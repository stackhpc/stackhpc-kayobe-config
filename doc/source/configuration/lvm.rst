.. _lvm:

===
LVM
===

StackHPC Kayobe configuration provides Logical Volume Manager (LVM)
configuration that is compatible with the included :ref:`host-images`
configuration. The configuration uses the :kayobe-doc:`LVM
<configuration/reference/hosts.html#lvm>` host configuration functionality of
Kayobe.

The LVM configuration is provided in
``etc/kayobe/inventory/group_vars/all/stackhpc/lvm``. This allows configuration
variables to be overridden on a per-group or per-host basis (which would not be
possible for an "extra variable" in ``etc/kayobe/*.yml``). This configuration
is not used by default, and must be actively opted into. This can be done as
follows:

.. code-block:: yaml

   controller_lvm_groups:
     - "{{ stackhpc_lvm_group_rootvg }}"

This will configure the standard set of logical volumes for the ``rootvg``
volume group on controller hosts.

The disks in this volume group are configured via
``stackhpc_lvm_group_rootvg_disks``, and by default this contains a single
disk, matched by a partition label of ``root`` (as used in the standard
:ref:`host-images`).

The size of each LV is configurable via the following variables:

.. code-block:: yaml

   # StackHPC LVM lv_swap LV size.
   stackhpc_lvm_lv_swap_size: 16g

   # StackHPC LVM lv_root LV size.
   stackhpc_lvm_lv_root_size: 50g

   # StackHPC LVM lv_tmp LV size.
   stackhpc_lvm_lv_tmp_size: 10g

   # StackHPC LVM lv_var LV size.
   stackhpc_lvm_lv_var_size: 20g

   # StackHPC LVM lv_var_tmp LV size.
   stackhpc_lvm_lv_var_tmp_size: 2g

   # StackHPC LVM lv_log LV size.
   stackhpc_lvm_lv_log_size: 20g

   # StackHPC LVM lv_audit LV size.
   stackhpc_lvm_lv_audit_size: 10g

   # StackHPC LVM lv_home LV size.
   stackhpc_lvm_lv_home_size: 10g

Additional LVs may be configured via ``stackhpc_lvm_group_rootvg_lvs_extra``. A
common requirement is to have ``/var/lib/docker/`` mounted on a separate LV,
so this has been made convenient to achieve:

.. code-block:: yaml

   stackhpc_lvm_group_rootvg_lvs_extra:
     - "{{ stackhpc_lvm_lv_docker }}"

   # StackHPC LVM lv_docker LV size.
   stackhpc_lvm_lv_docker_size: 100%FREE

It may be desirable to use a lower percentage of the free space, in case
another LV needs to be grown at a later date.

Growroot playbook
=================

A ``growroot.yml`` custom playbook is provided that can be used to grow the
partition and LVM Physical Volume (PV) of the root Volume Group (VG). This
allows for expansion of Logical Volumes (LVs) in that VG.

The following variables may be used to configure the playbook:

``growroot_group``
  Host pattern against which to target the playbook. Default is ``overcloud``.
``growroot_vg``
  Name of the VG containing the PV to grow. Default is ``rootvg`` to match the
  standard :ref:`host image configuration <host-images>`.

This playbook may be used as a host configure pre hook, e.g. for overcloud
hosts:

.. code-block:: console

   mkdir -p ${KAYOBE_CONFIG_PATH}/hooks/overcloud-host-configure/pre.d
   cd ${KAYOBE_CONFIG_PATH}/hooks/overcloud-host-configure/pre.d
   ln -s ../../../ansible/growroot.yml 30-growroot.yml
