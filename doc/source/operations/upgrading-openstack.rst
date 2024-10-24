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

Heat disabled by default
------------------------

The Heat OpenStack service is no longer enabled by default.

This behavior can be overridden manually:

.. code-block:: yaml
   :caption: ``kolla.yml``

   kolla_enable_heat: true

Wherever possible, Magnum deployments should be migrated to the CAPI Helm
driver. Instructions for enabling the driver can be found `here
<../configuration/magnum-capi.rst>`_. Enable the driver, recreate any clusters
using Heat, and disable the service.

TODO: guide for disabling Heat

Designate sink disabled by default
----------------------------------

Designate sink is an optional Designate service which listens for event
notifications, primarily from Nova and Neutron. It is disabled by default (when
designate is enabled) in Caracal. It is not required for Designate to function.

If you still wish to use it, you should set the flag manually:

.. code-block:: yaml
   :caption: ``kolla/globals.yml``

   designate_enable_notifications_sink: true

If you are using Designate and do not make this change, the Antelope
``designate-sink`` container will remain on the controllers after the upgrade.
It must be removed manually.

Grafana Volume
--------------
The Grafana container volume is no longer used. If you wish to automatically
remove the old volume, set ``grafana_remove_old_volume`` to ``true`` in
``kolla/globals.yml``. Note that doing this will lose any plugins installed via
the CLI directly and not through Kolla. If you have previously installed
Grafana plugins via the Grafana UI or CLI, you must change to installing them
at image build time. The Grafana volume, which contains existing custom
plugins, will be automatically removed in the next release.

Prometheus HAproxy Exporter
---------------------------
Due to the change from using the ``prometheus-haproxy-exporter`` to using the
native support for Prometheus which is now built into HAProxy, metric names may
have been replaced and/or removed, and in some cases the metric names may have
remained the same but the labels may have changed. Alerts and dashboards may
also need to be updated to use the new metrics. Please review any configuration
that references the old metrics as this is not a backwards compatible change.

Horizon configuration
---------------------
The Horizon role has been reworked to the preferred ``local_settings.d``
configuration model. Files ``local_settings`` and ``custom_local_settings``
have been renamed to ``_9998-kolla-settings.py`` and
``_9999-custom-settings.py`` respectively. Users who use Horizon's custom
configuration must change the names of those files in
``etc/kolla/config/horizon`` as well.

Neutron DNS Domain
------------------
When Designate is enabled and the default Neutron DNS integration has not been
disabled, ``neutron_dns_domain`` must be configured manually in
``kolla/globals.yml``.

The ``neutron_dns_domain`` must end with a period ``.`` e.g. ``example.com.``.
The domain set should be something that is not use anywhere else such as
``internal.compute.example.com.``

The Neuron DNS integration can be disabled by setting
``neutron_dns_integration: false`` in ``kolla/globals.yml``

Redis Default User
------------------

The ``redis_connection_string`` has changed the username used from ``admin``
to ``default``. Whilst this does not have any negative impact on services
that utilise Redis it will feature prominently in any preview of the overcloud
configuration.

Known issues
============

* Due to an incorrect default value NGS will attempt to use v3alpha for the api
  path when communicating with etcd3. This isn't possible as in Caracal etcd is
  running a newer version that has dropped support for v3alpha. You can work
  around this in custom config, see the SMS PR for an example:
  https://github.com/stackhpc/smslab-kayobe-config/pull/354

Security baseline
=================

As part of the Caracal release we are looking to improve the security
baseline of StackHPC OpenStack deployments. If any of the following have not
been done, they should be completed before the upgrade begins.

.. TODO: Add these when docs exist

   * Enable `host firewalling <TODO>`_

* Enable `Center for Internet Security (CIS) compliance <../configuration/security-hardening.rst>`_
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

RabbitMQ SLURP upgrade
----------------------

.. note::
   The upgrade is reliant on recent changes. Make sure you have updated to
   the latest version of kolla ansible and deployed the latest kolla containers
   before proceeding.

Because this is a SLURP upgrade, RabbitMQ must be upgraded manually from 3.11,
to 3.12, then to 3.13 on Antelope before the Caracal upgrade. This upgrade
should not cause an API outage (though it should still be considered "at
risk").

Some errors have been observed in testing when the upgrades are perfomed
back-to-back. A 200s delay eliminates this issue. On particularly large or slow
deployments, consider increasing this timeout.

.. code-block:: bash

   kayobe overcloud service configuration generate --node-config-dir /tmp/ignore -kt none
   kayobe kolla ansible run "rabbitmq-upgrade 3.12"
   sleep 200
   kayobe kolla ansible run "rabbitmq-upgrade 3.13"

RabbitMQ quorum queues
----------------------

In Caracal, quorum queues are enabled by default for RabbitMQ. This is
different to Antelope which used HA queues. Before upgrading to Caracal, it is
strongly recommended that you migrate from HA to quorum queues. The migration
is automated using a script.

.. warning::
   This migration will stop all services using RabbitMQ and cause an
   extended API outage while queues are migrated. It should only be
   performed in a pre-agreed maintenance window.

Set the following variables in your kolla globals file (i.e.
``$KAYOBE_CONFIG_PATH/kolla/globals.yml`` or
``$KAYOBE_CONFIG_PATH/environments/$KAYOBE_ENVIRONMENT/kolla/globals.yml``):

.. code-block:: yaml

      om_enable_rabbitmq_high_availability: false
      om_enable_rabbitmq_quorum_queues: true

Then execute the migration script:

.. code-block:: bash

   $KAYOBE_CONFIG_PATH/../../tools/rabbitmq-quorum-migration.sh

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

The local Kayobe environment should be either recreated or upgraded to use the
new release. It may be beneficial to keep a Kayobe environment for the old
release in case it is necessary before the uprade begins.

In general it is safer to rebuild an environment than upgrade, but for
completeness the following shows how to upgrade an existing local Kayobe
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

Syncing Release Train artifacts
-------------------------------

New `StackHPC Release Train <../configuration/release-train>` content should be
synced to the local Pulp server. This includes host packages (Deb/RPM) and
container images.

.. _sync-rt-package-repos:

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

   kayobe playbook run $KAYOBE_CONFIG_PATH/ansible/reboot.yml -l seed-hypervisor

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

   kayobe playbook run $KAYOBE_CONFIG_PATH/ansible/reboot.yml -l seed

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

   kayobe playbook run $KAYOBE_CONFIG_PATH/ansible/reboot.yml -l wazuh-manager

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

   kayobe playbook run $KAYOBE_CONFIG_PATH/ansible/wazuh-manager.yml

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

   kayobe playbook run $KAYOBE_CONFIG_PATH/ansible/wazuh-agent.yml

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

   kayobe playbook run $KAYOBE_CONFIG_PATH/ansible/nova-compute-{disable,drain}.yml --limit <host>

To update all eligible packages, use ``*``, escaping if necessary:

.. code-block:: console

   kayobe overcloud host package update --packages "*" --limit <host>

If the kernel has been upgraded, reboot the host or batch of hosts to pick up
the change:

.. code-block:: console

   kayobe playbook run $KAYOBE_CONFIG_PATH/ansible/reboot.yml -l <host>

If the host is a hypervisor, enable the Nova compute service.

.. code-block:: console

   kayobe playbook run $KAYOBE_CONFIG_PATH/ansible/nova-compute-enable.yml --limit <host>

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
least start with a small number of hosts.:

.. code-block:: console

   kayobe overcloud host configure --limit <host>

Alternatively, to apply the configuration to all hosts:

.. code-block:: console

   kayobe overcloud host configure

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

If using Octavia with the Amphora driver, you should :ref:`build a new amphora
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
