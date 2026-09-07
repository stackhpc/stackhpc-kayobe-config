.. _upgrading-to-rocky-10:

=====================
Upgrading to Rocky 10
=====================

Overview
========
This document describes how to migrate systems to Rocky Linux 10, which is a prerequisite
for upgrading to OpenStack release 2026.1 (Gazpacho).

Pre-migration testing
=====================
It is recommended to run a baseline set of tests to check the cloud is in a good state before
beginning migrations:

#. :doc:`tempest`.
#. Check OpenSearch logs
#. Check Prometheus alerts
#. Check Azimuth operation status

Update Configuration
====================

Merge in the latest ``stackhpc-kayobe-config`` - ``stackhpc/2025.1`` branch by
:ref:`updating your base configuration <updating-configuration>`.

Then upgrade the control environment:

.. code-block:: console

   kayobe control host upgrade

Update your environment's ``globals.yml``:

.. code-block:: yaml

    os_distribution: "rocky"
    os_release: "10"

To enable syncing of valkey container images for the required redis to valkey migration,
update your environment's ``kolla.yml``:

.. code-block:: diff

    -kolla_enable_redis: true
    +kolla_enable_valkey: true

Update Kayobe
=============
Ensure you have the latest version of Kayobe installed, from your kayobe environment:

.. code-block:: console

   pip install -U kayobe

Sync Release Train artifacts
============================
New StackHPC Release Train content should be synced to the local Pulp server. This includes host
packages and container images.

To sync host packages:

.. code-block:: console

    kayobe playbook run $KAYOBE_CONFIG_PATH/ansible/pulp/pulp-repo-sync.yml

.. code-block:: console

    kayobe playbook run $KAYOBE_CONFIG_PATH/ansible/pulp/pulp-repo-publish.yml

Once the host package content has been tested in a staging environment, it can be promoted to production:

.. code-block:: console

    kayobe playbook run $KAYOBE_CONFIG_PATH/ansible/pulp/pulp-repo-promote-production.yml

To sync container images:

.. code-block:: console

    kayobe playbook run $KAYOBE_CONFIG_PATH/ansible/pulp/pulp-container-sync.yml

.. code-block:: console

    kayobe playbook run $KAYOBE_CONFIG_PATH/ansible/pulp/pulp-container-publish.yml

Valkey migration
================
Before beginning upgrades the redis service must be migrated to valkey.

Update your ``kolla/passwords.yml`` file to contain an entry for ``valkey_master_password``. For the
migration this must match your existing ``redis_master_password``.

Pull in the new valkey containers:

.. code-block:: console

    kayobe overcloud container image pull --kolla-tag valkey

Perform the migration:

.. code-block:: console

    kayobe kolla ansible run migrate-valkey

Check Opensearch logs and prometheus alerts for any ongoing warnings/alerts.

Build locally customised container images
=========================================
.. note::

    The container images provided by StackHPC's *Release Train* are suitable for most deployments, in
    which case this step can be skipped.

In some cases it may be necessary to build some or all images locally to apply customisations. In order
to do this it is necessary to set ``stackhpc_pulp_sync_for_local_container_build`` to ``true`` before
syncing container images.

To build the overcloud images locally and push them to the local Pulp server:

.. code-block:: console

    kayobe overcloud container image build --push

It is possible to build a specific set of images by supplying one or more image name regular expressions:

.. code-block:: console

    kayobe overcloud container image build --push ironic- nova-api

Deploy latest Rocky 9 images
============================
Before beginning the migration make sure you deploy the latest Rocky 9 container images.

.. code-block:: console

   kayobe overcloud container image pull

.. code-block:: console

    kayobe overcloud service deploy

Prepare host images
=========================================

Pull latest images from Release Train
-------------------------------------
If hosts are provsioned using Bifrost, Rocky 10 host images will need to be downloaded to the seed before hosts
can be provisioned:

.. code-block:: console

   kayobe seed service deploy --tags kolla-bifrost --kolla-tags bifrost

Build locally customised host images
------------------------------------
.. note::

    The host images provided by StackHPC's *Release Train* are suitable for most deployments, in
    which case this step can be skipped.

For some deployments it may be necessary to build custom host images. To enable this ensure
``overcloud_dib_build_host_images`` is set to ``true``.

To build the host images locally:

.. code-block:: console

   kayobe overcloud host image build

Potential Issues
================
* Rocky 10 has a maximum interface name length of 15 characters; depending on device names and the VLAN ID it
  is possible for this to be exceeded. Work is in progress to add a pre-check to stop deployment if interface
  names exceed this limit. Systemd link files are a potential option for implementing custom interface naming.
* A bug within QEMU image causes failure during the mounting of devices using 4k block sizes
  (`qemu-img: /dev/loop0: Failed to clear the new image's first sector: Invalid argument`). Currently the only
  workaround for deploying on Rocky 10 with these devices is to build nova, cinder, ironic, and glance container
  images using CentOS Stream 10 packages.
* Once a controller starts migration, RabbitMQ on other nodes can start raising errors about
  missing cluster fanouts which doesn't resolve once the migration is complete, this can be fixed
  post-migration by resetting RabbitMQ:

  .. code-block:: console

    kayobe playbook run $KAYOBE_CONFIG_PATH/ansible/fixes/rabbitmq-reset.yml --skip-tags restart-openstack

* *Possibly need to update interface names*

Controllers
===========
Controllers should be migrated one-by-one, ideally migrating the controller with the Virtual IP (VIP) last.

Full procedure for one host
---------------------------
#. `Back up your database <https://docs.openstack.org/kayobe/2025.1/administration/overcloud.html#performing-database-backups>`__

   #. Ensure the backup is moved off the controller that is to be migrated, before it is deprovisioned.

#. If the controller is running Ceph services:

   #. Place host in maintenance mode:

      .. code-block:: console

        kayobe playbook run $KAYOBE_CONFIG_PATH/ansible/ceph/ceph-enter-maintenance.yml --limit <host>

   #. Check nothing is running on the host, from any cephadm shell:

      .. code-block:: console

        ceph orch ps <host>

#. If using OVN, you should follow the *OVN Graceful Shutdown Procedure* on each controller
   before beginning to migrate it:

   #. Exec into the OVN Northbound container, ``ovn_nb_db`` on at least the controller to
      be removed and one other:

      .. code-block:: console

        sudo docker exec -it ovn_nb_db bash

   #. Check the status of the cluster on these controllers:

      .. code-block:: console

        ovs-appctl -t /var/run/ovn/ovnnb_db.ctl cluster/status OVN_Northbound

      At this point all controllers should be present in the cluster.

   #. On the controller to be removed, leave the cluster:

      .. code-block:: console

        ovs-appctl -t /var/run/ovn/ovnnb_db.ctl cluster/leave OVN_Northbound

   #. Check the cluster state again from another controller:

      .. code-block:: console

        ovs-appctl -t /var/run/ovn/ovnnb_db.ctl cluster/status OVN_Northbound

      All controllers except the one being removed should still be in the cluster.

   #. Repeat the same process for the OVN Southbound container, ``ovn_sb_db``:

      .. code-block:: console

        sudo docker exec -it ovn_sb_db bash

      .. code-block:: console

        ovs-appctl -t /var/run/ovn/ovnsb_db.ctl cluster/status OVN_Southbound

      .. code-block:: console

        ovs-appctl -t /var/run/ovn/ovnsb_db.ctl cluster/leave OVN_Southbound

#. Stop OpenStack services on the controller:

   .. code-block:: console

        kayobe overcloud service stop --yes-i-really-really-mean-it --kolla-limit <host>

#. Deprovision the controller, and reprovision it with Rocky Linux 10:

   .. code-block:: console

        kayobe overcloud deprovision --limit <host>

   .. code-block:: console

        kayobe overcloud provision --limit <host>

#. Configure the host:

   .. code-block:: console

        kayobe overcloud host configure --limit <host>

#. If the controller is running Ceph OSD services:

   #. **Deploy public key/install cephadm - this step needs checking**

   #. Take the host out of maintenance mode:

      .. code-block:: console

        kayobe playbook run $KAYOBE_CONFIG_PATH/ansible/ceph/ceph-exit-maintenance.yml --limit <host>

   #. Make sure Ceph services are back in a working condition before moving on to
      the next host, from any cephadm shell:

      .. code-block:: console

        ceph -s

#. Deploy overcloud services, this should be run against all controllers:

   .. code-block:: console

        kayobe overcloud service deploy --kolla-limit controllers

#. If using OpenBao, reset the cluster:

   .. code-block:: console

         kayobe playbook run $KAYOBE_CONFIG_PATH/ansible/secret-store/fix-openbao-overcloud.yml

Compute
=======
Compute nodes can be migrated to Rocky Linux 10 in batches, dependent on:

* Available spare cluster capacity
* Willingness for instance reboots and downtime
* Sizes of groups of compatible hypervisors

Full procedure for a batch of hosts
-----------------------------------
#. Disable the Nova Compute service:

   .. code-block:: console

        kayobe playbook run $KAYOBE_CONFIG_PATH/ansible/maintenance/nova-compute-disable.yml --limit <hosts>

#. Drain the hosts of VMs using live migration:

   .. code-block:: console

        kayobe playbook run $KAYOBE_CONFIG_PATH/ansible/maintenance/nova-compute-drain.yml --limit <hosts>

#. If the hosts are running Ceph services:

   #. Place host in maintenance mode:

      .. code-block:: console

        kayobe playbook run $KAYOBE_CONFIG_PATH/ansible/ceph/ceph-enter-maintenance.yml --limit <hosts>

   #. Check nothing is running on the host, from any cephadm shell:

      .. code-block:: console

        ceph orch ps

#. Stop OpenStack services on the hosts:

   .. code-block:: console

        kayobe overcloud service stop --yes-i-really-really-mean-it --kolla-limit <hosts>

#. Deprovision the nodes, and reprovision them with Rocky Linux 10:

   .. code-block:: console

        kayobe overcloud deprovision --limit <hosts>

   .. code-block:: console

        kayobe overcloud provision --limit <hosts>

#. Configure the hosts:

   .. code-block:: console

        kayobe overcloud host configure --limit <hosts>

#. If the hosts are running Ceph services:

   #. **Deploy public key/install cephadm - this step needs checking**

   #. Take the hosts out of maintenance mode:

      .. code-block:: console

        kayobe playbook run $KAYOBE_CONFIG_PATH/ansible/ceph/ceph-exit-maintenance.yml --limit <hosts>

   #. Make sure Ceph services are back in a working condition before moving on to
      the next host, from any cephadm shell:

      .. code-block:: console

        ceph -s

#. Deploy overcloud services on the hosts:

   .. code-block:: console

        kayobe overcloud service deploy --kolla-limit <hosts>

#. Restore the system to full health:

   #. Wait for any alerts to resolve, or address them
   #. If any VMs were powered off, they can now be powered back on
   #. Once you're happy the hosts are operating correctly, reenable the
      compute service and move onto the next set of hosts:

      .. code-block:: console

        kayobe playbook run $KAYOBE_CONFIG_PATH/ansible/maintenance/nova-compute-enable.yml --limit <hosts>

Storage
=======

Full procedure for one host
---------------------------
#. Place host in maintenance mode:

   .. code-block:: console

      kayobe playbook run $KAYOBE_CONFIG_PATH/ansible/ceph/ceph-enter-maintenance.yml --limit <host>

#. Check nothing is running on the host, from any cephadm shell:

   .. code-block:: console

      ceph orch ps <host>

#. Stop OpenStack services on the host:

   .. code-block:: console

      kayobe overcloud service stop --yes-i-really-really-mean-it --kolla-limit <host>

#. Deprovision the node, and reprovision it with Rocky Linux 10:

   .. code-block:: console

      kayobe overcloud deprovision --limit <host>

   .. code-block:: console

      kayobe overcloud provision --limit <host>

#. Configure the host:

   .. code-block:: console

      kayobe overcloud host configure --limit <host>

#. **Deploy public key/install cephadm - this step needs checking**

#. Take the host out of maintenance mode:

   .. code-block:: console

    kayobe playbook run $KAYOBE_CONFIG_PATH/ansible/ceph/ceph-exit-maintenance.yml --limit <host>

#. Make sure Ceph services are back in a working condition before moving on to
   the next host, from any cephadm shell:

   .. code-block:: console

    ceph -s

#. Deploy overcloud services on the host:

   .. code-block:: console

        kayobe overcloud service deploy --kolla-limit <host>

Seed
====
TODO

* Bifrost docker volume

Ansible Control Host
====================
Due to the variety of approaches taken to setup control hosts, this section is left as an exercise
for the cloud operator.

*But we could maybe give some pointers about things to watch out for?*
