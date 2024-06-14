===========================
Managing and Operating Ceph
===========================

Working with Cephadm
====================

This documentation provides guide for Ceph operations. For deploying Ceph,
please refer to :ref:`cephadm-kayobe` documentation.

cephadm configuration location
------------------------------

In kayobe-config repository, under ``etc/kayobe/cephadm.yml`` (or in a specific
Kayobe environment when using multiple environment, e.g.
``etc/kayobe/environments/<Environment Name>/cephadm.yml``)

StackHPC's cephadm Ansible collection relies on multiple inventory groups:

- ``mons``
- ``mgrs``
- ``osds``
- ``rgws`` (optional)

Those groups are usually defined in ``etc/kayobe/inventory/groups``.

Running cephadm playbooks
-------------------------

In kayobe-config repository, under ``etc/kayobe/ansible`` there is a set of
cephadm based playbooks utilising stackhpc.cephadm Ansible Galaxy collection.

- ``cephadm.yml`` - runs the end to end process starting with deployment and
  defining EC profiles/crush rules/pools and users
- ``cephadm-crush-rules.yml`` - defines Ceph crush rules according
- ``cephadm-deploy.yml`` - runs the bootstrap/deploy playbook without the
  additional playbooks
- ``cephadm-ec-profiles.yml`` - defines Ceph EC profiles
- ``cephadm-gather-keys.yml`` - gather Ceph configuration and keys and populate
  kayobe-config
- ``cephadm-keys.yml`` - defines Ceph users/keys
- ``cephadm-pools.yml`` - defines Ceph pools\

Running Ceph commands
---------------------

Ceph commands are usually run inside a ``cephadm shell`` utility container:

.. code-block:: console

   # From storage host
   sudo cephadm shell

Operating a cluster requires a keyring with an admin access to be available for Ceph
commands. Cephadm will copy such keyring to the nodes carrying
`_admin <https://docs.ceph.com/en/latest/cephadm/host-management/#special-host-labels>`__
label - present on MON servers by default when using
`StackHPC Cephadm collection <https://github.com/stackhpc/ansible-collection-cephadm>`__.

Adding a new storage node
-------------------------

Add a node to a respective group (e.g. osds) and run ``cephadm-deploy.yml``
playbook.

.. note::
   To add other node types than osds (mons, mgrs, etc) you need to specify
   ``-e cephadm_bootstrap=True`` on playbook run.

Removing a storage node
-----------------------

First drain the node

.. code-block:: console

   # From storage host
   sudo cephadm shell
   ceph orch host drain <host>

Once all daemons are removed - you can remove the host:

.. code-block:: console

   # From storage host
   sudo cephadm shell
   ceph orch host rm <host>

And then remove the host from inventory (usually in
``etc/kayobe/inventory/overcloud``)

Additional options/commands may be found in
`Host management <https://docs.ceph.com/en/latest/cephadm/host-management/>`_

Replacing failing drive
-----------------------

A failing drive in a Ceph cluster will cause OSD daemon to crash.
In this case Ceph will go into `HEALTH_WARN` state.
Ceph can report details about failed OSDs by running:

.. code-block:: console
   # From storage host
   sudo cephadm shell
   ceph health detail

.. note ::

   Remember to run ceph/rbd commands from within ``cephadm shell``
   (preferred method) or after installing Ceph client. Details in the
   official `documentation <https://docs.ceph.com/en/latest/cephadm/install/#enable-ceph-cli>`__.
   It is also required that the host where commands are executed has admin
   Ceph keyring present - easiest to achieve by applying
   `_admin <https://docs.ceph.com/en/latest/cephadm/host-management/#special-host-labels>`__
   label (Ceph MON servers have it by default when using
   `StackHPC Cephadm collection <https://github.com/stackhpc/ansible-collection-cephadm>`__).

A failed OSD will also be reported as down by running:

.. code-block:: console

   ceph osd tree

Note the ID of the failed OSD.

The failed disk is usually logged by the Linux kernel too:

.. code-block:: console

   # From storage host
   dmesg -T

Cross-reference the hardware device and OSD ID to ensure they match.
(Using `pvs` and `lvs` may help make this connection).

See upstream documentation:
https://docs.ceph.com/en/latest/cephadm/services/osd/#replacing-an-osd

In case where disk holding DB and/or WAL fails, it is necessary to recreate
all OSDs that are associated with this disk - usually NVMe drive. The
following single command is sufficient to identify which OSDs are tied to
which physical disks:

.. code-block:: console

   ceph device ls

Once OSDs on failed disks are identified, follow procedure below.

If rebooting a Ceph node, first set ``noout`` to prevent excess data
movement:

.. code-block:: console

   # From storage host
   sudo cephadm shell
   ceph osd set noout

Reboot the node and replace the drive

Unset noout after the node is back online

.. code-block:: console

   # From storage host
   sudo cephadm shell
   ceph osd unset noout

Remove the OSD using Ceph orchestrator command:

.. code-block:: console

   # From storage host
   sudo cephadm shell
   ceph orch osd rm <ID> --replace

After removing OSDs, if the drives the OSDs were deployed on once again become
available, cephadm may automatically try to deploy more OSDs on these drives if
they match an existing drivegroup spec.
If this is not your desired action plan - it's best to modify the drivegroup
spec before (``cephadm_osd_spec`` variable in ``etc/kayobe/cephadm.yml``).
Either set ``unmanaged: true`` to stop cephadm from picking up new disks or
modify it in some way that it no longer matches the drives you want to remove.

Host maintenance
----------------

https://docs.ceph.com/en/latest/cephadm/host-management/#maintenance-mode

Upgrading
---------

https://docs.ceph.com/en/latest/cephadm/upgrade/


Troubleshooting
===============

Inspecting a Ceph Block Device for a VM
---------------------------------------

To find out what block devices are attached to a VM, go to the hypervisor that
it is running on (an admin-level user can see this from ``openstack server
show``).

On this hypervisor, enter the libvirt container:

.. code-block:: console

   # From hypervisor host
   docker exec -it nova_libvirt /bin/bash

Find the VM name using libvirt:

.. code-block:: console

   (nova-libvirt)[root@compute-01 /]# virsh list
    Id    Name                State
   ------------------------------------
    1     instance-00000001   running

Now inspect the properties of the VM using ``virsh dumpxml``:

.. code-block:: console

   (nova-libvirt)[root@compute-01 /]# virsh dumpxml instance-00000001 | grep rbd
         <source protocol='rbd' name='<nova rbd pool>/51206278-e797-4153-b720-8255381228da_disk'>

On a Ceph node, the RBD pool can be inspected and the volume extracted as a RAW
block image:

.. code-block:: console

   # From storage host
   sudo cephadm shell
   rbd ls <nova rbd pool>
   rbd export <nova rbd pool>/51206278-e797-4153-b720-8255381228da_disk blob.raw

The raw block device (blob.raw above) can be mounted using the loopback device.

Inspecting a QCOW Image using LibGuestFS
----------------------------------------

The virtual machine's root image can be inspected by installing
libguestfs-tools and using the guestfish command:

.. code-block:: console

   # From storage host
   export LIBGUESTFS_BACKEND=direct
   guestfish -a blob.qcow
   ><fs> run
    100% [XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX] 00:00
   ><fs> list-filesystems
   /dev/sda1: ext4
   ><fs> mount /dev/sda1 /
   ><fs> ls /
   bin
   boot
   dev
   etc
   home
   lib
   lib64
   lost+found
   media
   mnt
   opt
   proc
   root
   run
   sbin
   srv
   sys
   tmp
   usr
   var
   ><fs> quit
