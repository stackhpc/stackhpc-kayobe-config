===================
Upgrading OpenStack
===================

This section describes how to upgrade from the |previous_release| OpenStack
release series to |current_release|. It is based on the :kayobe-doc:`upstream
Kayobe documentation <upgrading>` with additional considerations for using
StackHPC Kayobe Configuration.

Overview
========

A StackHPC OpenStack upgrade is broken down into several phases.

* Prerequisites
* Preparation
* Upgrading the Seed Hypervisor
* Upgrading the Seed
* Upgrading Wazuh Manager
* Upgrading Wazuh Agents
* Upgrading the Overcloud
* Cleaning up

After preparation is complete, the remaining phases may be completed in any
order, however the order specified above allows for completing as much as
possible before the user-facing overcloud upgrade. It is not recommended to
keep different parts of the system on different releases for extended periods
due to the need to maintain and use separate local Kayobe environments.

.. NOTE(upgrade): Update these notable changes for the current release.

Notable changes in the |current_release| Release
================================================

There are many changes in the OpenStack |current_release| release described in
the release notes for each project. Here are some notable ones.

stackhpc.linux collection
-------------------------

The ``stackhpc.linux`` collection version has been bumped to 1.3.0. Note this
version uses systemd to activate virtual functions. This change is restricted
to the ``stackhpc.linux.sriov`` role, which is not used by Kayobe. If a custom
playbook uses this role, you can retain existing behaviour by setting
``sriov_numvfs_driver`` to ``udev``.

Neutron driver defaults
-----------------------

The default Neutron ML2 type drivers and tenant network types now use
``geneve`` instead of ``vxlan`` when OVN is enabled. This affects the
``kolla_neutron_ml2_type_drivers`` and
``kolla_neutron_ml2_tenant_network_types`` variables.

Custom inspector_keep_ports
---------------------------

If you have customized ``inspector_keep_ports``, ensure it is set to one of:
``all``, ``present``, or ``added``. If you are relying on the previous
behaviour you should set ironic_keep_ports to present.

Seed/Infra VM boot firmware
---------------------------

The default boot firmware for Seed and Infra VMs has changed from ``bios`` to
``efi``. Set ``infra_vm_boot_firmware`` and ``seed_vm_boot_firmware`` to bios
to retain existing behaviour.

Prometheus MSteams
------------------

The ``prometheus-msteams`` integration in Kolla Ansible has been removed, users
should switch to the `native
<https://prometheus.io/docs/alerting/latest/configuration/#msteams_config>`__
Prometheus Teams integration.

Prometheus blackbox exporter endpoints
--------------------------------------

Many endpoints for the Blackbox exporter are now templated in the Kolla-Ansible
group vars for the cloud. This means that the
``prometheus_blackbox_exporter_endpoints`` variable can be removed from the
environment's ``kolla/globals.yml`` file (if applicable) and the endpoints will
fallback to the ones templated in the group vars. Backend endpoints such as
`these <https://github.com/stackhpc/stackhpc-kayobe-config/blob/094c2e012a037309d103c08a71eb633fdeb214e7/etc/kayobe/kolla/inventory/group_vars/prometheus-blackbox-exporter#L27-L64>`__
are not yet templated by Kolla-Ansible.

Additional endpoints may still be added.

For Kolla-Ansible templating, use ``stackhpc_prometheus_blackbox_exporter_endpoints_custom``.
For example:

.. code-block:: yaml
   :caption: ``etc/kayobe/kolla/inventory/group_vars/prometheus-blackbox-exporter``

   stackhpc_prometheus_blackbox_exporter_endpoints_custom:
     - 'custom_service:http_2xx:{{ public_protocol }}://{{ external_fqdn | put_address_in_context('url') }}:{{ custom_serivce_port }}'

Alternatively, for Kayobe templating, use the ``prometheus_blackbox_exporter_endpoints_kayobe`` variable.
For example:

.. code-block:: yaml
   :caption: ``kolla/globals.yml``

   prometheus_blackbox_exporter_endpoints_kayobe:
      - endpoints:
         - "pulp:http_2xx:{{ pulp_url }}/pulp/api/v3/status/"
      enabled: "{{ seed_pulp_container_enabled | bool }}"

Ansible playbook subdirectories
-------------------------------

The playbooks under ``etc/kayobe/ansible`` have been subdivided into different
categories to make them easier to navigate. This change may result in merge
conflicts where playbooks have been edited downstream, and broken hooks where
symlinks have been used.

To mitigate the impact of these changes, two scripts have been added:

* ``tools/get-new-playbook-path.sh`` - Returns the new category of a given
  playbook. For example ``tools/get-new-playbook-path.sh
  deploy-os-capacity-exporter.yml`` returns ``deployment/``
* ``tools/magic-symlink-fix.sh`` - Uses the previous script to attempt to fix
  any broken symlinks in the kayobe configuration.

If playbooks are referenced in different methods other than symlinks, they'll
need to be manually resolved by operators. (e.g. Shell scripts running
playbooks with file paths, ``import_playbook`` command in custom playbooks)

Known issues
============

Cinder
------

`Enhancement of Ceph integration of multiple clusters
<https://review.opendev.org/c/openstack/kolla-ansible/+/907166>`__
means the Cinder role now requires ``user`` and ``pool`` set to the each item of kolla dict
variable ``cinder_ceph_backends`` at ``$KAYOBE_CONFIG_PATH/kolla/globals.yml``
(``$KAYOBE_CONFIG_PATH/environments/<env>/kolla/globals.yml`` if using environments)
For example,

.. code:: yaml

   cinder_ceph_backends:
      - name: rbd-1
         cluster: ceph
         user: cinder
         pool: volumes
         enabled: true
      - name: rbd-2
         cluster: ceph-hdd
         user: cinder
         pool: volumes-hdd
         enabled: true

You can find the name of pools from ``cephadm_pools`` in cephadm.yml and name of the users
will be ``cinder`` unless changed to otherwise.

The K-A upstream change `#909974 <https://review.opendev.org/c/openstack/kolla-ansible/+/909974>`__
requires users to manually set Cinder cluster name.
You can find the current name of the cluster from ``cluster`` variable in
``DEFAULT`` category in ``cinder.conf``.

For example,

.. code::

   [DEFAULT]
   cluster = ceph

Match the name of the cluster by setting ``cinder_cluster_name`` in ``$KAYOBE_CONFIG_PATH/kolla/globals.yml``
(``$KAYOBE_CONFIG_PATH/environments/<env>/kolla/globals.yml`` if using environments).

.. code:: yaml

   cinder_cluster_name: ceph

CloudKitty
----------

The Elasticsearch storage driver is no longer compatible with Opensearch storage backend.
Set CloudKitty storage backend to ``opensearch`` if it was set to be ``elasticsearch`` before.
This can be set at ``$KAYOBE_CONFIG_PATH/kolla/globals.yml``
(``$KAYOBE_CONFIG_PATH/environments/<env>/kolla/globals.yml`` if using environments)

.. code:: yaml

   cloudkitty_storage_backend: opensearch

Ironic
------

From Dalmatian, `Kayobe no longer provides its own default driver & interfaces
<https://review.opendev.org/c/openstack/kayobe/+/836999>`__
for Ironic and follows Ironic's default.
This can cause your Ironic configuration ``ironic.conf`` to regress.
Check the configuration difference before applying and re-add your options at
``$KAYOBE_CONFIG_PATH/kolla/config/ironic.conf``
(``$KAYOBE_CONFIG_PATH/environments/<env>/kolla/config/ironic.conf`` if using environments)

For example,

.. code:: yaml

   [DEFAULT]
   enabled_network_interfaces = neutron

RabbitMQ
--------

After some upgrades, it has been seen that RabbitMQ streams do not have replicas across all RabbitMQ nodes.
Errors like this will be logged::

   Basic.consume: (406) PRECONDITION_FAILED - stream queue 'compute_fanout' in vhost '/' does not have a running replica on the local node

A proper fix is still WIP, in the meantime these errors can be resolved with this script:
`<https://gist.github.com/MoteHue/00ba4b85b8e708c46060e025deee8a78>`__

Security baseline
=================

As part of the 2025.1 Epoxy release we are looking to improve the security
baseline of StackHPC OpenStack deployments. If any of the following have not
been done, they should be completed before the upgrade begins.

.. TODO: Add these when docs exist

   * Enable `host firewalling <TODO>`_

* Enable `Center for Internet Security (CIS) compliance <../configuration/security-hardening.html>`_
* Enable TLS on the :kayobe-doc:`public API network
  <configuration/reference/kolla-ansible.html#tls-encryption-of-apis>`
* Enable TLS on the `internal API network <../configuration/vault.html>`_
* Configure `walled garden networking <../configuration/walled-garden.html>`_
* Use `LVM-based host images <../configuration/lvm.html>`_
* Deploy `Wazuh <../configuration/wazuh.html>`_

Prerequisites
=============

Before starting the upgrade, ensure any appropriate prerequisites are
satisfied. These will be specific to each deployment, but here are some
suggestions:

* If hypervisors will be rebooted, e.g. to pick up a new kernel, or
  reprovisioned, ensure that there is sufficient hypervisor capacity to drain
  at least one node.
* If using Ironic for bare metal compute, ensure that at least one node is
  available for testing provisioning.
* Ensure that expected test suites are passing, e.g. Tempest.
* Resolve any Prometheus alerts.
* Check for unexpected ``ERROR`` or ``CRITICAL`` messages in OpenSearch
  Dashboard.
* Check Grafana dashboards.
* Update the deployment to use the latest |previous_release| images and
  configuration.
* If your customer has overriden any policies, check to see if they need
  updating to align with new defaults. These will be written to files
  ``kolla/config/<service>/policy.yaml``. Policy reference documentation can
  generally be found in the documentation of each project. For example, Nova
  policy: https://docs.openstack.org/nova/latest/configuration/policy.html

Ubuntu Noble migration
----------------------

Ubuntu Jammy support has been removed from the 2025.1 release onwards. Hosts
must be migrated to Ubuntu 24.04 before upgrading OpenStack services.
You can find the upgrade procedure from :ref:`upgrading-to-ubuntu-noble`
documentation.


RabbitMQ Prerequisites
----------------------

.. warning::

   StackHPC Kayobe Config sets RabbitMQ 4.1 as the default for the Epoxy release.
   Existing transient queues must be migrated to durable queues with Queue Manager
   before upgrading to RabbitMQ 4.1.

   This means that queue migration and the RabbitMQ 4.1 upgrade must be completed
   before upgrading to Epoxy.

Queue Migration
~~~~~~~~~~~~~~~

.. warning::

   This migration will stop all services using RabbitMQ and cause an extended
   API outage while queues are migrated. It should only be performed in a
   pre-agreed maintenance window.

   If you are using Azimuth or the ClusterAPI driver for Magnum, you should
   make sure to pause reconciliation of all clusters before the API outage
   window. See the `Azimuth docs
   <https://azimuth-cloud.github.io/azimuth-config/operations/maintenance/>`__
   for instructions.

Set the following variables in your kolla globals file (i.e.
``$KAYOBE_CONFIG_PATH/kolla/globals.yml`` or
``$KAYOBE_CONFIG_PATH/environments/$KAYOBE_ENVIRONMENT/kolla/globals.yml``):

.. code-block:: yaml

   om_enable_queue_manager: true
   om_enable_rabbitmq_quorum_queues: true
   om_enable_rabbitmq_transient_quorum_queue: true
   om_enable_rabbitmq_stream_fanout: true

Then execute the migration script:

.. code-block:: bash

   $KAYOBE_CONFIG_PATH/../../tools/rabbitmq-queue-migration.sh

.. note::

   After migrating to durable queues, messages are sent to all receivers, but
   only one will respond. This results in high numbers of messages staying in
   the ready state, so the Prometheus alert ``RabbitMQTooMuchReady`` will start
   firing. This alert can be ignored, and will be removed when Prometheus is
   reconfigured.

RabbitMQ Upgrade
~~~~~~~~~~~~~~~~

After the queue migration is finished, upgrade RabbitMQ to 4.1.

1. Sync and publish latest Kolla container images to ensure local pulp has RabbitMQ 4.1 image.
   (This can be skipped if local pulp is not used.)

   .. code-block:: bash

      kayobe playbook run $KAYOBE_CONFIG_PATH/ansible/pulp-container-sync.yml
      kayobe playbook run $KAYOBE_CONFIG_PATH/ansible/pulp-container-publish.yml

2. Upgrade RabbitMQ to 4.1 with Kolla-Ansible

   .. code-block:: bash

      kayobe kolla ansible run "rabbitmq-upgrade 4.1"

.. _python-3-12:

Python 3.12
-----------

From OpenStack 2025.1, Kayobe and Kolla-Ansible require Python 3.12.

Ubuntu 24.04 has a default Python of version 3.12.
You can find the upgrade procedure from :ref:`upgrading-to-ubuntu-noble`

For Rocky Linux 9, install Python 3.12 manually.

.. code-block:: bash

   dnf install python3.12

For both Operating Systems, Kayobe and Kolla-Ansible Python virtual environments
created with older Python versions will not work with OpenStack 2025.1.

Create a new Kayobe environment and bootstrap the Ansible control host with Python 3.12.
Beokay is recommended when creating and managing the local Kayobe environment.
You can find more information from the :ref:`beokay` documentation.

.. note::

   For Rocky Linux 9, ``beokay create`` must be used with the ``--python python3.12``
   option to specify Beokay to use Python 3.12 as it is not the default.

Kayobe Automation
~~~~~~~~~~~~~~~~~

For deployments using Kayobe Automation CI, the Kayobe Docker image also needs
to be rebuilt with Python 3.12. In GitHub, run the ``Build Kayobe Docker
Image`` workflow. In GitLab, run the ``build_kayobe_image`` pipeline. In either
case, the image will automatically be rebuilt with Python 3.12.

Preparation
===========

Preparation is crucial for a successful upgrade. It allows for a minimal
maintenance/change window and ensures we are ready if unexpected issues arise.

Upgrade plan
------------

The less you need to think on upgrade day, the better. Save your brain for
solving any issues that arise. Write an upgrade plan detailing:

* the predicted schedule
* a checklist of prerequisites
* a set of smoke tests to perform after significant changes
* a list of steps to perform during the preparation phase
* a list of steps to perform during the upgrade maintenance/change window phase
* a list of steps to perform during the follow up phase
* a set of full system tests to perform after the upgrade is complete
* space to make notes of progress and any issues/solutions/workarounds that
  arise

Ideally all steps will include the exact commands to execute that can be
copy/pasted, or links to appropriate CI/CD workflows to run.

Backing up
----------

Before you start, be sure to back up any local changes, configuration, and
data.

See the :kayobe-doc:`Kayobe documentation
<administration/overcloud.html#performing-database-backups>` for information on
backing up the overcloud MariaDB database. It may be prudent to take backups at
various stages of the upgrade since the database state will change over time.

Updating code forks
-------------------

If the deployment uses any source code forks (other than the StackHPC ones),
update them to use the |current_release| release.

Migrating Kayobe Configuration
------------------------------

Kayobe configuration options may be changed between releases of Kayobe. Ensure
that all site local configuration is migrated to the target version format.
See the :skc-doc:`StackHPC Kayobe Configuration release notes
<release-notes.html>`, :kayobe-renos:`Kayobe release notes <>` and
:kolla-ansible-renos:`Kolla Ansible release notes <>`. In particular, the
*Upgrade Notes* and *Deprecation Notes* sections provide information that might
affect the configuration migration.

In the following example we assume a branch naming scheme of
``example/<release>``.

Create a branch for the new release:

.. code-block:: console
   :substitutions:

   git fetch origin
   git checkout example/|previous_release|
   git checkout -b example/|current_release|
   git push origin example/|current_release|

Merge in the new branch of StackHPC Kayobe Configuration:

.. code-block:: console
   :substitutions:

   git remote add stackhpc https://github.com/stackhpc/stackhpc-kayobe-config
   git fetch stackhpc
   git fetch origin
   git checkout -b example/|current_release|-sync origin/example/|current_release|
   git merge stackhpc/|current_release_git_branch_name|

There may be conflicts to resolve. The configuration should be manually
inspected after the merge to ensure that it is correct. Once complete, push the
branch and create a pull request with the changes:

.. code-block:: console
   :substitutions:

   git push origin example/|current_release|-sync

Once approved and merged, update the configuration to adapt to the new release.
This may involve e.g. adding, removing or renaming variables to allow for
upstream changes.  Note that configuration in the base environment
(``etc/kayobe/``) will be merged with upstream changes, but anything in a
deployment-specific environment directory (``etc/kayobe/environments/`` may
require manual inspection.

If using the ``kayobe-env`` environment file in ``kayobe-config``, this should
also be inspected for changes and modified to suit the local Ansible control
host environment if necessary. When ready, source the environment file:

.. code-block:: console

   source kayobe-env

Create one or more pull requests with these changes.

Once the configuration has been migrated, it is possible to view the global
variables for all hosts:

.. code-block:: console

   kayobe configuration dump

The output of this command is a JSON object mapping hosts to their
configuration.  The output of the command may be restricted using the
``--host``, ``--hosts``, ``--var-name`` and ``--dump-facts`` options.

Upgrading local Kayobe environment
----------------------------------

.. warning::

   Python 3.12 is required for OpenStack 2025.1 Kayobe environments.
   The environment cannot be upgraded for this release, it must be rebuilt.
   You can find more information at :ref:`python-3-12`

The local Kayobe environment should be either recreated or upgraded to use the
new release. It may be beneficial to keep a Kayobe environment for the old
release in case it is necessary before the upgrade begins.

In general it is safer to rebuild an environment than upgrade. You can follow
instructions from the :ref:`beokay` documentation.
But for completeness the following shows how to upgrade an existing local Kayobe
environment.

Change to the Kayobe configuration directory:

.. code-block:: console

   cd /path/to/src/kayobe-config

Check the status:

.. code-block:: console

   git status

Pull down the new branch:

.. code-block:: console
   :substitutions:

   git checkout example/|current_release|
   git pull origin example/|current_release|

Activate the Kayobe virtual environment:

.. code-block:: console

   source /path/to/venvs/kayobe/bin/activate

Reinstall Kayobe and other dependencies:

.. code-block:: console

   pip install --force-reinstall -r requirements.txt

Source the ``kayobe-env`` script:

.. code-block:: console

   source kayobe-env [--environment <env>]

Export the Ansible Vault password:

.. code-block:: console

   export KAYOBE_VAULT_PASSWORD=$(cat /path/to/vault/password/file)

Next we must upgrade the Ansible control host.  Tasks performed here include:

- Install updated Ansible collection and role dependencies from Ansible Galaxy.
- Generate an SSH key if necessary and add it to the current user's authorised
  keys.
- Upgrade Kolla Ansible locally to the configured version.

To upgrade the Ansible control host:

.. code-block:: console

   kayobe control host upgrade

Upgrading Pulp
--------------

The local Pulp server needs to be upgraded before synchronising 2025.1
container images. The following command will deploy the latest Pulp container
without upgrading Bifrost:

.. code-block:: console

   kayobe seed service deploy --kolla-tags none --tags seed-manage-containers

Note that this will also update any other enabled seed containers, such as Squid.

Syncing Release Train artifacts
-------------------------------

New :ref:`stackhpc-release-train` content should be synced to the local Pulp
server. This includes host packages (Deb/RPM) and container images.

.. _sync-rt-package-repos:

To sync host packages:

.. code-block:: console

   kayobe playbook run $KAYOBE_CONFIG_PATH/ansible/pulp/pulp-repo-sync.yml
   kayobe playbook run $KAYOBE_CONFIG_PATH/ansible/pulp/pulp-repo-publish.yml

Once the host package content has been tested in a test/staging environment, it
may be promoted to production:

.. code-block:: console

   kayobe playbook run $KAYOBE_CONFIG_PATH/ansible/pulp/pulp-repo-promote-production.yml

To sync container images:

.. code-block:: console

   kayobe playbook run $KAYOBE_CONFIG_PATH/ansible/pulp/pulp-container-sync.yml
   kayobe playbook run $KAYOBE_CONFIG_PATH/ansible/pulp/pulp-container-publish.yml

Build locally customised container images
-----------------------------------------

.. note::

   The container images are provided by StackHPC Release Train are
   suitable for most deployments. In this case, this step can be skipped.

In some cases it is necessary to build some or all images locally to apply
customisations. In order to do this it is necessary to set
``stackhpc_pulp_sync_for_local_container_build`` to ``true`` before
:ref:`syncing container images <sync-rt-package-repos>`.

To build the overcloud images locally and push them to the local Pulp server:

.. code-block:: console

   kayobe overcloud container image build --push

It is possible to build a specific set of images by supplying one or more
image name regular expressions:

.. code-block:: console

   kayobe overcloud container image build --push ironic- nova-api

Pull container images to hosts
------------------------------

Pulling container images from the local Pulp server to the control plane hosts
can take a considerable time, because images are only synced from Ark to the
local Pulp on demand, and there is potentially a large fan-out. Pulling images
in advance of the upgrade moves this step out of the maintenance/change window.
Consider checking available disk space before pulling:

.. code-block:: console

   kayobe overcloud host command run --command "df -h" --show-output --limit controllers[0],compute[0],storage[0]

Then pull the images:

.. code-block:: console

   kayobe overcloud container image pull

Preview overcloud service configuration changes
-----------------------------------------------

Kayobe allows us to generate overcloud service configuration in advance, and
compare it with the running configuration. This allows us to check for any
unexpected changes.

This can take a significant time, and it may be advisable to limit these
commands to one of each type of host (controller, compute, storage, etc.).
The following commands use a limit including the first host in each of these
groups.

Save the old configuration locally.

.. code-block:: console

   kayobe overcloud service configuration save --node-config-dir /etc/kolla --output-dir ~/kolla-diff/old --limit controllers[0],compute[0],storage[0] --exclude ironic-agent.initramfs,ironic-agent.kernel

Generate the new configuration to a tmpdir.

.. code-block:: console

   kayobe overcloud service configuration generate --node-config-dir /tmp/kolla --kolla-limit controllers[0],compute[0],storage[0]

Save the new configuration locally.

.. code-block:: console

   kayobe overcloud service configuration save --node-config-dir /tmp/kolla --output-dir ~/kolla-diff/new --limit controllers[0],compute[0],storage[0] --exclude ironic-agent.initramfs,ironic-agent.kernel

The old and new configuration will be saved to ``~/kolla-diff/old`` and
``~/kolla-diff/new`` respectively on the Ansible control host.

Fix up the paths:

.. code-block:: console

   cd ~/kolla-diff/new
   for i in *; do mv $i/tmp $i/etc; done
   cd -

Compare the old & new configuration:

.. code-block:: console

   diff -ru ~/kolla-diff/{old,new} > ~/kolla-diff.diff
   less ~/kolla-diff.diff

Upgrading the Seed Hypervisor
=============================

Currently, upgrading the seed hypervisor services is not supported.  It may
however be necessary to upgrade host packages and some host services.

Consider whether the seed hypervisor needs to be upgraded within or outside of
a maintenance/change window.

Upgrading Host Packages
-----------------------

.. note::

   In case of issues booting up, consider alternative access methods if the
   hypervisor is also used as the Ansible control host (or runs it in a VM).

Prior to upgrading the seed hypervisor, it may be desirable to upgrade system
packages on the seed hypervisor host.

To update all eligible packages, use ``*``, escaping if necessary:

.. code-block:: console

   kayobe seed hypervisor host package update --packages "*"

If the kernel has been upgraded, reboot the seed hypervisor to pick up the
change:

.. code-block:: console

   kayobe playbook run $KAYOBE_CONFIG_PATH/ansible/maintenance/reboot.yml -l seed-hypervisor

Upgrading Host Services
-----------------------

It may be necessary to upgrade some host services:

.. code-block:: console

   kayobe seed hypervisor host upgrade

Note that this will not perform full configuration of the host, and will
instead perform a targeted upgrade of specific services where necessary.

Configuring hosts
-----------------

Performing host configuration is not a formal part of the upgrade process, but
it is possible for host configuration to drift over time as new features and
other changes are added to Kayobe.

Host configuration, particularly around networking, can lead to loss of network
connectivity and other issues if the configuration is not correct. For this
reason it is sensible to first run Ansible in "check mode" to see what changes
would be applied:

.. code-block:: console

   kayobe seed hypervisor host configure --check --diff

When ready to apply the changes:

.. code-block:: console

   kayobe seed hypervisor host configure

Upgrading the Seed
==================

Consider whether the seed needs to be upgraded within or outside of a
maintenance/change window.

Upgrading Host Packages
-----------------------

.. note::

   In case of issues booting up, consider alternative access methods if the
   seed is also used as the Ansible control host.

Prior to upgrading the seed, it may be desirable to upgrade system packages on
the seed host.

Note that these commands do not affect packages installed in containers, only
those installed on the host.

To update all eligible packages, use ``*``, escaping if necessary:

.. code-block:: console

   kayobe seed host package update --packages "*"

If the kernel has been upgraded, reboot the seed to pick up the change:

.. code-block:: console

   kayobe playbook run $KAYOBE_CONFIG_PATH/ansible/maintenance/reboot.yml -l seed

Verify that Bifrost, Ironic and Inspector are running as expected:

.. code-block:: console

   ssh stack@<seed>
   sudo docker exec -it bifrost_deploy bash
   systemctl
   export OS_CLOUD=bifrost
   baremetal node list
   baremetal introspection list
   exit
   exit

Building Ironic Deployment Images
---------------------------------

.. note::

   It is possible to use prebuilt deployment images. In this case, this step
   can be skipped.

It is possible to use prebuilt deployment images from the `OpenStack hosted
tarballs <https://tarballs.openstack.org/ironic-python-agent>`_ or another
source.  In some cases it may be necessary to build images locally either to
apply local image customisation or to use a downstream version of Ironic Python
Agent (IPA).  In order to build IPA images, the ``ipa_build_images`` variable
should be set to ``True``.  To build images locally:

.. code-block:: console

   kayobe seed deployment image build

To overwrite existing images, add the ``--force-rebuild`` argument.

Upgrading Host Services
-----------------------

It may be necessary to upgrade some host services:

.. code-block:: console

   kayobe seed host upgrade

Note that this will not perform full configuration of the host, and will
instead perform a targeted upgrade of specific services where necessary.

Configuring hosts
-----------------

Performing host configuration is not a formal part of the upgrade process, but
it is possible for host configuration to drift over time as new features and
other changes are added to Kayobe.

Host configuration, particularly around networking, can lead to loss of network
connectivity and other issues if the configuration is not correct. For this
reason it is sensible to first run Ansible in "check mode" to see what changes
would be applied:

.. code-block:: console

   kayobe seed host configure --check --diff

When ready to apply the changes:

.. code-block:: console

   kayobe seed host configure

Building Container Images
-------------------------

.. note::

   The container images are provided by StackHPC Release Train are
   suitable for most deployments. In this case, this step can be skipped.

In some cases it is necessary to build some or all images locally to apply
customisations. In order to do this it is necessary to set
``stackhpc_pulp_sync_for_local_container_build`` to ``true`` before
:ref:`syncing container images <sync-rt-package-repos>`.

To build the seed images locally and push them to the local Pulp server:

.. code-block:: console

   kayobe seed container image build --push

Upgrading Containerised Services
--------------------------------

Containerised seed services may be upgraded by replacing existing containers
with new containers using updated images which have been pulled from the local
Pulp registry.

To upgrade the containerised seed services:

.. code-block:: console

   kayobe seed service upgrade

Verify that Bifrost, Ironic and Inspector are running as expected:

.. code-block:: console

   ssh stack@<seed>
   sudo docker exec -it bifrost_deploy bash
   systemctl
   export OS_CLOUD=bifrost
   baremetal node list
   baremetal introspection list
   exit
   exit

Upgrading Wazuh Manager
=======================

Consider whether Wazuh Manager needs to be upgraded within or outside of a
maintenance/change window.

Upgrading Host Packages
-----------------------

Prior to upgrading the Wazuh manager services, it may be desirable to upgrade
system packages on the Wazuh manager host.

To update all eligible packages, use ``*``, escaping if necessary:

.. code-block:: console

   kayobe infra vm host package update --packages "*" -l wazuh-manager

If the kernel has been upgraded, reboot the Wazuh Manager to pick up the
change:

.. code-block:: console

   kayobe playbook run $KAYOBE_CONFIG_PATH/ansible/maintenance/reboot.yml -l wazuh-manager

Verify that Wazuh Manager is functioning correctly by :ref:`logging into the
Wazuh UI <wazuh-verification>`.

Configuring hosts
-----------------

Performing host configuration is not a formal part of the upgrade process, but
it is possible for host configuration to drift over time as new features and
other changes are added to Kayobe.

Host configuration, particularly around networking, can lead to loss of network
connectivity and other issues if the configuration is not correct. For this
reason it is sensible to first run Ansible in "check mode" to see what changes
would be applied:

.. code-block:: console

   kayobe infra vm host configure --check --diff -l wazuh-manager

When ready to apply the changes:

.. code-block:: console

   kayobe infra vm host configure -l wazuh-manager

Upgrade Wazuh Manager services
------------------------------

.. todo

   Is this the correct way to update Wazuh Manager?

Run the following playbook to update Wazuh Manager services and configuration:

.. code-block:: console

   kayobe playbook run $KAYOBE_CONFIG_PATH/ansible/deployment/wazuh-manager.yml

Verify that Wazuh Manager is functioning correctly by :ref:`logging into the
Wazuh UI <wazuh-verification>`.

Upgrading Wazuh Agents
======================

Consider whether Wazuh Agents need to be upgraded within or outside of a
maintenance/change window.

Upgrade Wazuh Agent services
----------------------------

.. todo

   Is this the correct way to update Wazuh Agents?

Run the following playbook to update Wazuh Agent services and configuration:

.. code-block:: console

   kayobe playbook run $KAYOBE_CONFIG_PATH/ansible/deployment/wazuh-agent.yml

Verify that the agents have conncted to Wazuh Manager correctly by
:ref:`logging into the Wazuh UI <wazuh-verification>`.

Upgrading the Overcloud
=======================

Consider which of the overcloud upgrade steps need to be performed within or
outside of a maintenance/change window.

Upgrading Host Packages
-----------------------

Prior to upgrading the OpenStack control plane, it may be desirable to upgrade
system packages on the overcloud hosts.

Note that these commands do not affect packages installed in containers, only
those installed on the host.

In order to avoid downtime, it is important to control how package updates are
rolled out. In general, controllers and network hosts should be updated *one by
one*, ideally updating the host with the Virtual IP (VIP) last. For hypervisors
it may be possible to update packages in batches of hosts, provided there is
sufficient capacity to migrate VMs to other hypervisors.

For each host or batch of hosts, perform the following steps.

If the host is a hypervisor, disable the Nova compute service and drain it of
VMs using live migration. If any VMs fail to migrate, they may be cold migrated
or powered off:

.. code-block:: console

   kayobe playbook run $KAYOBE_CONFIG_PATH/ansible/maintenance/nova-compute-{disable,drain}.yml --limit <host>

To update all eligible packages, use ``*``, escaping if necessary:

.. code-block:: console

   kayobe overcloud host package update --packages "*" --limit <host>

.. note::

   Due to a `security-related change in the GRUB package on Rocky Linux 9
   <https://access.redhat.com/security/cve/CVE-2023-4001>`__, the operating
   system can become unbootable (boot will stop at a ``grub>`` prompt). Remove
   the ``--root-dev-only`` option from ``/boot/efi/EFI/rocky/grub.cfg`` after
   applying package updates. This will happen automatically as a post hook when
   running the ``kayobe overcloud host package update`` command.

If the kernel has been upgraded, reboot the host or batch of hosts to pick up
the change:

.. code-block:: console

   kayobe playbook run $KAYOBE_CONFIG_PATH/ansible/maintenance/reboot.yml -l <host>

.. warning::

   Take extra care when updating packages on Ceph hosts. Docker live-restore
   does not work until the Squid version of Ceph, so a reload of docker will
   restart all Ceph containers. Set the hosts to maintenance mode before
   updating packages, and unset when done:

   .. code-block:: console

      kayobe playbook run $KAYOBE_CONFIG_PATH/ansible/ceph/ceph-enter-maintenance.yml --limit <host>
      kayobe overcloud host package update --packages "*" --limit <host>
      kayobe playbook run $KAYOBE_CONFIG_PATH/ansible/maintenance/reboot.yml -l <host>
      kayobe playbook run $KAYOBE_CONFIG_PATH/ansible/ceph/ceph-exit-maintenance.yml --limit <host>

   **Always** reconfigure hosts in small batches or one-by-one. Check the Ceph
   state after each host configuration. Ensure all warnings and errors are
   resolved before moving on.

If the host is a hypervisor, enable the Nova compute service.

.. code-block:: console

   kayobe playbook run $KAYOBE_CONFIG_PATH/ansible/maintenance/nova-compute-enable.yml --limit <host>

If any VMs were powered off, they may now be powered back on.

Wait for Prometheus alerts and errors in OpenSearch Dashboard to resolve, or
address them.

After updating controllers or network hosts, run any appropriate smoke tests.

Once happy that the system has been restored to full health, move onto the next
host or batch or hosts.

Upgrading Host Services
-----------------------

Prior to upgrading the OpenStack control plane, the overcloud host services
should be upgraded:

.. code-block:: console

   kayobe overcloud host upgrade

Note that this will not perform full configuration of the host, and will
instead perform a targeted upgrade of specific services where necessary.

Configuring hosts
-----------------

Performing host configuration is not a formal part of the upgrade process, but
it is possible for host configuration to drift over time as new features and
other changes are added to Kayobe.

Host configuration, particularly around networking, can lead to loss of network
connectivity and other issues if the configuration is not correct. For this
reason it is sensible to first run Ansible in "check mode" to see what changes
would be applied:

.. code-block:: console

   kayobe overcloud host configure --check --diff

When ready to apply the changes, it may be advisable to do so in batches, or at
least start with a small number of hosts:

.. code-block:: console

   kayobe overcloud host configure --limit <host>


.. warning::

   Take extra care when configuring Ceph hosts. Set the hosts to maintenance
   mode before reconfiguring them, and unset when done:

   .. code-block:: console

      kayobe playbook run $KAYOBE_CONFIG_PATH/ansible/ceph/ceph-enter-maintenance.yml --limit <host>
      kayobe overcloud host configure --limit <host>
      kayobe playbook run $KAYOBE_CONFIG_PATH/ansible/ceph/ceph-exit-maintenance.yml --limit <host>

   **Always** reconfigure hosts in small batches or one-by-one. Check the Ceph
   state after each host configuration. Ensure all warnings and errors are
   resolved before moving on.

.. _building_ironic_deployment_images:

Building Ironic Deployment Images
---------------------------------

.. note::

   It is possible to use prebuilt deployment images. In this case, this step
   can be skipped.

It is possible to use prebuilt deployment images from the `OpenStack hosted
tarballs <https://tarballs.openstack.org/ironic-python-agent>`_ or another
source.  In some cases it may be necessary to build images locally either to
apply local image customisation or to use a downstream version of Ironic Python
Agent (IPA).  In order to build IPA images, the ``ipa_build_images`` variable
should be set to ``True``.  To build images locally:

.. code-block:: console

   kayobe overcloud deployment image build

To overwrite existing images, add the ``--force-rebuild`` argument.

Upgrading Ironic Deployment Images
----------------------------------

Prior to upgrading the OpenStack control plane you should upgrade
the deployment images. If you are using prebuilt images, update
the following variables in ``etc/kayobe/ipa.yml`` accordingly:

* ``ipa_kernel_upstream_url``
* ``ipa_kernel_checksum_url``
* ``ipa_kernel_checksum_algorithm``
* ``ipa_ramdisk_upstream_url``
* ``ipa_ramdisk_checksum_url``
* ``ipa_ramdisk_checksum_algorithm``

Alternatively, you can update the files that the URLs point to. If building the
images locally, follow the process outlined in
:ref:`building_ironic_deployment_images`.

To get Ironic to use an updated set of overcloud deployment images, you can run:

.. code-block:: console

   kayobe baremetal compute update deployment image

This will register the images in Glance and update the ``deploy_ramdisk``
and ``deploy_kernel`` properties of the Ironic nodes.

Before rolling out the update to all nodes, it can be useful to test the image
on a limited subset. To do this, you can use the ``--baremetal-compute-limit``
option. The argument should take the form of an `ansible host pattern
<https://docs.ansible.com/ansible/latest/user_guide/intro_patterns.html>`_
which is matched against the Ironic node name.

Upgrading Containerised Services
--------------------------------

Containerised control plane services may be upgraded by replacing existing
containers with new containers using updated images which have been pulled from
a registry or built locally.

If using overcloud Ironic, check whether any ironic nodes are in a wait state:

.. code-block:: console

   baremetal node list | grep wait

This will block the upgrade, but may be overridden by setting
``ironic_upgrade_skip_wait_check`` to ``true`` in
``etc/kayobe/kolla/globals.yml`` or
``etc/kayobe/environments/<env>/kolla/globals.yml``.

To upgrade the containerised control plane services:

.. code-block:: console

   kayobe overcloud service upgrade

It is possible to specify tags for Kayobe and/or kolla-ansible to restrict the
scope of the upgrade:

.. code-block:: console

   kayobe overcloud service upgrade --tags config --kolla-tags keystone

Updating the Octavia Amphora Image
----------------------------------

If using Octavia with the Amphora driver, you should :ref:`update the amphora
image <Amphora image>`.

Testing
-------

At this point it is recommended to perform a thorough test of the system to
catch any unexpected issues. This may include:

* Check Prometheus, OpenSearch Dashboards and Grafana
* Smoke tests
* All applicable tempest tests
* Horizon UI inspection

Cleaning up
===========

Prune unused container images:

.. code-block:: console

   kayobe overcloud host command run -b --command "docker image prune -a -f"
