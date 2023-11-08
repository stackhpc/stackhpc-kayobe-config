==========================
Migrating to Rocky Linux 9
==========================

Overview
========

This document describes how to migrate systems from CentOS Stream 8 to Rocky Linux 9.
This procedure must be performed on CentOS Stream 8 OpenStack Yoga systems before it is possible to upgrade to OpenStack Zed.
It is possible to perform a rolling migration to ensure service is not disrupted. This section covers the steps required to perform such a migration.

For hosts running CentOS 8 Stream, the migration process has a simple structure:

- Remove a CentOS Stream 8 host from service
- Reprovision the host with a Rocky Linux 9 image
- Configure and deploy the host with Rocky Linux 9 containers

While it is technically possible to migrate hosts in any order, it is strongly recommended that migrations for one type of node are completed before moving on to the next i.e. all compute node migrations are performed before all storage node migrations.

The order of node groups is less important, however it is arguably safest to perform controller node migrations first, given that they are the most complex and it is easiest to revert their state in the event of a failure.
This guide covers the following types of hosts:

- Controllers
- Compute hosts
- Storage hosts
- Seed

The following types of hosts will be covered in future:

- Seed hypervisor
- Ansible control host
- Wazuh manager

Resources
=========

* `Kolla Ansible Rocky Linux 9 migration documentation <https://docs.openstack.org/kolla-ansible/yoga/user/rocky-linux-9.html>`__

Necessary patches
=================

This section lists some patches that are necessary for the migration to complete successfully.

The following patches have been **merged** to the downstream StackHPC ``stackhpc/yoga`` branches:

-  https://review.opendev.org/c/openstack/kayobe/+/898563 (to fix ``kayobe overcloud deprovision``)
-  https://review.opendev.org/c/openstack/kayobe/+/898284 (if deployment predates Ussuri)

   - TODO: Put this into the procedure.
   -  **Must reprocess inspection data to update IPA kernel URL (see
      release note)**

-  https://review.opendev.org/c/openstack/kayobe/+/898777
-  https://review.opendev.org/c/openstack/kayobe/+/898915
-  https://review.opendev.org/c/openstack/kayobe/+/898905
-  https://review.opendev.org/c/openstack/kolla/+/878835
-  https://review.opendev.org/c/openstack/kayobe/+/898434 (if seeing slow fact gathering)
-  https://review.opendev.org/c/openstack/kolla-ansible/+/900034
-  https://review.opendev.org/c/openstack/kolla-ansible/+/897667
-  https://review.opendev.org/c/openstack/nova/+/898554

Configuration
=============

Make the following changes to your Kayobe configuration:

- Merge in the latest ``stackhpc-kayobe-config`` ``stackhpc/yoga`` branch.
- Set ``os_distribution`` to ``rocky`` in ``etc/kayobe/globals.yml``.
- Set ``os_release`` to ``"9"`` in ``etc/kayobe/globals.yml``.
- If you are using Kayobe multiple environments, add the following into
  ``kayobe-config/etc/kayobe/environments/<env>/kolla/config/nova.conf``
  (as Kolla custom service config environment merging is not supported in
  Yoga). See `this PR
  <https://github.com/stackhpc/stackhpc-kayobe-config/pull/648>`__ for details.

  .. code-block:: ini

     [libvirt]
     hw_machine_type = x86_64=q35
     num_pcie_ports = 16

  This change does not need to be applied before migrating to Rocky Linux 9, but it should cause no harm to do so.
  Note that this will not affect existing VMs, only newly created VMs.

Prerequisites
=============

Before starting the upgrade, ensure any appropriate prerequisites are
satisfied. These will be specific to each deployment, but here are some
suggestions:

* Ensure that there is sufficient hypervisor capacity to drain
  at least one node.
* If using Ironic for bare metal compute, ensure that at least one node is
  available for testing provisioning.
* Ensure that expected test suites are passing, e.g. Tempest.
* Resolve any Prometheus alerts.
* Check for unexpected ``ERROR`` or ``CRITICAL`` messages in Kibana/OpenSearch
  Dashboard.
* Check Grafana dashboards.

Migrate to OpenSearch
---------------------

Elasticsearch/Kibana should be migrated to OpenSearch.

- Read the `Kolla Ansible OpenSearch migration
  docs <https://docs.openstack.org/kolla-ansible/yoga/reference/logging-and-monitoring/central-logging-guide-opensearch.html#migration>`__
- If necessary, take a backup of the Elasticsearch data.
- Ensure ``kolla_enable_elasticsearch`` is unset in ``etc/kayobe/kolla.yml``
- Set ``kolla_enable_opensearch: true`` in ``etc/kayobe/kolla.yml``
- ``kayobe kolla ansible run opensearch-migration``
- If old indices are detected, they may be removed by running ``kayobe kolla ansible run opensearch-migration -e prune_kibana_indices=true``

Sync Release Train artifacts
----------------------------

New `StackHPC Release Train <../configuration/release-train>` content should be
synced to the local Pulp server. This includes host packages (Deb/RPM) and
container images.

To sync host packages:

.. code-block:: console

   kayobe playbook run $KAYOBE_CONFIG_PATH/ansible/pulp-repo-sync.yml
   kayobe playbook run $KAYOBE_CONFIG_PATH/ansible/pulp-repo-publish.yml

Once the host package content has been tested in a test/staging environment, it
may be promoted to production:

.. code-block:: console

   kayobe playbook run $KAYOBE_CONFIG_PATH/ansible/pulp-repo-promote-production.yml

To sync container images:

.. code-block:: console

   kayobe playbook run $KAYOBE_CONFIG_PATH/ansible/pulp-container-sync.yml
   kayobe playbook run $KAYOBE_CONFIG_PATH/ansible/pulp-container-publish.yml

Build locally customised container images
-----------------------------------------

.. note::

   The container images are provided by StackHPC Release Train are
   suitable for most deployments. In this case, this step can be skipped.

In some cases it is necessary to build some or all images locally to apply
customisations. In order to do this it is necessary to set
``stackhpc_pulp_sync_for_local_container_build`` to ``true`` before
syncing container images.

To build the overcloud images locally and push them to the local Pulp server:

.. code-block:: console

   kayobe overcloud container image build --push

It is possible to build a specific set of images by supplying one or more
image name regular expressions:

.. code-block:: console

   kayobe overcloud container image build --push ironic- nova-api

Deploy latest CentOS Stream 8 images
------------------------------------

Make sure you deploy the latest CentOS Stream 8 containers prior to
this migration:

.. code-block:: console

   kayobe overcloud service deploy

Controllers
===========

Migrate controllers *one by one*, ideally migrating the host with the Virtual
IP (VIP) last.

Potential issues
----------------

-  MariaDB had serious issues one time during testing, after the
   first controller was migrated. The solution in that instance was to
   restart the container on the two original CS8 hosts. The behaviour
   has not been observed again when running
   ``kayobe overcloud database recover`` between migrations. It can't be
   said for sure whether this is a genuine solution or the bug just
   hasn’t occurred these times during testing.
-  Issues have been seen when attempting to backup the MariaDB database,
   ``mariabackup`` was segfaulting. This was avoided by reverting to an old
   MariaDB container image by adding the following in
   ``etc/kayobe/kolla/globals.yml``:

   .. code-block:: yaml

      mariabackup_image_full: "{{ docker_registry }}/stackhpc/rocky-source-mariadb-server:yoga-20230310T170929"

Full procedure for one host
---------------------------

1. `Back up your database
   <https://docs.openstack.org/kayobe/yoga/administration/overcloud.html#performing-database-backups>`__

2. If using OVN, check OVN northbound DB cluster state on all controllers:

   .. code:: console

      kayobe overcloud host command run --command 'docker exec -it ovn_nb_db ovs-appctl -t /run/ovn/ovnnb_db.ctl cluster/status OVN_Northbound' --show-output -l controllers

3. If using OVN, check OVN southbound DB cluster state on all controllers:

   .. code:: console

      kayobe overcloud host command run --command 'docker exec -it ovn_sb_db ovs-appctl -t /run/ovn/ovnsb_db.ctl cluster/status OVN_Southbound' --show-output -l controllers

4. If the controller is running Ceph services:

   1. Set host in maintenance mode:

      .. code-block:: console

         ceph orch host maintenance enter <hostname>

   2. Check there's nothing remaining on the host:

      .. code-block:: console

         ceph orch ps <hostname>

5. Deprovision the controller:

   .. code:: console

      kayobe overcloud deprovision -l <hostname>

6. Reprovision the controller:

   .. code:: console

      kayobe overcloud provision -l <hostname>

7. Host configure:

   .. code:: console

      kayobe overcloud host configure -l <hostname> -kl <hostname>

8. If the controller is running Ceph OSD services:

   1. Make sure the cephadm public key is in ``authorized_keys`` for stack or
      root user - depends on your setup. For example, your SSH key may
      already be defined in ``users.yml`` . If in doubt, run the cephadm
      deploy playbook to copy the SSH key and install the cephadm binary.

      .. code-block:: console

         kayobe playbook run $KAYOBE_CONFIG_PATH/ansible/cephadm-deploy.yml

   2. Take the host out of maintenance mode:

      .. code-block:: console

         ceph orch host maintenance exit <hostname>

   3. Make sure that everything is back in working condition before moving
      on to the next host:

      .. code-block:: console

         ceph -s
         ceph -w

9. Service deploy on all controllers:

   .. code:: console

      kayobe overcloud service deploy -kl controllers

10. If using OVN, check OVN northbound DB cluster state on all controllers to see if the new host has joined:

    .. code:: console

       kayobe overcloud host command run --command 'docker exec -it ovn_nb_db ovs-appctl -t /run/ovn/ovnnb_db.ctl cluster/status OVN_Northbound' --show-output -l controllers

11. If using OVN, check OVN southbound DB cluster state on all controllers to see if the new host has joined:

    .. code:: console

       kayobe overcloud host command run --command 'docker exec -it ovn_sb_db ovs-appctl -t /run/ovn/ovnsb_db.ctl cluster/status OVN_Southbound' --show-output -l controllers

12. Some MariaDB instability has been observed. The exact cause is unknown but
    the simplest fix seems to be to run the Kayobe database recovery tool
    between migrations.

    .. code:: console

       kayobe overcloud database recover

After each controller has been migrated you may wish to perform some smoke testing, check for alerts and errors etc.

Compute
=======

Compute nodes can be migrated to Rocky Linux 9 in batches.
The possible batches depend on a number of things:

* willingness for instance reboots and downtime
* available spare hypervisor capacity
* sizes of groups of compatible hypervisors

Potential issues
----------------

Nothing yet!

Full procedure for one batch of hosts
-------------------------------------

1. Disable the Nova compute service and drain it of VMs using live migration.
   If any VMs fail to migrate, they may be cold migrated or powered off:

   .. code-block:: console

      kayobe playbook run $KAYOBE_CONFIG_PATH/ansible/nova-compute-{disable,drain}.yml --limit <host>

2. If the compute node is running Ceph OSD services:

   1. Set host in maintenance mode:

      .. code-block:: console

         ceph orch host maintenance enter <hostname>

   2. Check there's nothing remaining on the host:

      .. code-block:: console

         ceph orch ps <hostname>

3. Deprovision the compute node:

   .. code:: console

      kayobe overcloud deprovision -l <hostname>

4. Reprovision the compute node:

   .. code:: console

      kayobe overcloud provision -l <hostname>

5. Host configure:

   .. code:: console

      kayobe overcloud host configure -l <hostname> -kl <hostname>

6. If the compute node is running Ceph OSD services:

   1. Make sure the cephadm public key is in ``authorized_keys`` for stack or
      root user - depends on your setup. For example, your SSH key may
      already be defined in ``users.yml`` . If in doubt, run the cephadm
      deploy playbook to copy the SSH key and install the cephadm binary.

      .. code-block:: console

         kayobe playbook run $KAYOBE_CONFIG_PATH/ansible/cephadm-deploy.yml

   2. Take the host out of maintenance mode:

      .. code-block:: console

         ceph orch host maintenance exit <hostname>

   3. Make sure that everything is back in working condition before moving
      on to the next host:

      .. code-block:: console

         ceph -s
         ceph -w

7. Service deploy:

   .. code:: console

      kayobe overcloud service deploy -kl <hostname>

If any VMs were powered off, they may now be powered back on.

Wait for Prometheus alerts and errors in OpenSearch Dashboard to resolve, or
address them.

Once happy that the system has been restored to full health, move onto the next
host or batch or hosts.

Storage
=======

Potential issues
----------------

-  The procedure for the bootstrap host and the other ceph hosts should
   be identical, now that the "maintenance mode approach" is being used.
   It is still recommended to do the bootstrap host last.

-  Commands starting with ``ceph`` are all run on the cephadm bootstrap
   host in a cephadm shell unless stated otherwise.

Full procedure for any storage host
-----------------------------------

1. Set host in maintenance mode:

   .. code-block:: console

      ceph orch host maintenance enter <hostname>

2. Check there's nothing remaining on the host:

   .. code-block:: console

      ceph orch ps <hostname>

3. Deprovision the storage node:

   .. code:: console

      kayobe overcloud deprovision -l <hostname>

4. Reprovision the storage node:

   .. code:: console

      kayobe overcloud provision -l <hostname>

5. Host configure:

   .. code-block:: console

      kayobe overcloud host configure -l <hostname>

6. Make sure the cephadm public key is in ``authorized_keys`` for stack or
   root user - depends on your setup. For example, your SSH key may
   already be defined in ``users.yml`` . If in doubt, run the cephadm
   deploy playbook to copy the SSH key and install the cephadm binary.

   .. code-block:: console

      kayobe playbook run $KAYOBE_CONFIG_PATH/ansible/cephadm-deploy.yml

7. Take the host out of maintenance mode:

   .. code-block:: console

      ceph orch host maintenance exit <hostname>

8. Make sure that everything is back in working condition before moving
   on to the next host:

   .. code-block:: console

      ceph -s
      ceph -w

Seed
====

Potential issues
----------------

- The process depends a lot on the structure of the seed’s volumes. By
  default two volumes are created (one root volume and one data
  volume), however only the root volume is actually used. Most
  deployments have this behaviour overridden so that both the volumes
  are used and either ``/var/lib/docker`` or
  ``/var/lib/docker/volumes`` is mounted to the data volume. This setup
  makes it considerably easier to migrate the seed, as the root volume
  can be deleted and the seed can be reprovisioned, leaving the data
  volume intact throughout. If the deployment is using the default
  setup, and nothing is stored in the data volume, the first step
  should be to back up either the docker volumes or the entire docker
  directory. This should then be restored to the seed after
  ``seed host configure``
- The mariadb process within the bifrost_deploy container needs to be
  gracefully stopped. mariadb can’t boot a newer version if the
  previous version stopped with an error.

Full procedure
--------------

1.  On the seed, check the LVM configuration:

    .. code:: console

       lsblk

2.  Use `mysqldump
    <https://docs.openstack.org/kayobe/yoga/administration/seed.html#database-backup-restore>`_
    to take a backup of the MariaDB database. Copy the backup file to one of
    the Bifrost container's persistent volumes, such as ``/var/lib/ironic/`` in
    the ``bifrost_deploy`` container.

3.  If the data volume is not mounted at either ``/var/lib/docker`` or
    ``/var/lib/docker/volumes``, make an external copy of the data
    somewhere on the seed hypervisor.

4.  On the seed, stop the MariaDB process within the bifrost_deploy
    container:

    .. code:: console

       sudo docker exec bifrost_deploy systemctl stop mariadb

5.  On the seed, stop docker:

    .. code:: console

       sudo systemctl stop docker

6.  On the seed, shut down the host:

    .. code:: console

       sudo systemctl poweroff

7.  Wait for the VM to shut down:

    .. code:: console

       watch sudo virsh list --all

8.  Back up the VM volumes on the seed hypervisor

    .. code:: console

       sudo mkdir /var/lib/libvirt/images/backup
       sudo cp -r /var/lib/libvirt/images /var/lib/libvirt/images/backup

9.  Delete the seed root volume (check the structure & naming
    conventions first)

    .. code:: console

       sudo virsh vol-delete seed-root --pool default

10.  Reprovision the seed

     .. code:: console

        kayobe seed vm provision

11. Seed host configure

    .. code:: console

       kayobe seed host configure

12. Rebuild seed container images (if using locally-built rather than
    release train images)

    .. code:: console

       kayobe seed container image build --push

13. Service deploy

    .. code:: console

       kayobe seed service deploy

14. Verify that Bifrost/Ironic is healthy.

Seed hypervisor
===============

TODO

Ansible control host
====================

TODO

Wazuh manager
=============

TODO

In-place migrations
===================

TODO
