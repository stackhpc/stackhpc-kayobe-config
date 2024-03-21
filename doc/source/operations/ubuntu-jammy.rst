=========================
Upgrading to Ubuntu Jammy
=========================

Overview
========

This document describes how to upgrade systems from Ubuntu Focal 20.04 to
Ubuntu Jammy 22.04. This procedure must be performed on Ubuntu Focal 20.04
OpenStack Yoga systems before it is possible to upgrade to OpenStack Zed. It is
possible to perform a rolling upgrade to ensure service is not disrupted.

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

   Ceph node upgrades have not yet been performed outside of a virtualised test
   environment. Proceed with caution.

Prerequisites
=============

Before starting the upgrade, ensure any appropriate prerequisites are
satisfied. These will be specific to each deployment, but here are some
suggestions:

* Merge in the latest ``stackhpc-kayobe-config`` ``stackhpc/yoga`` branch.
* Ensure that there is sufficient hypervisor capacity to drain
  at least one node.
* If using Ironic for bare metal compute, ensure that at least one node is
  available for testing provisioning.
* Ensure that expected test suites are passing, e.g. Tempest.
* Resolve any Prometheus alerts.
* Check for unexpected ``ERROR`` or ``CRITICAL`` messages in Kibana/OpenSearch
  Dashboard.
* Check Grafana dashboards.

Sync Release Train artifacts
----------------------------

New `StackHPC Release Train <../configuration/release-train.html>`__ content
should be synced to the local Pulp server. This includes host packages
(Deb/RPM) and container images.

To sync host packages:

.. code-block:: console

   kayobe playbook run $KAYOBE_CONFIG_PATH/ansible/pulp-repo-sync.yml -e stackhpc_pulp_sync_ubuntu_focal=true -e stackhpc_pulp_sync_ubuntu_jammy=true
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

-  Interface names regularly change during upgrades, usually gaining the
   ``np0`` suffix. This cannot easily be resolved. The upgrade script
   configures networking both before and after rebooting to apply the upgrade.
   Setting the interface statically in a kayobe-config fails during one of
   these. This can be worked around by adding a ``sed`` command to the upgrade
   script between the upgrade playbook step and the host configure step e.g.

   .. code-block:: bash

      kayobe playbook run $KAYOBE_CONFIG_PATH/ansible/ubuntu-upgrade.yml -e os_release=jammy --limit $1
      sed -i -e 's/"ens1"/"ens1np0"/g' -e 's/"ens2"/"ens2np0"/g' $KAYOBE_CONFIG_PATH/environments/production/inventory/group_vars/compute/network-interfaces
      kayobe overcloud host configure --limit $1 --kolla-limit $1 -e os_release=jammy

   Remember to reset the change before upgrading another host (or add a
   second ``sed`` command to automate the process)
-  Disk names can change during upgrades. This can be resolved in kayobe-config
   once the new name is known (i.e. after the first upgrade) and applied by
   re-running ``host configure`` for the affected host.
-  Timeouts can become an issue with some hardware. The host will reboot once
   or twice depending on whether it needs to apply package updates. Edit the
   timeouts in the upgrade playbook (``ubuntu-upgrade.yml``) where required.
-  On systems using OVN networking, the Yoga Kolla Neutron container images
   include ``pyroute2`` 0.6.6. On Ubuntu Jammy systems this results in the
   Neutron OVN metadata agent failing to provision the datapath correctly. See
   `LP#1995735
   <https://bugs.launchpad.net/ubuntu/+source/neutron/+bug/1995735>`__ and
   `LP#2042954 <https://bugs.launchpad.net/kolla/+bug/2042954>`__ for
   details.  A `fix <https://review.opendev.org/c/openstack/kolla/+/913584>`__
   is in progress.

Controllers
===========

Upgrade controllers *one by one*, ideally upgrading the host with the Kolla
Virtual IP (VIP) last. Before upgrading a host with the VIP, stop the
``keepalived`` container for a few seconds to fail it over to another
controller (restarting the container does not always stop the container for
long enough).

.. code-block:: bash

   sudo docker stop keepalived
   sudo docker start keepalived

Always back up the overcloud DB before starting:

.. code-block:: bash

   kayobe overcloud database backup

Potential issues
----------------

-  In both testing and production, RabbitMQ has fallen into an error state
   during controller upgrades. Keep an eye on the RabbitMQ Grafana dashboard and
   if errors begin to increase, use the ``rabbitmq-reset`` playbook:

   .. code-block:: bash

      kayobe playbook run $KAYOBE_CONFIG_PATH/ansible/rabbitmq-reset.yml

-  If you are using hyper-converged Ceph, please also note the potential issues
   in the Storage section below.

Full procedure for one controller
---------------------------------

1. Export the ``KAYOBE_PATH`` environment variable e.g.

   .. code-block:: console

      export KAYOBE_PATH=~/src/kayobe

2. If the controller is running Ceph services:

   1. Set host in maintenance mode:

      .. code-block:: console

         ceph orch host maintenance enter <host>

   2. Check nothing remains on the host:

      .. code-block:: console

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

         ceph orch host maintenance exit <host>

   3. Make sure that everything is back in working condition before moving
      on to the next host:

      .. code-block:: console

         ceph -s
         ceph -w

5.  Some RabbitMQ instability has been observed. Check the RabbitMQ dashboard
    in Grafana if the cluster is unhealthy run the ``rabbitmq-reset`` playbook.

    .. code:: console

       kayobe playbook run $KAYOBE_CONFIG_PATH/ansible/rabbitmq-reset.yml

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

-  VMs cannot be live migrated between Focal and Jammy hypervisors using AMD
   CPUs. Any affected VMs must be cold-migrated. It may be possible to disable
   ``xsave``, reboot the VM, then live-migrate, however this process has not
   been tested.

Full procedure for one batch of hosts
-------------------------------------

1. Export the ``KAYOBE_PATH`` environment variable e.g.

   .. code-block:: console

      export KAYOBE_PATH=~/src/kayobe

2. Disable the Nova compute service and drain it of VMs using live migration.
   If any VMs fail to migrate, they may be cold migrated or powered off:

   .. code-block:: console

      kayobe playbook run $KAYOBE_CONFIG_PATH/ansible/nova-compute-{disable,drain}.yml --limit <hosts>

3. If the compute node is running Ceph OSD services:

   1. Set host in maintenance mode:

      .. code-block:: console

         ceph orch host maintenance enter <hosts>

   2. Check there's nothing remaining on the host:

      .. code-block:: console

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

         ceph orch host maintenance exit <hosts>

   3. Make sure that everything is back in working condition before moving
      on to the next host:

      .. code-block:: console

         ceph -s
         ceph -w

6. Restore the system to full health.

   1. If any VMs were powered off, they may now be powered back on.

   2. Wait for Prometheus alerts and errors in Kibana/OpenSearch Dashboard to
      resolve, or address them.

   3. Once happy that the system has been restored to full health, enable the
      hypervisor in Nova if it is still disabled and then move onto the next
      host or batch or hosts.

      .. code-block:: console

         kayobe playbook run $KAYOBE_CONFIG_PATH/ansible/nova-compute-enable.yml --limit <hosts>

Storage
=======

Potential issues
----------------

-  It is recommended that you upgrade the bootstrap host last.
-  Before upgrading the bootstrap host, it can be beneficial to backup
   ``/etc/ceph`` and ``/var/lib/ceph``, as sometimes the keys, config, etc.
   stored here will not be moved/recreated correctly.
-  When a host is taken out of maintenance, you may see errors relating to
   permissions of /tmp/etc and /tmp/var. These issues should be resolved in
   Ceph version 17.2.7. See issue: https://github.com/ceph/ceph/pull/50736. In
   the meantime, you can work around this by running the command below. You may
   need to omit one or the other of ``/tmp/etc`` and ``/tmp/var``. You will
   likely need to run this multiple times. Run ``ceph -W cephadm`` to monitor
   the logs and see when permissions issues are hit.

   .. code-block:: console

      kayobe overcloud host command run --command "chown -R stack:stack /tmp/etc /tmp/var" -b -l storage

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

      export KAYOBE_PATH=~/src/kayobe

2. Set host in maintenance mode:

   .. code-block:: console

      ceph orch host maintenance enter <host>

3. Check there's nothing remaining on the host:

   .. code-block:: console

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

      ceph orch host maintenance exit <host>

7. Make sure that everything is back in working condition before moving
   on to the next host:

   .. code-block:: console

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
