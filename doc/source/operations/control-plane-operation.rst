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
decommissioning or making any disruptive configuration change.

Monitoring
----------

* `Back up InfluxDB <https://docs.influxdata.com/influxdb/v1.8/administration/backup_and_restore/>`__
* `Back up ElasticSearch <https://www.elastic.co/guide/en/elasticsearch/reference/current/backup-cluster-data.html>`__
* `Back up Prometheus <https://prometheus.io/docs/prometheus/latest/querying/api/#snapshot>`__

Seed
----

* `Back up bifrost <https://docs.openstack.org/kayobe/latest/administration/seed.html#database-backup-restore>`__

Ansible control host
--------------------

* Back up service VMs such as the seed VM

Control Plane Monitoring
========================

The control plane has been configured to collect logs centrally using the EFK
stack (Elasticsearch, Fluentd and Kibana).

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
apply to multiple alerts using a reduced list of labels. :ref:`Log into
Alertmanager <prometheus-alertmanager>`, click on the ``Silence`` button next
to an alert and adjust the matcher list to keep only ``instance=<hostname>``
label.  Then, create another silence to match ``hostname=<hostname>`` (this is
required because, for the OpenStack exporter, the instance is the host running
the monitoring service rather than the host being monitored).

.. note::

   After creating the silence, you may get redirected to a 404 page. This is a
   `known issue <https://github.com/prometheus/alertmanager/issues/1377>`__
   when running several Alertmanager instances behind HAProxy.

Generating Alerts from Metrics
++++++++++++++++++++++++++++++

Alerts are defined in code and stored in Kayobe configuration. See ``*.rules``
files in ``$KAYOBE_CONFIG_PATH/kolla/config/prometheus`` as a model to add
custom rules.

Control Plane Shutdown Procedure
================================

Overview
--------

* Verify integrity of clustered components (RabbitMQ, Galera, Keepalived). They
  should all report a healthy status.
* Put node into maintenance mode in bifrost to prevent it from automatically
  powering back on
* Shutdown down nodes one at a time gracefully using systemctl poweroff

Controllers
-----------

If you are restarting the controllers, it is best to do this one controller at
a time to avoid the clustered components losing quorum.

Checking Galera state
+++++++++++++++++++++

On each controller perform the following:

.. code-block:: console

   [stack@controller0 ~]$ docker exec -i mariadb mysql -u root -p -e "SHOW STATUS LIKE 'wsrep_local_state_comment'"
   Variable_name   Value
   wsrep_local_state_comment       Synced

The password can be found using:

.. code-block:: console

   kayobe# ansible-vault view $KAYOBE_CONFIG_PATH/kolla/passwords.yml \
           --vault-password-file <Vault password file path> | grep ^database

Checking RabbitMQ
+++++++++++++++++

RabbitMQ health is determined using the command ``rabbitmqctl cluster_status``:

.. code-block:: console

   [stack@controller0 ~]$ docker exec rabbitmq rabbitmqctl cluster_status

   Cluster status of node rabbit@controller0 ...
   [{nodes,[{disc,['rabbit@controller0','rabbit@controller1',
                   'rabbit@controller2']}]},
    {running_nodes,['rabbit@controller1','rabbit@controller2',
                    'rabbit@controller0']},
    {cluster_name,<<"rabbit@controller2">>},
    {partitions,[]},
    {alarms,[{'rabbit@controller1',[]},
             {'rabbit@controller2',[]},
             {'rabbit@controller0',[]}]}]

Checking Keepalived
+++++++++++++++++++

On (for example) three controllers:

.. code-block:: console

   [stack@controller0 ~]$ docker logs keepalived

Two instances should show:

.. code-block:: console

   VRRP_Instance(kolla_internal_vip_51) Entering BACKUP STATE

and the other:

.. code-block:: console

   VRRP_Instance(kolla_internal_vip_51) Entering MASTER STATE

Ansible Control Host
--------------------

The Ansible control host is not enrolled in bifrost. This node may run services
such as the seed virtual machine which will need to be gracefully powered down.

Compute
-------

If you are shutting down a single hypervisor, to avoid down time to tenants it
is advisable to migrate all of the instances to another machine. See
:ref:`evacuating-all-instances`.

Ceph
----

The following guide provides a good overview:
https://access.redhat.com/documentation/en-us/red_hat_openstack_platform/8/html/director_installation_and_usage/sect-rebooting-ceph

Shutting down the seed VM
-------------------------

.. code-block:: console

   kayobe# virsh shutdown <Seed hostname>

.. _full-shutdown:

Full shutdown
-------------

In case a full shutdown of the system is required, we advise to use the
following order:

* Perform a graceful shutdown of all virtual machine instances
* Shut down compute nodes
* Shut down monitoring node
* Shut down network nodes (if separate from controllers)
* Shut down controllers
* Shut down Ceph nodes (if applicable)
* Shut down seed VM
* Shut down Ansible control host

Rebooting a node
----------------

Example: Reboot all compute hosts apart from compute0:

.. code-block:: console

   kayobe# kayobe overcloud host command run --limit 'compute:!compute0' -b --command "shutdown -r"

References
----------

* https://galeracluster.com/library/training/tutorials/restarting-cluster.html

Control Plane Power on Procedure
================================

Overview
--------

* Remove the node from maintenance mode in bifrost
* Bifrost should automatically power on the node via IPMI
* Check that all docker containers are running
* Check Kibana for any messages with log level ERROR or equivalent

Controllers
-----------

If all of the servers were shut down at the same time, it is necessary to run a
script to recover the database once they have all started up. This can be done
with the following command:

.. code-block:: console

   kayobe# kayobe overcloud database recover

Ansible Control Host
--------------------

The Ansible control host is not enrolled in Bifrost and will have to be powered
on manually.

Seed VM
-------

The seed VM (and any other service VM) should start automatically when the seed
hypervisor is powered on. If it does not, it can be started with:

.. code-block:: console

   kayobe# virsh start <Seed hostname>

Full power on
-------------

Follow the order in :ref:`full-shutdown`, but in reverse order.

Shutting Down / Restarting Monitoring Services
----------------------------------------------

Shutting down
+++++++++++++

Log into the monitoring host(s):

.. code-block:: console

   kayobe# ssh stack@monitoring0

Stop all Docker containers:

.. code-block:: console

   monitoring0# for i in `docker ps -q`; do docker stop $i; done

Shut down the node:

.. code-block:: console

   monitoring0# sudo shutdown -h

Starting up
+++++++++++

The monitoring services containers will automatically start when the monitoring
node is powered back on.

Software Updates
================

Update Packages on Control Plane
--------------------------------

OS packages can be updated with:

.. code-block:: console

   kayobe# kayobe overcloud host package update --limit <Hypervisor node> --packages '*'
   kayobe# kayobe overcloud seed package update --packages '*'

See https://docs.openstack.org/kayobe/latest/administration/overcloud.html#updating-packages

Minor Upgrades to OpenStack Services
------------------------------------

* Pull latest changes from upstream stable branch to your own ``kolla`` fork (if applicable)
* Update ``kolla_openstack_release`` in ``etc/kayobe/kolla.yml`` (unless using default)
* Update tags for the images in ``etc/kayobe/kolla/globals.yml`` to use the new value of ``kolla_openstack_release``
* Rebuild container images
* Pull container images to overcloud hosts
* Run kayobe overcloud service upgrade

For more information, see: https://docs.openstack.org/kayobe/latest/upgrading.html

Troubleshooting
===============

Deploying to a Specific Hypervisor
----------------------------------

To test creating an instance on a specific hypervisor, *as an admin-level user*
you can specify the hypervisor name as part of an extended availability zone
description.

To see the list of hypervisor names:

.. code-block:: console

   # From host that can reach Openstack
   openstack hypervisor list

To boot an instance on a specific hypervisor

.. code-block:: console

   openstack server create --flavor <Flavour name>--network <Network name> --key-name <key> --image <Image name> --availability-zone nova::<Hypervisor name> <VM name>

Cleanup Procedures
==================

OpenStack services can sometimes fail to remove all resources correctly. This
is the case with Magnum, which fails to clean up users in its domain after
clusters are deleted. `A patch has been submitted to stable branches
<https://review.opendev.org/#/q/Ibadd5b57fe175bb0b100266e2dbcc2e1ea4efcf9>`__.
Until this fix becomes available, if Magnum is in use, administrators can
perform the following cleanup procedure regularly:

.. code-block:: console

   for user in $(openstack user list --domain magnum -f value -c Name | grep -v magnum_trustee_domain_admin); do
      if openstack coe cluster list -c uuid -f value | grep -q $(echo $user | sed 's/_[0-9a-f]*$//'); then
         echo "$user still in use, not deleting"
      else
         openstack user delete --domain magnum $user
      fi
      done

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

   kayobe# kayobe overcloud service reconfigure --kolla-tags opensearch

For more information see the `upstream documentation
<https://docs.openstack.org/kolla-ansible/latest/reference/logging-and-monitoring/central-logging-guide.html#applying-log-retention-policies>`__.
