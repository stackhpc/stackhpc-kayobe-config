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
    5. If you are using Centos ensure pvresize has been executed on your partition (computes and controllers BMs)
    ```
    pvresize /dev/sda3
    ```
    6. For the storage nodes ensure the hostname is not FQDN

    ```
    sudo hostnamectl set-hostname "$(hostname -s)"
    ```
    7. If you are using Centos ensure pvresize has been executed on your partition (storage nodes VMs)
    ```
    pvresize /dev/vda3
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

6. Add hooks for `configure-vxlan.yml` and `growroot.yml`

```
mkdir -p ${KAYOBE_CONFIG_PATH}/hooks/overcloud-host-configure/pre.d
cd ${KAYOBE_CONFIG_PATH}/hooks/overcloud-host-configure/pre.d
ln -s ${KAYOBE_CONFIG_PATH}/ansible/growroot.yml 40-growroot.yml
```
```
mkdir -p ${KAYOBE_CONFIG_PATH}/hooks/overcloud-host-configure/post.d
cd ${KAYOBE_CONFIG_PATH}/hooks/overcloud-host-configure/post.d
ln -s ${KAYOBE_CONFIG_PATH}/ansible/configure-vxlan.yml 50-configure-vxlan.yml
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

[seed]

[storage:children]
ceph

[ceph:children]
mons
mgrs
osds
rgws

[mons]
kayobe-ceph-1
kayobe-ceph-2
kayobe-ceph-3
[mgrs]
kayobe-ceph-1
kayobe-ceph-2
kayobe-ceph-3
[osds]
kayobe-ceph-1
kayobe-ceph-2
kayobe-ceph-3
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
  kayobe-ceph-1: 10.209.0.76
  kayobe-ceph-2: 10.209.3.225
  kayobe-ceph-3: 10.209.1.20
  kayobe-compute-01: 10.209.2.79
  kayobe-controller-01: 10.209.0.168
  kayobe-controller-02: 10.209.0.36
  kayobe-controller-03: 10.209.2.228
```

3. Configure the vxlan vars found within `${KAYOBE_CONFIG_PATH}/ansible/configure-vxlan.yml` [See role documentation for more details](https://github.com/stackhpc/ansible-role-vxlan)

> **_NOTE:_** this will change be moved in a future commit

```
vars:
    vxlan_vni: 10
    vxlan_phys_dev: "{{ admin_oc_net_name | net_interface }}"
    vxlan_dstport: 4790
    vxlan_interfaces:
        - device: vxlan10
          group: 224.0.0.10
          bridge: breth
```

> ⚠️ **_WARNING:_** change `vxlan_vni` to another value to prevent interfering with another VXLAN on the same network. Also change the change group address to another [multicast address](https://en.wikipedia.org/wiki/Multicast_address) ⚠️

## Deploying Kayobe Config

With Kayobe Config configured as required you can proceed with deployment.

1. Perform a control host bootstrap

```
kayobe control host bootstrap
```

2. Perform a overcloud configure

```
kayobe overcloud host configure
```

2a. (OPTIONAL) If required, update host packages and reboot all the overcloud nodes by running
```
kayobe overcloud host package update --packages '*'
```
After successfull updates

```
kayobe playbook run $KAYOBE_CONFIG_PATH/ansible/reboot.yml
```
or
```
kayobe overcloud host command run --command "shutdown -r +1 rebooting"  --become
```

3. Deploy CEPH cluster

```
kayobe playbook run $KAYOBE_CONFIG_PATH/ansible/cephadm-deploy.yml
kayobe playbook run $KAYOBE_CONFIG_PATH/ansible/cephadm.yml
kayobe playbook run $KAYOBE_CONFIG_PATH/ansible/cephadm-gather-keys.yml
```

4. Finally proceed with service deploy

```
kayobe overcloud service deploy
```

## Testing with Tempest

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

5. Configure some test resources


```
kayobe playbook run etc/kayobe/ansible/configure-aio-resources.yml
```

6. Copy `ci-aio` tempest overrides for the current environment or provide your own

```
cp .automation.conf/tempest/tempest-{ci-aio,$KAYOBE_ENVIRONMENT}.overrides.conf 
```

7. Make a directory to store the tempest outputs

```
mkdir -p tempest-artifacts
```

8. Ensure the private key for kayobe has been set

```
export KAYOBE_AUTOMATION_SSH_PRIVATE_KEY=$(cat ~/.ssh/id_rsa)
```

9. Update your tempest inventory file with your controller hostname

```
vi ~/src/stackhpc-kayobe-config/etc/kayobe/environments/ci-multinode/inventory/kayobe-automation
```

10. Run the tempest test suite

```
sudo -E docker run -it --rm --network host -v $(pwd):/stack/kayobe-automation-env/src/kayobe-config -v $(pwd)/tempest-artifacts:/stack/tempest-artifacts -e KAYOBE_ENVIRONMENT -e KAYOBE_VAULT_PASSWORD -e KAYOBE_AUTOMATION_SSH_PRIVATE_KEY kayobe:latest /stack/kayobe-automation-env/src/kayobe-config/.automation/pipeline/tempest.sh -e ansible_user=stack
```

Once the test suite has finished you can view the contents of `${KAYOBE_CONFIG_PATH}/tempest-artifacts/failed_tests` which should be empty. You may also download a copy of `rally-verify-report.html` to review allowing you to ensure all expected tests were carried out. `scp centos@{{ ANSIBLE_HOST_IP }}:/home/centos/src/kayobe-config/tempest-artifacts/rally-verify-report.html ~/Downloads/rally-verify-report.html`
