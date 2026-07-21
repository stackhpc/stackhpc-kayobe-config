====================
Shutdown and startup
====================

Use this procedure for a planned shutdown of the whole cloud. Complete the
sections in order. Skip components that are not present.

Some deployments use the Ansible control host as the seed hypervisor. In this
case, shut it down once, as the final step.

Shutdown
========

.. _shutdown-pre-flight:

Pre-flight
----------

Get the MariaDB password on the Ansible control host:

.. code-block:: console

   ansible-vault view $KAYOBE_CONFIG_PATH/kolla/passwords.yml \
       --vault-password-file <vault password file> | \
       grep '^database_password:'

Log in to each controller:

.. code-block:: console

   ssh stack@<controller>

Run the following checks on every controller.

Galera
++++++

Enter the MariaDB password when prompted:

.. code-block:: console

   docker exec -i mariadb mysql -u root -p \
       -e "SHOW STATUS LIKE 'wsrep_local_state_comment'"

The result must be ``Synced``:

.. code-block:: text

   wsrep_local_state_comment  Synced

RabbitMQ
++++++++

.. code-block:: console

   docker exec rabbitmq rabbitmqctl cluster_status

Check the output:

* ``Running Nodes`` lists every controller.
* ``Network Partitions`` is ``(none)``.
* ``Alarms`` is ``(none)``.

Keepalived
++++++++++

.. code-block:: console

   docker logs keepalived 2>&1 | \
       grep -E 'Entering (MASTER|BACKUP) STATE' | tail -1

One controller must show ``Entering MASTER STATE``. The other controllers
must show ``Entering BACKUP STATE``.

Do not continue until all checks pass.

MariaDB backup
++++++++++++++

Run on the Ansible control host:

.. code-block:: console

   kayobe overcloud database backup

Check that the command succeeds. See :doc:`database-backups` for off-host
backups.

Instances
---------

Workload instances
++++++++++++++++++

Ask users to stop their instances.

Ironic compute instances
++++++++++++++++++++++++

.. warning::

   If compute nodes are deployed as Ironic instances, stop all workload
   instances before stopping the compute node instances.

Stop each Ironic compute instance:

.. code-block:: console

   openstack server stop <compute node instance>

Remaining instances
+++++++++++++++++++

Stop any remaining active instances:

.. code-block:: console

   for server in $(openstack server list --all-projects --status ACTIVE \
       -f value -c ID); do
       openstack server stop "$server"
   done

Wait until this command returns no instances:

.. code-block:: console

   openstack server list --all-projects --status ACTIVE

Investigate any failures.

Bifrost
-------

On the seed VM, put every managed node into maintenance:

.. code-block:: console

   docker exec bifrost_deploy bash -c '
   for node in $(baremetal --os-cloud bifrost node list -f value -c UUID); do
       baremetal --os-cloud bifrost node maintenance set \
           --reason full-shutdown "$node"
   done'

OpenStack services
------------------

Run on the Ansible control host:

.. code-block:: console

   kayobe overcloud service stop --yes-i-really-really-mean-it

This stops all Kolla containers, including monitoring. The containers start
when their hosts boot.

Compute nodes
-------------

Bifrost-managed compute nodes
+++++++++++++++++++++++++++++

On the seed VM, shut down each compute node:

.. code-block:: console

   docker exec bifrost_deploy baremetal --os-cloud bifrost \
       node power off --soft <compute node>

Wait for each node to reach ``power off``.

Monitoring nodes
----------------

On the seed VM, shut down each monitoring node:

.. code-block:: console

   docker exec bifrost_deploy baremetal --os-cloud bifrost \
       node power off --soft <monitoring node>

Wait for each node to reach ``power off``.

Network nodes
-------------

On the seed VM, shut down each network node:

.. code-block:: console

   docker exec bifrost_deploy baremetal --os-cloud bifrost \
       node power off --soft <network node>

Wait for each node to reach ``power off``.

Controllers
-----------

On the seed VM, shut down each controller:

.. code-block:: console

   docker exec bifrost_deploy baremetal --os-cloud bifrost \
       node power off --soft <controller>

Wait for each node to reach ``power off``.

Ceph
----

.. warning::

   Stop all external Ceph client I/O before continuing. Unmount CephFS,
   disconnect RBD clients, and stop traffic to RGW/S3 and other Ceph gateways.

On a MON node, check that Ceph reports ``HEALTH_OK`` and all placement groups
are ``active+clean``, then set ``noout``:

.. code-block:: console

   sudo cephadm shell -- ceph -s
   sudo cephadm shell -- ceph osd set noout

On the seed VM, shut down Ceph nodes:

.. code-block:: console

   docker exec bifrost_deploy baremetal --os-cloud bifrost \
       node power off --soft <Ceph node>

Shut down nodes running MON services last. Wait for each node to reach
``power off``.

Seed VM
-------

If the seed is a VM on the seed hypervisor, run:

.. code-block:: console

   virsh shutdown <seed VM>

Wait for the VM to stop. If the seed is hosted elsewhere, shut it down using
the platform that hosts it.

Seed hypervisor
---------------

Run on the separate seed hypervisor:

.. code-block:: console

   sudo systemctl poweroff

Ansible control host
--------------------

Shut down the Ansible control host last:

.. code-block:: console

   sudo systemctl poweroff

Startup
=======

Ansible control host
--------------------

Power on the Ansible control host.

Seed hypervisor and seed VM
---------------------------

If the seed is a VM on the seed hypervisor, power on the hypervisor if it is
separate from the Ansible control host, then start the seed VM:

.. code-block:: console

   virsh start <seed VM>

If the seed is hosted elsewhere, start it using the platform that hosts it.

Bifrost
-------

On the seed VM, wait for the ``bifrost_deploy`` container to be running.

Ceph
----

On the seed VM, start Ceph MON nodes, then the other Ceph nodes:

.. code-block:: console

   docker exec bifrost_deploy baremetal --os-cloud bifrost \
       node power on <Ceph node>

On a MON node, wait for all OSDs and placement groups. Continue when Ceph
reports ``HEALTH_OK`` and all Ceph services are running, then unset ``noout``:

.. code-block:: console

   sudo cephadm shell -- ceph orch ls
   sudo cephadm shell -- ceph -s
   sudo cephadm shell -- ceph osd unset noout

External Ceph clients can now be started.

Controllers and MariaDB
-----------------------

On the seed VM, start every controller:

.. code-block:: console

   docker exec bifrost_deploy baremetal --os-cloud bifrost \
       node power on <controller>

When all controllers are reachable, recover MariaDB from the Ansible control
host:

.. code-block:: console

   kayobe overcloud database recover

Network nodes
-------------

On the seed VM, start every network node:

.. code-block:: console

   docker exec bifrost_deploy baremetal --os-cloud bifrost \
       node power on <network node>

Monitoring nodes
----------------

On the seed VM, start every monitoring node:

.. code-block:: console

   docker exec bifrost_deploy baremetal --os-cloud bifrost \
       node power on <monitoring node>

Compute nodes
-------------

Bifrost-managed compute nodes
+++++++++++++++++++++++++++++

On the seed VM, start every compute node:

.. code-block:: console

   docker exec bifrost_deploy baremetal --os-cloud bifrost \
       node power on <compute node>

Ironic compute instances
++++++++++++++++++++++++

.. warning::

   If compute nodes are deployed as Ironic instances, start the compute node
   instances before starting workload instances.

Start the compute node instances:

.. code-block:: console

   openstack server start <compute node instance>

Wait for their Nova compute services to report ``enabled`` and ``up``:

.. code-block:: console

   openstack compute service list --service nova-compute

OpenStack services
------------------

Repeat the Galera, RabbitMQ and Keepalived checks from
:ref:`shutdown-pre-flight`.

List containers that are not running:

.. code-block:: console

   kayobe overcloud host command run --show-output --command \
       "docker ps --all --filter status=exited --filter status=dead \
       --filter status=restarting --format '{{.Names}}: {{.Status}}'"

No containers should be listed. For a listed container, check its output and
the service logs under ``/var/log/kolla/``, then restart its systemd unit:

.. code-block:: console

   docker logs <container>
   sudo systemctl restart kolla-<container>-container

Bifrost maintenance
-------------------

On the seed VM, remove a healthy node from maintenance:

.. code-block:: console

   docker exec bifrost_deploy baremetal --os-cloud bifrost \
       node maintenance unset <node>

Verification
------------

Wait for the shutdown alerts to clear in Alertmanager. Investigate any
remaining alerts and new errors in OpenSearch Dashboards.

Workload instances
------------------

Workload instances can now be started.
