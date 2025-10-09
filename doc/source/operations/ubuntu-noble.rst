=========================
Upgrading to Ubuntu Noble
=========================

Overview
========

This document describes how to upgrade systems from Ubuntu Jammy 22.04 to
Ubuntu Noble 24.04. This procedure must be performed on Ubuntu Jammy 22.04
OpenStack Caracal systems before it is possible to upgrade to OpenStack Epoxy.
It is possible to perform a rolling upgrade to ensure service is not disrupted.

Upgrades are performed in-place with a script using the ``do-release-upgrade``
tool provided by Canonical, rather than reprovisioning. The scripts are found
at ``tools/ubuntu-upgrade-*.sh``. For overcloud and infrastructure VM upgrades,
the script takes one argument - the host(s) to upgrade. The scripts execute a
playbook to upgrade the host, then run the appropriate ``kayobe * host
configure`` command.

The guide assumes a local pulp instance is deployed and all hosts use it
to pull ``apt`` packages. To upgrade a host using upstream packages, see the
manual upgrade process at the bottom of this page.

While it is technically possible to upgrade hosts in any order, it is
recommended that upgrades for one type of node be completed before moving on
to the next i.e. all compute node upgrades are performed before all storage
node upgrades.

The order of node groups is less important however it is arguably safest to
perform controller node upgrades first, given that they are the most complex
and it is easiest to revert their state in the event of a failure.
This guide covers the following types of hosts:

- Controllers
- Compute hosts
- Storage hosts
- Seed
- Other hosts not managed by Kayobe

The following types of hosts will be covered in the future:

- Ansible control host
- Seed hypervisor (an upgrade script exists but has not been tested)
- Infrastructure VMs (an upgrade script exists but has not been tested)

.. warning::

   Due to `Bug 66389 <https://tracker.ceph.com/issues/66389>`__, do not upgrade
   Ceph hosts to Noble until the Ceph cluster has been upgraded to at least
   Reef v18.2.5. Upgrading a host prematurely will prevent its Ceph daemons
   from starting, and it will not be able to rejoin the cluster.

Prerequisites
=============

Before starting the upgrade, ensure any appropriate prerequisites are
satisfied. These will be specific to each deployment, but here are some
suggestions:

* Merge in the latest ``stackhpc-kayobe-config`` ``stackhpc/2024.1`` branch.
* Ensure that there is sufficient hypervisor capacity to drain
  at least one node.
* If using Ironic for bare metal compute, ensure that at least one node is
  available for testing provisioning.
* Ensure that expected test suites are passing, e.g. Tempest.
* Resolve any Prometheus alerts.
* Check for unexpected ``ERROR`` or ``CRITICAL`` messages in OpenSearch
  Dashboard.
* Check Grafana dashboards.

Sync Release Train artifacts
----------------------------

New `StackHPC Release Train <../configuration/release-train.html>`__ content
should be synced to the local Pulp server. This includes host packages
(Deb/RPM) and container images.

To sync host packages:

.. code-block:: console

   kayobe playbook run $KAYOBE_CONFIG_PATH/ansible/pulp-repo-sync.yml -e stackhpc_pulp_sync_ubuntu_jammy=true -e stackhpc_pulp_sync_ubuntu_noble=true
   kayobe playbook run $KAYOBE_CONFIG_PATH/ansible/pulp-repo-publish.yml -e stackhpc_pulp_sync_ubuntu_jammy=true -e stackhpc_pulp_sync_ubuntu_noble=true

Once the host package content has been tested in a test/staging environment, it
may be promoted to production:

.. code-block:: console

   kayobe playbook run $KAYOBE_CONFIG_PATH/ansible/pulp-repo-promote-production.yml -e stackhpc_pulp_sync_ubuntu_jammy=true -e stackhpc_pulp_sync_ubuntu_noble=true

To sync container images:

.. code-block:: console

   kayobe playbook run $KAYOBE_CONFIG_PATH/ansible/pulp-container-sync.yml
   kayobe playbook run $KAYOBE_CONFIG_PATH/ansible/pulp-container-publish.yml

Build locally customised container images
-----------------------------------------

.. note::

   The container images provided by StackHPC Release Train are suitable for
   most deployments. In this case, this step can be skipped.

In some cases, it is necessary to build some or all images locally to apply
customisations. To do this, set
``stackhpc_pulp_sync_for_local_container_build`` to ``true`` before syncing
container images.

To build the overcloud images locally and push them to the local Pulp server:

.. code-block:: console

   kayobe overcloud container image build --push

It is possible to build a specific set of images by supplying one or more
image name regular expressions:

.. code-block:: console

   kayobe overcloud container image build --push ironic- nova-api

Deploy the latest container images
----------------------------------

Make sure you deploy the latest containers before this upgrade:

.. code-block:: console

   kayobe seed service deploy
   kayobe overcloud service deploy

Common issues for all host types
================================

-  Disk names can change during upgrades. This can be resolved in kayobe-config
   once the new name is known (i.e. after the first upgrade) and applied by
   re-running ``host configure`` for the affected host.
-  Timeouts can become an issue with some hardware. The host will reboot once
   or twice depending on whether it needs to apply package updates. Edit the
   timeouts in the upgrade playbook (``ubuntu-upgrade.yml``) where required.

Controllers
===========

Upgrade controllers *one by one*, ideally upgrading the host with the Kolla
Virtual IP (VIP) last. Before upgrading a host with the VIP, stop the
``keepalived`` container for a few seconds to fail it over to another
controller (restarting the container does not always stop the container for
long enough).

.. code-block:: bash

   sudo systemctl stop kolla-keepalived-container.service
   sudo systemctl start kolla-keepalived-container.service

Always back up the overcloud DB before starting:

.. code-block:: bash

   kayobe overcloud database backup

Potential issues
----------------

-  If the system uses OVS as a network driver, there's a chance that kolla
   services can struggle to find reply queues from RabbitMQ during the upgrade.
   Currently this could be observed when rolling reboot of controllers are done
   or deploying Ubuntu Noble based Kolla containers are deployed after all
   hosts are upgraded to Ubuntu to Noble.
   You can use the ``rabbitmq-reset.yml`` playbook but all messages that are
   in progress will be lost:

   .. code-block:: bash

      kayobe playbook run $KAYOBE_CONFIG_PATH/ansible/rabbitmq-reset.yml

-  If you are using hyper-converged Ceph, please also note the potential issues
   in the Storage section below.
-  After controllers are rebooted, Hashicorp Vault can be sealed. Run the
   ``vault-unseal-overcloud.yml`` playbook to unseal the vaults.

   .. code-block:: bash

      kayobe playbook run $KAYOBE_CONFIG_PATH/ansible/vault-unseal-overcloud.yml

Full procedure for one controller
---------------------------------

1. Export the ``KAYOBE_PATH`` environment variable to be the source of Kayobe
   e.g.

   .. code-block:: console

      export KAYOBE_PATH=~/venvs/kayobe/share/kayobe

      # or if you have a kayobe source locally

      export KAYOBE_PATH=~/src/kayobe

2. If the controller is running Ceph services:

   1. Set host in maintenance mode:

      .. code-block:: console

         kayobe playbook run $KAYOBE_CONFIG_PATH/ansible/ceph-enter-maintenance.yml --limit <host>

   2. Check nothing remains on the host:

      .. code-block:: console

         # From cephadm shell
         ceph orch ps <host>

3. Run the upgrade script:

   .. code-block:: console

      $KAYOBE_CONFIG_PATH/../../tools/ubuntu-upgrade-overcloud.sh <host>

4. If the controller is running Ceph OSD services:

   1. Make sure the cephadm public key is in ``authorized_keys`` for stack or
      root user - depends on your setup. For example, your SSH key may
      already be defined in ``users.yml``. If in doubt, run the cephadm
      deploy playbook to copy the SSH key and install the cephadm binary.

      .. code-block:: console

         kayobe playbook run $KAYOBE_CONFIG_PATH/ansible/cephadm-deploy.yml

   2. Take the host out of maintenance mode:

      .. code-block:: console

         kayobe playbook run $KAYOBE_CONFIG_PATH/ansible/ceph-exit-maintenance.yml --limit <host>

   3. Make sure that everything is back in working condition before moving
      on to the next host:

      .. code-block:: console

         # From cephadm shell
         ceph -s
         ceph -w

After each controller has been upgraded you may wish to perform some smoke
testing, run Tempest, check for alerts and errors etc.

Compute
=======

Compute nodes can be upgraded in batches.
The possible batches depend on:

* willingness for instance reboots and downtime
* available spare hypervisor capacity
* sizes of groups of compatible hypervisors

Potential issues
----------------

None so far!

Full procedure for one batch of hosts
-------------------------------------

1. Export the ``KAYOBE_PATH`` environment variable e.g.

   .. code-block:: console

      export KAYOBE_PATH=~/venvs/kayobe/share/kayobe

      # or if you have a kayobe source locally

      export KAYOBE_PATH=~/src/kayobe

2. Disable the Nova compute service and drain it of VMs using live migration.
   If any VMs fail to migrate, they may be cold migrated or powered off:

   .. code-block:: console

      kayobe playbook run $KAYOBE_CONFIG_PATH/ansible/nova-compute-{disable,drain}.yml --limit <hosts>

3. If the compute node is running Ceph OSD services:

   1. Set host in maintenance mode:

      .. code-block:: console

         kayobe playbook run $KAYOBE_CONFIG_PATH/ansible/ceph-enter-maintenance.yml --limit <hosts>

   2. Check there's nothing remaining on the host:

      .. code-block:: console

         # From cephadm shell
         ceph orch ps <hosts>

4. Run the upgrade script:

   .. code-block:: console

      $KAYOBE_CONFIG_PATH/../../tools/ubuntu-upgrade-overcloud.sh <hosts>

5. If the compute node is running Ceph OSD services:

   1. Make sure the cephadm public key is in ``authorized_keys`` for stack or
      root user - depends on your setup. For example, your SSH key may
      already be defined in ``users.yml`` . If in doubt, run the cephadm
      deploy playbook to copy the SSH key and install the cephadm binary.

      .. code-block:: console

         kayobe playbook run $KAYOBE_CONFIG_PATH/ansible/cephadm-deploy.yml

   2. Take the host out of maintenance mode:

      .. code-block:: console

         kayobe playbook run $KAYOBE_CONFIG_PATH/ansible/ceph-exit-maintenance.yml --limit <hosts>

   3. Make sure that everything is back in working condition before moving
      on to the next host:

      .. code-block:: console

         # From cephadm shell
         ceph -s
         ceph -w

6. Restore the system to full health.

   1. If any VMs were powered off, they may now be powered back on.

   2. Wait for Prometheus alerts and errors in OpenSearch Dashboard to resolve,
      or address them.

   3. Once happy that the system has been restored to full health, enable the
      hypervisor in Nova if it is still disabled and then move onto the next
      host or batch or hosts.

      .. code-block:: console

         kayobe playbook run $KAYOBE_CONFIG_PATH/ansible/nova-compute-enable.yml --limit <hosts>

Storage
=======

Potential issues
----------------

-  Ensure the Ceph cluster is running at least Reef v18.2.5.
   Upgrading hosts with an older Ceph version will cause daemons to fail.
-  It is recommended that you upgrade the bootstrap host last.
-  Before upgrading the bootstrap host, it can be beneficial to backup
   ``/etc/ceph`` and ``/var/lib/ceph``, as sometimes the keys, config, etc.
   stored here will not be moved/recreated correctly.
-  It has been seen that sometimes the Ceph containers do not come up after
   upgrading. This seems to be related to having ``/var/lib/ceph`` persisted
   through the reprovision (e.g. seen at a customer in a volume with software
   RAID). Further investigation is needed for the root cause. When this
   occurs, you will need to redeploy the daemons:

   List the daemons on the host:

   .. code-block:: console

      ceph orch ps <host>

   Redeploy the daemons, one at a time. It is recommended that you start with
   the crash daemon, as this will have the least impact if unexpected issues
   occur.

   .. code-block:: console

      ceph orch daemon redeploy <daemon name> to redeploy a daemon.

-  Commands starting with ``ceph`` are all run on the cephadm bootstrap
   host in a cephadm shell unless stated otherwise.

Full procedure for a storage host
---------------------------------

1. Export the ``KAYOBE_PATH`` environment variable e.g.

   .. code-block:: console

      export KAYOBE_PATH=~/venvs/kayobe/share/kayobe

      # or if you have a kayobe source locally

      export KAYOBE_PATH=~/src/kayobe

2. Set host in maintenance mode:

   .. code-block:: console

      kayobe playbook run $KAYOBE_CONFIG_PATH/ansible/ceph-enter-maintenance.yml --limit <host>

3. Check there's nothing remaining on the host:

   .. code-block:: console

      # From cephadm shell
      ceph orch ps <host>

4. Run the upgrade script:

   .. code-block:: console

      $KAYOBE_CONFIG_PATH/../../tools/ubuntu-upgrade-overcloud.sh <host>

5. Make sure the cephadm public key is in ``authorized_keys`` for stack or
   root user - depends on your setup. For example, your SSH key may
   already be defined in ``users.yml``. If in doubt, run the cephadm
   deploy playbook to copy the SSH key and install the cephadm binary.

   .. code-block:: console

      kayobe playbook run $KAYOBE_CONFIG_PATH/ansible/cephadm-deploy.yml

6. Take the host out of maintenance mode:

   .. code-block:: console

      kayobe playbook run $KAYOBE_CONFIG_PATH/ansible/ceph-exit-maintenance.yml --limit <host>

7. Make sure that everything is back in working condition before moving
   on to the next host:

   .. code-block:: console

      # From cephadm shell
      ceph -s
      ceph -w

Seed
====

Potential issues
----------------

-  The process has not been tested as well as for other hosts. Proceed with
   caution.
-  The Seed can take significantly longer to upgrade than other hosts.
   ``do-release-upgrade`` has been observed taking more than 45 minutes to
   complete.

Full procedure
--------------

1. Export the ``KAYOBE_PATH`` environment variable e.g.

   .. code-block:: console

      export KAYOBE_PATH=~/venvs/kayobe/share/kayobe

      # or if you have a kayobe source locally

      export KAYOBE_PATH=~/src/kayobe

2. Run the upgrade script:

   .. code-block:: console

      $KAYOBE_CONFIG_PATH/../../tools/ubuntu-upgrade-seed.sh

Wazuh manager
=============

TODO

Seed hypervisor
===============

TODO

Ansible control host
====================

TODO

Manual Process
==============

Sometimes it is necessary to upgrade a system that is not managed by Kayobe
(and therefore does not use packages from pulp). Below is a set of instructions
to manually execute the upgrade process.

Full procedure
--------------

1. Update all packages to the latest available versions

   .. code-block:: console

      sudo apt update -y && sudo apt upgrade -y

2. Install the upgrade tool

   .. code-block:: console

      sudo apt install ubuntu-release-upgrader-core

3. Check whether a reboot is required

   .. code-block:: console

      cat /var/run/reboot-required

4. Where required, reboot to apply updates

   .. code-block:: console

      sudo reboot

5. Run ``do-release-upgrade``

   .. code-block:: console

      do-release-upgrade -f DistUpgradeViewNonInteractive

6. Reboot to apply the upgrade

   .. code-block:: console

      sudo reboot


Post Upgrade works
==================

Deploy Ubuntu Noble Kolla containers
------------------------------------

Once all hosts are upgraded to Ubuntu Noble and stable, Kolla containers built
with Ubuntu Noble base image need to be deployed.

.. code-block:: console

   kayobe overcloud service upgrade

System verification
-------------------

After new Kolla containers are deployed, check the system status with

- Opensearch Dashboards
- Grafana
- Prometheus

and run appropriate test suites. e.g. Tempest.
