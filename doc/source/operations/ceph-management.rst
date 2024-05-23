==========================
Managing Ceph with Cephadm
==========================

cephadm configuration location
==============================

In kayobe-config repository, under ``etc/kayobe/cephadm.yml`` (or in a specific
Kayobe environment when using multiple environment, e.g.
``etc/kayobe/environments/production/cephadm.yml``)

StackHPC's cephadm Ansible collection relies on multiple inventory groups:

- ``mons``
- ``mgrs``
- ``osds``
- ``rgws`` (optional)

Those groups are usually defined in ``etc/kayobe/inventory/groups``.

Running cephadm playbooks
=========================

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
=====================

Ceph commands are usually run inside a ``cephadm shell`` utility container:

.. code-block:: console

   # From the node that runs Ceph
   ceph# sudo cephadm shell

Operating a cluster requires a keyring with an admin access to be available for Ceph
commands. Cephadm will copy such keyring to the nodes carrying
`_admin <https://docs.ceph.com/en/quincy/cephadm/host-management/#special-host-labels>`__
label - present on MON servers by default when using
`StackHPC Cephadm collection <https://github.com/stackhpc/ansible-collection-cephadm>`__.

Adding a new storage node
=========================

Add a node to a respective group (e.g. osds) and run ``cephadm-deploy.yml``
playbook.

.. note::
   To add other node types than osds (mons, mgrs, etc) you need to specify
   ``-e cephadm_bootstrap=True`` on playbook run.

Removing a storage node
=======================

First drain the node

.. code-block:: console

   ceph# cephadm shell
   ceph# ceph orch host drain <host>

Once all daemons are removed - you can remove the host:

.. code-block:: console

   ceph# cephadm shell
   ceph# ceph orch host rm <host>

And then remove the host from inventory (usually in
``etc/kayobe/inventory/overcloud``)

Additional options/commands may be found in
`Host management <https://docs.ceph.com/en/latest/cephadm/host-management/>`_

Replacing a Failed Ceph Drive
=============================

Once an OSD has been identified as having a hardware failure,
the affected drive will need to be replaced.

If rebooting a Ceph node, first set ``noout`` to prevent excess data
movement:

.. code-block:: console

   ceph# cephadm shell
   ceph# ceph osd set noout

Reboot the node and replace the drive

Unset noout after the node is back online

.. code-block:: console

   ceph# cephadm shell
   ceph# ceph osd unset noout

Remove the OSD using Ceph orchestrator command:

.. code-block:: console

   ceph# cephadm shell
   ceph# ceph orch osd rm <ID> --replace

After removing OSDs, if the drives the OSDs were deployed on once again become
available, cephadm may automatically try to deploy more OSDs on these drives if
they match an existing drivegroup spec.
If this is not your desired action plan - it's best to modify the drivegroup
spec before (``cephadm_osd_spec`` variable in ``etc/kayobe/cephadm.yml``).
Either set ``unmanaged: true`` to stop cephadm from picking up new disks or
modify it in some way that it no longer matches the drives you want to remove.
