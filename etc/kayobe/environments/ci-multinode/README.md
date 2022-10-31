# Multinode Test Environment 

The multinode test environment is intended as an easy method of deploying an openstack deployment with multiple baremetal nodes acting as compute/controllers and a seed.
Also storage nodes which back OpenStack such as Cinder, Glance and Nova are apart of the environment and are intended to run as virtual machines.

## Deploy Hosts & Preconfiguration
1. [Terraform Kayobe Multinode](https://github.com/stackhpc/terraform-kayobe-multinode) for instructions on deploying nodes within an OpenStack environment.

2. Due to some outstanding issues with the network and OS image ensure the following steps have been taken for each of the nodes:

    1. Edit `/etc/hosts` to include the following lines

    ```
    10.0.0.34 pelican pelican.service.compute.sms-lab.cloud
    10.205.3.187 pulp-server pulp-server.internal.sms-cloud
    ```
    2. Edit `/etc/resolv.conf` to include include the following line
    ```
    nameserver 10.209.0.5
    nameserver 10.209.0.3
    nameserver 10.209.0.4
    ```
    3. If you are using Centos ensure the `centos` user owns its own home folder
    ```
    sudo chown -R centos: ~
    ```
    4. If you are using Centos ensure /home/stack does not exist (bug with DIB cache).
    ```
    sudo rm -fr /home/stack
    ```
    5. For the storage nodes ensure the hostname is not FQDN

    ```
    sudo hostnamectl set-hostname "$(hostname -s)"
    ```

## Setup of Kayobe Config

The following steps are to be carried out from an ansible control host that can reach of nodes within the environment.

1. Install package dependencies

```
sudo dnf install -y python3-virtualenv git
```

2. Clone Kayobe and the Kayobe multinode configuration

```
mkdir -p src
cd src
git clone https://github.com/stackhpc/kayobe.git -b stackhpc/wallaby
git clone https://github.com/stackhpc/stackhpc-kayobe-config.git -b multinode-env
```

3. Create a virtual environment and install Kayobe

```
mkdir -p venvs
cd venvs
virtualenv kayobe
source kayobe/bin/activate
pip install -U pip
pip install ~/src/kayobe
```

4. Acquire the Ansible Vault password for this repository, and store a copy at `~/vault-pw` and load the contents as an environment variable

```
export KAYOBE_VAULT_PASSWORD=$(cat ~/vault-pw)
```

5. Activate the `ci-multinode` environment

```
cd ../stackhpc-kayobe-config
source kayobe-env --environment ci-multinode
```

## Configuration of Kayobe Config

1. Ensure the `${KAYOBE_CONFIG_PATH}/environments/${KAYOBE_ENVIRONMENT}/inventory/hosts` is configured appropriately
```
[controllers]
kayobe-controller-01
kayobe-controller-02
kayobe-controller-03

[compute]
kayobe-compute-01
kayobe-compute-02

[seed]
kayobe-seed

[storage:children]
ceph

[ceph:children]
mons
mgrs
osds
rgws

[mons]
kayobe-storage-1
kayobe-storage-2
kayobe-storage-3
[mgrs]
kayobe-storage-1
kayobe-storage-2
kayobe-storage-3
[osds]
kayobe-storage-1
kayobe-storage-2
kayobe-storage-3
[rgws]
```

2. Ensure the `${KAYOBE_CONFIG_PATH}/environments/${KAYOBE_ENVIRONMENT}/tf-networks.yml` is configured appropriately
```
---
admin_cidr: 10.209.0.0/16
admin_allocation_pool_start: 0.0.0.0
admin_allocation_pool_end: 0.0.0.0
admin_bootproto: dhcp
admin_ips:
  kayobe-seed: 10.209.3.65
  kayobe-storage-01: 10.209.1.202
  kayobe-storage-02: 10.209.0.63
  kayobe-storage-03: 10.209.3.142
  kayobe-compute-01: 10.209.2.79
  kayobe-compute-02: 10.209.2.194
  kayobe-controller-01: 10.209.0.168
  kayobe-controller-02: 10.209.0.36
  kayobe-controller-03: 10.209.2.228
```

3. Configure the VXLAN interface for the `ALL` group 
{KAYOBE_CONFIG_PATH}/environments/${KAYOBE_ENVIRONMENT}/inventory/groups_vars/all/vxlan [See role documentation for more details](https://github.com/stackhpc/ansible-role-vxlan)

```
 vxlan_phys_dev: "{{ admin_oc_interface }}"
  vxlan_dstport: 4790
  vxlan_vni: 10
  vxlan_interfaces:
    - device: "vxlan{{ vxlan_vni }}"
      group: "{{ '239.0.0.0/8' | ansible.utils.next_nth_usable(vxlan_vni) }}"
```

> ⚠️ **_WARNING_** ⚠️
> 
> #### To avoid crosstalk between the existing VXLANs it important you change the following values;
> - vxlan_vni: this value is similar to VLAN ID however it is 24 bits in size (16,777,215) 

## Deploying Kayobe Config

With Kayobe Config configured as required you can proceed with deployment.

1. Perform a control host bootstrap

```
kayobe control host bootstrap
```

2. Perform a seed and overcloud host configure

```
kayobe seed host configure
kayobe overcloud host configure
```

3. If required, update host packages and reboot all the overcloud nodes by running
```
kayobe overcloud host package update --packages '*'
```

Reboot the system updates after upgrade the system packages

```
kayobe playbook run $KAYOBE_CONFIG_PATH/ansible/reboot.yml
```

or

```
kayobe overcloud host command run --command "shutdown -r +1 rebooting"  --become
```

4. Deploy CEPH cluster

```
kayobe playbook run $KAYOBE_CONFIG_PATH/ansible/cephadm-deploy.yml
kayobe playbook run $KAYOBE_CONFIG_PATH/ansible/cephadm.yml
kayobe playbook run $KAYOBE_CONFIG_PATH/ansible/cephadm-gather-keys.yml
```

5. Finally proceed with service deploy

```
kayobe overcloud service deploy
```

## Configuring OpenStack Resources

You can configure the OpenStack deployment using the [Openstack Config Multinode](https://github.com/stackhpc/openstack-config-multinode). The configuration applied should ensure that the OpenStack deployment has appropriate networks, flavours, security groups and images available. 

If need to access the network from your local machine or Ansible Control Host you can use `sshuttle` which operates as a transparent proxy over SSH. For example to access Horizon on the public network you can `sshuttle -r centos@${controller_ip} 192.168.39.0/24` This can also be used with `openstackclient`.


## Testing with Tempest


### Building Tempest Docker Container

It is important to test the various features and services of the OpenStack deployment. This can be achieved with the use of Tempest.

1. Install Docker on the Ansible Control Host

```
if $(which dnf 2>/dev/null >/dev/null); then
  sudo dnf config-manager \
      --add-repo \
      https://download.docker.com/linux/centos/docker-ce.repo
  sudo dnf install docker-ce
else
  sudo apt update
  sudo apt install -y docker.io
fi
```

2. Start the Docker service

```
sudo systemctl start docker
```

3. Inside the kayobe-config root directory initialise the submodules

```
git submodule init
git submodule update
```

4. Build Docker image

```
sudo DOCKER_BUILDKIT=1 docker build --file .automation/docker/kayobe/Dockerfile --tag kayobe:latest .
```

### Running Tempest Tests

1. Make a directory to store the tempest outputs

```
mkdir -p tempest-artifacts
```

2. Ensure the private key for kayobe has been set

```
export KAYOBE_AUTOMATION_SSH_PRIVATE_KEY=$(cat ~/.ssh/id_rsa)
```

3. Run the tempest test suite


```
sudo -E docker run -it --rm --network host -v $(pwd):/stack/kayobe-automation-env/src/kayobe-config -v $(pwd)/tempest-artifacts:/stack/tempest-artifacts -e KAYOBE_ENVIRONMENT -e KAYOBE_VAULT_PASSWORD -e KAYOBE_AUTOMATION_SSH_PRIVATE_KEY kayobe:latest /stack/kayobe-automation-env/src/kayobe-config/.automation/pipeline/tempest.sh -e ansible_user=stack
```

Whilst the tests are running you can view the logs in realtime by running `ssh centos@seed 'sudo docker logs --follow $(sudo docker ps -q)'

Once the test suite has finished you can view the contents of `${KAYOBE_CONFIG_PATH}/tempest-artifacts/failed_tests` which should be empty. You may also download a copy of `rally-verify-report.html` to review allowing you to ensure all expected tests were carried out. `scp centos@{{ ANSIBLE_HOST_IP }}:/home/centos/src/kayobe-config/tempest-artifacts/rally-verify-report.html ~/Downloads/rally-verify-report.html`
