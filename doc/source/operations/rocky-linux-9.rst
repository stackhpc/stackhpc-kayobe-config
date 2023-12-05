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
- Consider using a `prebuilt overcloud host image
  <../configuration/host-images.html#pulling-host-images>`_ or building an
  overcloud host image using the `standard configuration
  <../configuration/host-images.html#building-host-images>`_.
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

Routing rules
-------------

Routing rules referencing tables by name may need adapting to be compatible with NetworkManager
e.g:

  .. code-block:: yaml

      undercloud_prov_rules:
        - from {{ internal_net_name | net_cidr }} table ironic-api

will need to be updated to use numeric IDs:

  .. code-block:: yaml

      undercloud_prov_rules:
        - from {{ internal_net_name | net_cidr }} table 1

The error from NetworkManager was:

  .. code-block:: shell

      [1697192659.9611] keyfile: ipv4.routing-rules: invalid value for "routing-rule1": invalid value for "table"

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
* Disable Ansible fact caching for the duration of the migration, or remember
  to clear hosts from the fact cache after they have been reprovisioned.

Migrate to OpenSearch
---------------------

Elasticsearch/Kibana should be migrated to OpenSearch.

- Read the `Kolla Ansible OpenSearch migration
  docs <https://docs.openstack.org/kolla-ansible/yoga/reference/logging-and-monitoring/central-logging-guide-opensearch.html#migration>`__
- If necessary, take a backup of the Elasticsearch data.
- Ensure ``kolla_enable_elasticsearch`` is unset in ``etc/kayobe/kolla.yml``
- If you have a custom Kolla Ansible inventory, ensure that it contains the ``opensearch`` and ``opensearch-dashboards`` groups. Otherwise, sync with the inventory in Kayobe.
- Set ``kolla_enable_opensearch: true`` in ``etc/kayobe/kolla.yml``
- ``kayobe overcloud service configuration generate --node-config-dir '/tmp/ignore' --kolla-tags none``
- ``kayobe overcloud container image pull -kt opensearch``
- ``kayobe kolla ansible run opensearch-migration``
- If old indices are detected, they may be removed by running ``kayobe kolla ansible run opensearch-migration -ke prune_kibana_indices=true``

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
-  When using Octavia load balancers, restarting Neutron causes load balancers
   with floating IPs to stop processing traffic. See `LP#2042938
   <https://bugs.launchpad.net/neutron/+bug/2042938>`__ for details. The issue
   may be worked around after Neutron has been restarted by detaching then
   reattaching the floating IP to the load balancer's virtual IP.

-  If you are using hyper-converged Ceph, please also note the potential issues
   in the Storage section below.

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

13. If you are using Wazuh, you will need to deploy the agent again.
    Note that CIS benchmarks do not run on RL9 out-the-box. See
    `our Wazuh docs <https://stackhpc-kayobe-config.readthedocs.io/en/stackhpc-yoga/configuration/wazuh.html#custom-sca-policies-optional>`__
    for details.

    .. code-block:: console

       kayobe playbook run $KAYOBE_CONFIG_PATH/ansible/wazuh-agent.yml -l <hostname>

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

8. If you are using Wazuh, you will need to deploy the agent again.
    Note that CIS benchmarks do not run on RL9 out-the-box. See
    `our Wazuh docs <https://stackhpc-kayobe-config.readthedocs.io/en/stackhpc-yoga/configuration/wazuh.html#custom-sca-policies-optional>`__
    for details.

    .. code-block:: console

       kayobe playbook run $KAYOBE_CONFIG_PATH/ansible/wazuh-agent.yml -l <hostname>

9. Restore the system to full health.

   1. If any VMs were powered off, they may now be powered back on.

   2. Wait for Prometheus alerts and errors in OpenSearch Dashboard to resolve,
      or address them.

   3. Once happy that the system has been restored to full health, enable the
      hypervisor in Nova if it is still disabled and then move onto the next
      host or batch or hosts.

      .. code-block:: console

         kayobe playbook run $KAYOBE_CONFIG_PATH/ansible/nova-compute-enable.yml --limit <hostname>


Storage
=======

Potential issues
----------------

-  The procedure for the bootstrap host and the other ceph hosts should
   be identical, now that the "maintenance mode approach" is being used.
   It is still recommended to do the bootstrap host last.

-  Prior to reprovisioning the bootstrap host, it can be beneficial to backup
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
   reprovisioning. This seems to be related to having ``/var/lib/ceph``
   persisted through the reprovision (e.g. seen at a customer in a volume
   with software RAID). (Note: further investigation is needed for the root
   cause). When this occurs, you will need to redeploy the daemons:

   List the daemons on the host:

   .. code-block:: console

      ceph orch ps <hostname>


   Redeploy the daemons, one at a time. It is recommended that you start with
   the crash daemon, as this will have the least impact if unexpected issues
   occur.

   .. code-block:: console

      ceph orch daemon redeploy <daemon name> to redeploy a daemon.


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

      kayobe overcloud host configure -l <hostname> -kl <hostname>

6. Make sure the cephadm public key is in ``authorized_keys`` for stack or
   root user - depends on your setup. For example, your SSH key may
   already be defined in ``users.yml``. If in doubt, run the cephadm
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

9. Deploy any services that are required, such as Prometheus exporters.

   .. code-block:: console

      kayobe overcloud service deploy -kl <hostname>

10. If you are using Wazuh, you will need to deploy the agent again.
    Note that CIS benchmarks do not run on RL9 out-the-box. See
    `our Wazuh docs <https://stackhpc-kayobe-config.readthedocs.io/en/stackhpc-yoga/configuration/wazuh.html#custom-sca-policies-optional>`__
    for details.

    .. code-block:: console

       kayobe playbook run $KAYOBE_CONFIG_PATH/ansible/wazuh-agent.yml -l <hostname>

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

15. If you are using Wazuh, you will need to deploy the agent again.
    Note that CIS benchmarks do not run on RL9 out-the-box. See
    `our Wazuh docs <https://stackhpc-kayobe-config.readthedocs.io/en/stackhpc-yoga/configuration/wazuh.html#custom-sca-policies-optional>`__
    for details.

    .. code-block:: console

       kayobe playbook run $KAYOBE_CONFIG_PATH/ansible/wazuh-agent.yml -l <hostname>

Seed hypervisor
===============

TODO

Ansible control host
====================

TODO

Wazuh manager
=============

TODO

In-place upgrades
=================

Sometimes it is necessary to upgrade a system in-place.
This may be the case for the seed hypervisor or Ansible control host which are often installed manually onto bare metal.
This procedure is not officially recommended, and can be risky, so be sure to back up all critical data and ensure serial console access is available (including password login) in case of getting locked out.

The procedure is performed in two stages:

1. Migrate from CentOS Stream 8 to Rocky Linux 8
2. Upgrade from Rocky Linux 8 to Rocky Linux 9

Potential issues
----------------

Full procedure
--------------

- Inspect existing DNF packages and determine whether they are really required.

- Use the `migrate2rocky.sh
  <https://raw.githubusercontent.com/rocky-linux/rocky-tools/main/migrate2rocky/migrate2rocky.sh>`__
  script to migrate to Rocky Linux 8.

- Disable all DNF modules - they're no longer used.

  .. code-block:: console

     sudo dnf module disable "*"

- Migrate to NetworkManager. This can be done using a manual process or with Kayobe.

  The manual process is as follows:

  - Ensure that all network interfaces are managed by Network Manager:

    .. code:: console

       sudo sed -i -e 's/NM_CONTROLLED=no/NM_CONTROLLED=yes/g' /etc/sysconfig/network-scripts/*

  - Enable and start NetworkManager:

    .. code:: console

       sudo systemctl enable NetworkManager
       sudo systemctl start NetworkManager

  - Migrate Ethernet connections to native NetworkManager configuration:

    .. code:: console

       sudo nmcli connection migrate

  - Manually migrate non-Ethernet (bonds, bridges & VLAN subinterfaces) network interfaces to native NetworkManager.

  - Look out for lost DNS configuration after migration to NetworkManager. This may be manually restored using something like this:

    .. code:: console

       nmcli con mod System\ brextmgmt.3003 ipv4.dns "10.41.4.4 10.41.4.5 10.41.4.6"

  The following Kayobe process for migrating to NetworkManager has not yet been tested.

  - Set ``interfaces_use_nmconnection: true`` as a host/group variable for the relevant hosts

  - Run the appropriate host configure command. For example, for the seed hypervisor:

    .. code:: console

       kayobe seed hypervisor host configure -t network -kt none

 - Make sure there are no funky udev rules left in
   ``/etc/udev/rules.d/70-persistent-net.rules`` (e.g. from cloud-init run on
   Rocky 9.1).

  - Inspect networking configuration at this point, ideally reboot to validate correctness.

- Upgrade to Rocky Linux 9

  .. https://forums.rockylinux.org/t/dnf-warning-message-after-upgrade-from-rocky-8-to-rocky-9/8319/2

  - Install Rocky Linux 9 repositories and GPG keys:

    .. code:: console

       sudo dnf install -y https://download.rockylinux.org/pub/rocky/9/BaseOS/x86_64/os/Packages/r/rocky-gpg-keys-9.2-1.6.el9.noarch.rpm \
                           https://download.rockylinux.org/pub/rocky/9/BaseOS/x86_64/os/Packages/r/rocky-release-9.2-1.6.el9.noarch.rpm \
                           https://download.rockylinux.org/pub/rocky/9/BaseOS/x86_64/os/Packages/r/rocky-repos-9.2-1.6.el9.noarch.rpm

  - Remove the RedHat logos package:

    .. code:: console

       sudo rm -rf /usr/share/redhat-logos

  - Synchronise all packages with current versions

    .. code:: console

       sudo dnf --releasever=9 --allowerasing --setopt=deltarpm=false distro-sync -y

  - Rebuild RPB database:

    .. code:: console

       sudo rpm --rebuilddb

  - Make a list of EL8 packages to remove:

    .. code:: console

       sudo rpm -qa | grep el8 > el8-packages

  - Inspect the ``el8-packages`` list and ensure only expected packages are included.

  - Remove the EL8 packages:

    .. code:: console

       cat el8-packages | xargs sudo dnf remove -y

- You will need to re-create *all* virtualenvs afterwards due to system Python version upgrade.
