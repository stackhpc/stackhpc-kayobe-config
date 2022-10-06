# Multinode Test Environment 

The multinode test environment is intended as an easy method of deploying an openstack deployment with multiple baremetal nodes acting as compute/controllers and a seed.
Also storage nodes which back OpenStack such as Cinder, Glance and Nova are apart of the environment and are intended to run as virtual machines.

## Deploy Hosts & Preconfiguration
1. [Terraform Kayobe Multinode](https://github.com/stackhpc/terraform-kayobe-multinode) for instructions on deploying nodes within an OpenStack environment.
1. Due to some outstanding issues with the network and OS image ensure the following steps have been taken for each of the nodes:
    
    1. Edit `/etc/hosts` to include the following lines

    ```
    10.0.0.34 pelican pelican.service.compute.sms-lab.cloud
    10.205.3.187 pulp-server pulp-server.internal.sms-cloud
    ```
    1. Edit `/etc/resolv.conf` to include include the following line
    ```
    nameserver 10.209.0.5
    nameserver 10.209.0.3
    nameserver 10.209.0.4
    ```
    1. Run `sudo chown -R centos: ~`

1. For the storage nodes ensure the hostname is not FQDN by running `sudo hostname "$(hostname -s)"`

## Setup of Kayobe Config

The following steps are to be carried out from an ansible control host that can reach of nodes within the environment.

1. Install package dependencies

    > `sudo dnf install -y python3-virtualenv`

1. Clone Kayobe and the Kayobe multinode configuration

    > `mkdir -p src`\
    > `cd src`\
    > `git clone https://github.com/stackhpc/kayobe.git -b stackhpc/wallaby`\
    > `git https://github.com/stackhpc/stackhpc-kayobe-config.git -b multinode-env`

1. Create a virtual environment and install Kayobe

    > `mkdir -p venvs`\
    > `cd vevns`\
    > `virtualenv kayobe`\
    > `source kayobe/bin/activate`\
    > `pip install -U pip`\
    > `pip install ~/src/kayobe`

1. Install Ansible role and collection dependencies from Ansible Galaxy:

```
ansible-galaxy role install \
     -p ${KAYOBE_CONFIG_PATH}/ansible/roles \
     -r ${KAYOBE_CONFIG_PATH}/ansible/requirements.yml

ansible-galaxy collection install \
    -p ${KAYOBE_CONFIG_PATH}/ansible/collections \
    -r ${KAYOBE_CONFIG_PATH}/ansible/requirements.yml
```

1. Acquire the Ansible Vault password for this repository, and store a copy at `~/vault-pw` and load the contents as an environment variable

    > `export KAYOBE_VAULT_PASSWORD=$(cat ~/vault-pw)`

## Configuration of Kayobe Config

1. Activate the `ci-multinode` environment

    > `kayobe environment ci-multinode`

1. Ensure the `${KAYOBE_CONFIG_PATH}/environments/${KAYOBE_ENVIRONMENT}/inventory/hosts` is configured appropriately
```
[controllers]

[compute]

[seed]

[storage:children]

[ceph:children]

[mons]

[mgrs]

[osds]

[rgws]
```

1. Configure the vxlan vars found within `${KAYOBE_CONFIG_PATH}/ansible/configure-vxlan.yml` [See role documentation for more details](https://github.com/stackhpc/ansible-role-vxlan)

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

    > :warning: Must change `vxlan_vni` to another value to prevent interfering with another VXLAN on the same network :warning:

## Deploying Kayobe Config

With Kayobe Config configured as required you can proceed with deployment.

```
kayobe control host bootstrap
kayobe overcloud host configure
kayobe playbook run $KAYOBE_CONFIG_PATH/ansible/growroot.yml
kayobe overcloud host configure
kayobe overcloud service deploy
```