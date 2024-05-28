==========================
Migrating virtual machines
==========================

To see where all virtual machines are running on the hypervisors:

.. code-block:: console

   admin# openstack server list --all-projects --long

To move a virtual machine with shared storage or booted from volume from one hypervisor to another, for example to
hypervisor-01:

.. code-block:: console

   admin# openstack server migrate --live-migration --host hypervisor-01 <VM name or uuid>

To move a virtual machine with local disks:

.. code-block:: console

   admin# openstack  server migrate --live-migration --block-migration --host hypervisor-01 <VM name or uuid>
