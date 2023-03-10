=============================
StackHPC Kayobe Configuration
=============================

This repository provides a base Kayobe configuration for the Xena release
of StackHPC OpenStack.

Documentation is hosted on `readthedocs.io
<https://stackhpc-kayobe-config.readthedocs.io/en/stackhpc-xena/index.html>`__,
and includes release notes.

Resources
=========

* Kayobe documentation: https://docs.openstack.org/kayobe/xena/
* Kayobe source: https://opendev.org/openstack/kayobe
* Kayobe bugs: https://storyboard.openstack.org/#!/project/openstack/kayobe-config
* IRC: #openstack-kolla

Configuration Diff
------------------

To test what changes your config change will create on disk, you
can use the following configuration diff tool.

While typically it is executed using gitlab ci, you can do it
manually by first building a docker file for the current kayobe
version::
    cd .automation/docker/kayobe/
    docker build . -t kayobe

Then you can run this, to diff your current code against the target branch,
which in this case is cumulus/train-preprod::
    RUN_LOCAL_DOCKER_IMAGE=kayobe .automation/run-local.sh .automation/pipeline/config-diff.sh cumulus/train-preprod -- --env KAYOBE_VAULT_PASSWORD=$(< ~/.ansible-vault-password)

Kayobe Extensions
-----------------

Accelerators
~~~~~~~~~~~~

GPUs
^^^^

It is possible to configure PCI passthrough by adding a hypervisor to one of the
gpu_passthrough groups. The following hardware is currently supported:

- Nvidia A100

The group mappings from hardware type to kayobe inventory group are as follows:

- Nvidia A100: gpu_passthrough_a100

New hardware definitions can be added to ``$KAYOBE_CONFIG_PATH/inventory/group_vars/all/gpu``.

If you want to make a modification apply to all hosts you can use the convenience file:

``$KAYOBE_CONFIG_PATH/gpu.yml``. For example, you could reconfigure the product_id for
the PCI device::
  gpu_passthrough_a100_product_id: 0xdead

Alternatively, you can use group_vars to modify it for a subset of the hosts.

Example: Passing through and A100 GPU
.....................................

Add the target host to the gpu_passthrough_a100 via the kayobe inventory::

  [gpu_passthrough_a100]
  my-compute-host-1


It is recommended to configure the mappings in the following file:
``$KAYOBE_CONFIG_PATH/inventory/gpu_passthrough``.

You will need to run the following commands:

- kayobe overcloud host configure
  - This will trigger the hook to perform the OS level configuration
  - You will be required to reboot the hypervisor
- kayobe overcloud service deploy
  - This will reconfigure nova to allow passthrough of the device

SRIOV
^^^^^

To enable SRIOV on a network card, you need to define the variable,
``sriov_devices``. This describes the devices and how many virtual functions
to enable. You will also need to add the host to the SRIOV group in the kayobe
inventory. This will configure the hook to perform the OS level configuration.

Example: Enabling SRIOV on a hypervisor
........................................

Add all the hosts you wish to configure to a group in the kayobe inventory.
The hosts should all have identical network card device names for the card
you wish to enable SRIOV on e.g eth0.

Configure group_vars to describe the number of virtual functions and how
they map to the physical networks configured in openstack::

  sriov_devices:
    - device: eth0
      numvfs: 16
  sriov_physnet_mappings:
    physnet1: eth0

The convention is use a file named ``sriov``. For example, if your group was called
``compute-connectx6``, the suggested path would be:
``$KAYOBE_CONFIG_PATH/inventory/group_vars/compute-connectx6/sriov``.

Also add your host to the sriov group in the kayobe inventory:

  [sriov:children]
  compute-connectx6

It is recommended to configure the mappings in the following file:
``$KAYOBE_CONFIG_PATH/inventory/sriov``.

You will need to run the following commands:

- kayobe overcloud host configure
  - This will trigger the hook to perform the OS level configuration
  - You will be required to reboot the hypervisor
- kayobe overcloud service deploy
  - This will reconfigure nova to allow passthrough of the device
