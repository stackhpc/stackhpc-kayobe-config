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
    3. Ensure the `centos` user owns its own home folder
    ```
    sudo chown -R centos: ~
    ```

    4. For the storage nodes ensure the hostname is not FQDN

    ```
    sudo hostname "$(hostname -s)"
    ```

## Setup of Kayobe Config

The following steps are to be carried out from an ansible control host that can reach of nodes within the environment.

1. Install package dependencies

```
sudo dnf install -y python3-virtualenv
```

2. Clone Kayobe and the Kayobe multinode configuration

```
mkdir -p src\
cd src
git clone https://github.com/stackhpc/kayobe.git -b stackhpc/wallaby
git https://github.com/stackhpc/stackhpc-kayobe-config.git -b multinode-env
```

3. Create a virtual environment and install Kayobe

```
mkdir -p venvs
cd vevns
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
kayobe environment ci-multinode
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

1. Perform a control host configure

```
kayobe control host configure
```

2. Perform a overcloud configure

```
kayobe overcloud host configure
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