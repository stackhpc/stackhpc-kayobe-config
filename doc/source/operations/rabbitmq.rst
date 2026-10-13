========
RabbitMQ
========

This guide covers common RabbitMQ operational checks and the response to an
alert caused by an uneven distribution of quorum queue leaders.

The commands in this guide are run on a host in the RabbitMQ cluster. This is
usually a controller, but some deployments run RabbitMQ on dedicated hosts by
customising the ``rabbitmq`` group in the Kolla-Ansible inventory. Where this
guide refers to RabbitMQ nodes, it means the hosts in that group.

Routine checks
==============

Run this command on a RabbitMQ node:

.. code-block:: console

   docker exec rabbitmq rabbitmqctl cluster_status

The cluster should contain every RabbitMQ node in ``Running Nodes`` and have no
network partitions or alarms. See :doc:`shutdown-and-startup` for the full
RabbitMQ checks used when stopping or starting the overcloud.

Management interface
--------------------

Kolla-Ansible enables the RabbitMQ management plugin. The management web
interface is available on the internal network at
``http://<kolla_internal_fqdn>:15672``, and on port ``15672`` of the internal
API address of each RabbitMQ node. Log in with the ``openstack`` user and the
``rabbitmq_password`` from ``etc/kayobe/kolla/passwords.yml``.

The interface gives an overview of cluster health, and shows connections,
channels and queues, including the leader and members of each quorum queue.
It is useful for investigating problems, but prefer the CLI commands in this
guide when making changes.

Quorum queue leader distribution
================================

RabbitMQ quorum queues have a leader, and the leader handles operations for
the queue. Leaders should be spread across the RabbitMQ nodes. The
``RabbitMQConsumersLowUtilization`` alert may be raised when one node is not
the leader for any quorum queues, even when the RabbitMQ cluster itself is
healthy.

Check the number of quorum queue leaders on each node. Run this command on a
RabbitMQ node and replace ``<node-name>`` with the name of each node in your
cluster:

.. code-block:: console

   docker exec rabbitmq rabbitmqctl list_queues name type leader | \
       grep 'rabbit@<node-name>' | grep quorum | wc -l

Repeat the command for each RabbitMQ node. A large imbalance, particularly a
node with zero leaders, is the likely cause of the
``RabbitMQConsumersLowUtilization`` alert.

Rebalance the leaders of quorum queues from a RabbitMQ node:

.. code-block:: console

   docker exec rabbitmq rabbitmq-queues rebalance quorum

The command reports the number of quorum queues assigned to each node. Confirm
that the result is reasonably even, then repeat the leader distribution checks
above. The exact counts depend on the number of queues and nodes in the
deployment.

After rebalancing, monitor the alert and check the RabbitMQ logs and service
dashboards. Run Tempest, as described in :doc:`tempest`, to confirm that
OpenStack services using RabbitMQ continue to operate normally.

Missing quorum queue replicas
=============================

Each quorum queue has a target number of members. Unless it is overridden by
the ``x-quorum-initial-group-size`` queue argument or a policy, RabbitMQ
places a member on up to three RabbitMQ nodes when the queue is declared. In
the common case of a three node RabbitMQ cluster, every quorum queue should
therefore have a member on every node.

OpenStack services use the ``/`` virtual host by default. To find quorum queues
in that virtual host with fewer members than expected, run the following on a
RabbitMQ node. Replace ``3`` with the expected number of members:

.. code-block:: console

   sudo docker exec rabbitmq rabbitmqctl list_queues -p / name type members --formatter json | \
       jq 'map(select(.type == "quorum") | select((.members // []) | length < 3))'

The output lists the affected queues and their current members. For example,
in a three node cluster, a queue with only ``rabbit@ctrl0`` as a member is
missing replicas on the other nodes.

An upstream Kolla-Ansible change is intended to add missing quorum queue
members automatically, by enabling RabbitMQ's continuous membership
reconciliation: `review 973110
<https://review.opendev.org/c/openstack/kolla-ansible/+/973110>`__.
Continuous membership reconciliation only grows queues up to their target
group size, so it will not add members beyond the expected number. Until that
change is available in the deployed Kolla-Ansible version, add the missing
members manually.

To add a member to a single queue, replace ``<queue-name>`` with its name and
``rabbit@ctrl0`` with the node on which the new member should be placed:

.. code-block:: console

   sudo docker exec rabbitmq rabbitmq-queues add_member --vhost / <queue-name> rabbit@ctrl0

Alternatively, add a member on a node to every quorum queue in the virtual
host that does not already have one there:

.. code-block:: console

   sudo docker exec rabbitmq rabbitmq-queues grow rabbit@ctrl0 all --vhost-pattern '^/$'

Only use the bulk ``grow`` command when every quorum queue is expected to have
a member on every node, as in a three node cluster with the default group
size. In larger clusters, it adds members beyond the target group size, so add
members to the affected queues individually instead.

Re-run the inspection command afterwards and confirm that every quorum queue
has the expected number of members.

Missing stream replicas
=======================

After some upgrades, RabbitMQ streams may not have replicas across all
RabbitMQ nodes. The problem can appear in the logs as:

.. code-block:: text

   Basic.consume: (406) PRECONDITION_FAILED - stream queue 'compute_fanout' in vhost '/' does not have a running replica on the local node

OpenStack services consume fanout streams from every RabbitMQ node, so each
stream needs a replica on every node that clients connect to. A proper fix is
still a work in progress. In the meantime, resolve these errors using the
`RabbitMQ stream replica repair script
<https://github.com/openstack/kolla-ansible/blob/master/contrib/ops/rabbitmq/rabbitmq-repair-stream-replicas.sh>`__.
Run it on a RabbitMQ node. It adds a replica of each stream on every running
RabbitMQ node that does not already have one.

After running the script, check the RabbitMQ logs and service dashboards to
confirm that the errors have stopped.

Recovery considerations
=======================

* Do not rebalance or add replicas during a RabbitMQ outage or network
  partition. Resolve the underlying cluster problem first.
* Rebalancing changes queue leadership and can create a short period of extra
  RabbitMQ activity. Perform it during an appropriate maintenance window when
  the deployment is quiet.
* If the cluster has missing nodes, partitions, or alarms that do not clear,
  reset the cluster before attempting to rebalance. Use the
  ``rabbitmq-reset.yml`` playbook:

  .. code-block:: console

     kayobe playbook run $KAYOBE_CONFIG_PATH/ansible/fixes/rabbitmq-reset.yml

  The playbook stops the OpenStack services that use RabbitMQ, resets
  RabbitMQ on each RabbitMQ node, and then restarts those services. It causes
  an outage of the OpenStack APIs and should only be used with an agreed
  outage window. By default, it resets RabbitMQ on the ``controllers`` group
  and restarts services on the ``controllers``, ``compute`` and ``storage``
  groups. If RabbitMQ runs on different hosts, set ``rabbitmq_reset_hosts``,
  and set ``rabbitmq_reset_service_hosts`` to match the hosts running
  OpenStack services, for example:

  .. code-block:: console

     kayobe playbook run $KAYOBE_CONFIG_PATH/ansible/fixes/rabbitmq-reset.yml \
         -e rabbitmq_reset_hosts=rabbitmq-nodes
