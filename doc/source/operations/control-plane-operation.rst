=======================
Operating Control Plane
=======================

Backup of the OpenStack Control Plane
=====================================

As the backup procedure is constantly changing, it is normally best to check
the upstream documentation for an up to date procedure. Here is a high level
overview of the key things you need to backup:

Controllers
-----------

* `Back up SQL databases <https://docs.openstack.org/kayobe/latest/administration/overcloud.html#performing-database-backups>`__
* `Back up configuration in /etc/kolla <https://docs.openstack.org/kayobe/latest/administration/overcloud.html#saving-overcloud-service-configuration>`__

Compute
-------

The compute nodes can largely be thought of as ephemeral, but you do need to
make sure you have migrated any instances and disabled the hypervisor before
rebooting, decommissioning or making any disruptive configuration change.

Monitoring
----------

* `Back up InfluxDB <https://docs.influxdata.com/influxdb/v1.8/administration/backup_and_restore/>`__
* `Back up OpenSearch <https://opensearch.org/docs/latest/tuning-your-cluster/availability-and-recovery/snapshots/snapshot-restore/>`__
* `Back up Prometheus <https://prometheus.io/docs/prometheus/latest/querying/api/#snapshot>`__

Seed
----

* `Back up bifrost <https://docs.openstack.org/kayobe/latest/administration/seed.html#database-backup-restore>`__

Ansible control host
--------------------

* Back up service VMs such as the seed VM

Control Plane Monitoring
========================

This section shows user guide of monitoring control plane. To see how to
configure monitoring services, read :ref:`monitoring-service-configuration`.

The control plane has been configured to collect logs centrally using Fluentd,
OpenSearch and OpenSearch Dashboards.

Telemetry monitoring of the control plane is performed by Prometheus. Metrics
are collected by Prometheus exporters, which are either running on all hosts
(e.g.  node exporter), on specific hosts (e.g. controllers for the memcached
exporter or monitoring hosts for the OpenStack exporter). These exporters are
scraped by the Prometheus server.

Configuring Prometheus Alerts
-----------------------------

Alerts are defined in code and stored in Kayobe configuration. See ``*.rules``
files in ``$KAYOBE_CONFIG_PATH/kolla/config/prometheus`` as a model to add
custom rules.

Silencing Prometheus Alerts
---------------------------

Sometimes alerts must be silenced because the root cause cannot be resolved
right away, such as when hardware is faulty. For example, an unreachable
hypervisor will produce several alerts:

* ``InstanceDown`` from Node Exporter
* ``OpenStackServiceDown`` from the OpenStack exporter, which reports status of
  the ``nova-compute`` agent on the host
* ``PrometheusTargetMissing`` from several Prometheus exporters

Rather than silencing each alert one by one for a specific host, a silence can
apply to multiple alerts using a reduced list of labels. Log into Alertmanager,
click on the ``Silence`` button next to an alert and adjust the matcher list
to keep only ``instance=<hostname>`` label.
Then, create another silence to match ``hostname=<hostname>`` (this is
required because, for the OpenStack exporter, the instance is the host running
the monitoring service rather than the host being monitored).

Control Plane Shutdown Procedure
================================

For a shutdown of the whole cloud, see :doc:`shutdown-and-startup`.

Single-node maintenance
-----------------------

Before shutting down a compute node, migrate its instances to another node.
See :doc:`migrating-vm`.

Before shutting down a controller, repeat the cluster checks from
:ref:`shutdown-pre-flight`. Shut down only one controller at a time.

For a Bifrost-managed compute, controller, network or monitoring node, run on
the seed VM:

.. code-block:: console

   docker exec bifrost_deploy baremetal --os-cloud bifrost \
       node maintenance set --reason maintenance <node>
   docker exec bifrost_deploy baremetal --os-cloud bifrost \
       node power off --soft <node>

Wait for the node to reach ``power off``. To start it again:

.. code-block:: console

   docker exec bifrost_deploy baremetal --os-cloud bifrost \
       node power on <node>

After the node is healthy, remove maintenance mode:

.. code-block:: console

   docker exec bifrost_deploy baremetal --os-cloud bifrost \
       node maintenance unset <node>

For a seed VM hosted on the seed hypervisor, run on the seed hypervisor to stop
it:

.. code-block:: console

   virsh shutdown <seed VM>

To start it again:

.. code-block:: console

   virsh start <seed VM>

Rebooting a node
----------------

Use ``reboot.yml`` playbook to reboot nodes
Example: Reboot all compute hosts apart from compute0:

.. code-block:: console

   kayobe playbook run $KAYOBE_CONFIG_PATH/ansible/maintenance/reboot.yml --limit 'compute:!compute0'

Software Updates
================

Sync local Pulp server with StackHPC Release Train
--------------------------------------------------

The host packages and Kolla container images are distributed from `StackHPC Release Train
<https://stackhpc.github.io/stackhpc-release-train/>`__ to ensure tested and reliable
software releases are provided.

Syncing new StackHPC Release Train contents to local Pulp server is needed before updating
host packages and/or Kolla services.

To sync host packages:

.. code-block:: console

   kayobe playbook run $KAYOBE_CONFIG_PATH/ansible/pulp/pulp-repo-sync.yml
   kayobe playbook run $KAYOBE_CONFIG_PATH/ansible/pulp/pulp-repo-publish.yml

If the system is production environment and want to use packages tested in test/staging
environment, you can promote them by:

.. code-block:: console

   kayobe playbook run $KAYOBE_CONFIG_PATH/ansible/pulp/pulp-repo-promote-production.yml

To sync container images:

.. code-block:: console

   kayobe playbook run $KAYOBE_CONFIG_PATH/ansible/pulp/pulp-container-sync.yml
   kayobe playbook run $KAYOBE_CONFIG_PATH/ansible/pulp/pulp-container-publish.yml

For more information about StackHPC Release Train, see :ref:`stackhpc-release-train` documentation.

Once sync with StackHPC Release Train is done, new contents will be accessible from local
Pulp server.

Update Host Packages on Control Plane
-------------------------------------

Host packages can be updated with:

.. code-block:: console

   kayobe overcloud host package update --limit <node> --packages '*'
   kayobe seed host package update --packages '*'

See https://docs.openstack.org/kayobe/latest/administration/overcloud.html#updating-packages

Troubleshooting
===============

Deploying to a Specific Hypervisor
----------------------------------

To test creating an instance on a specific hypervisor, *as an admin-level user*
you can specify the hypervisor name.

To see the list of hypervisor names:

.. code-block:: console

   # From host that can reach Openstack
   openstack hypervisor list

To boot an instance on a specific hypervisor

.. code-block:: console

   openstack server create --flavor <flavour name> --network <network name> --key-name <key name> --image <image name> --os-compute-api-version 2.74 --host <hypervisor hostname> <vm name>

OpenSearch indexes retention
=============================

To alter default rotation values for OpenSearch, edit

``$KAYOBE_CONFIG_PATH/kolla/globals.yml``:

.. code-block:: console

   # Duration after which index is closed (default 30)
   opensearch_soft_retention_period_days: 90
   # Duration after which index is deleted (default 60)
   opensearch_hard_retention_period_days: 180

Reconfigure Opensearch with new values:

.. code-block:: console

   kayobe overcloud service reconfigure --kolla-tags opensearch

For more information see the `upstream documentation
<https://docs.openstack.org/kolla-ansible/latest/reference/logging-and-monitoring/central-logging-guide.html#applying-log-retention-policies>`__.
