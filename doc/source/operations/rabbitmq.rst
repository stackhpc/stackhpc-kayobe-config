========
RabbitMQ
========

This guide covers common RabbitMQ operational checks and the response to an
alert caused by an uneven distribution of quorum queue leaders.

Routine checks
==============

Run these commands inside the RabbitMQ container on a controller:

.. code-block:: console

   docker exec rabbitmq rabbitmqctl cluster_status

The cluster should contain every controller in ``Running Nodes`` and have no
network partitions or alarms. See :doc:`shutdown-and-startup` for the full
RabbitMQ checks used when stopping or starting the overcloud.

Quorum queue leader distribution
================================

RabbitMQ quorum queues have a leader, and the leader handles operations for
the queue. Leaders should be spread across the RabbitMQ nodes. The
``RabbitMQConsumersLowUtilization`` alert may be raised when one node is not
the leader for any quorum queues, even when the RabbitMQ cluster itself is
healthy.

Check the number of quorum queue leaders on each node. Run this command on a
controller and replace the node names with the names in your cluster:

.. code-block:: console

   docker exec rabbitmq rabbitmqctl list_queues name type leader | \
       grep 'rabbit@<node-name>' | grep quorum | wc -l

Repeat the command for each RabbitMQ node. A large imbalance, particularly a
node with zero leaders, is the likely cause of the
``RabbitMQConsumersLowUtilization`` alert.

Rebalance the leaders of quorum queues from a controller:

.. code-block:: console

   docker exec rabbitmq rabbitmq-queues rebalance quorum

The command reports the number of quorum queues assigned to each node. Confirm
that the result is reasonably even, then repeat the leader distribution checks
above. The exact counts depend on the number of queues and nodes in the
deployment.

After rebalancing, monitor the alert and check the RabbitMQ logs and service
dashboards. Run a Tempest check to confirm that OpenStack services using
RabbitMQ continue to operate normally.

Missing quorum queue replicas
=============================

Quorum queues should have a member on every RabbitMQ node. To find quorum
queues with fewer members than the cluster has nodes, run the following on a
controller. Replace ``3`` with the number of RabbitMQ nodes in the cluster:

.. code-block:: console

  sudo docker exec rabbitmq rabbitmqctl list_queues name type members --formatter json | \
     jq 'map(select(.type == "quorum") | select((.members // []) | length < 3))'

The output lists the affected queues and their current members. For example,
a queue with only ``rabbit@ctrl0`` as a member is missing replicas on the
other nodes.

An upstream Kolla-Ansible change is intended to add missing quorum queue
members automatically: `review 973110
<https://review.opendev.org/c/openstack/kolla-ansible/+/973110>`__.
Until that change is available in the deployed Kolla-Ansible version, add the
missing members manually. Run the following for each affected queue, replacing
``<queue-name>`` with its name and ``rabbit@ctrl0`` with the node to which the
queue should be added:

.. code-block:: console

  sudo docker exec rabbitmq rabbitmq-queues grow rabbit@ctrl0 <queue-name>

For example, the abbreviated form used when growing all applicable queues is:

.. code-block:: console

  sudo docker exec rabbitmq rabbitmq-queues grow rabbit@ctrl0 all

Re-run the inspection command afterwards and confirm that every quorum queue
has the expected number of members.

Missing stream replicas
=======================

After some upgrades, RabbitMQ streams may not have replicas across all
RabbitMQ nodes. The problem can appear in the logs as:

.. code-block:: text

  Basic.consume: (406) PRECONDITION_FAILED - stream queue 'compute_fanout' in vhost '/' does not have a running replica on the local node

A proper fix is still a work in progress. In the meantime, resolve these
errors using the `RabbitMQ stream replica repair script
<https://gist.github.com/MoteHue/00ba4b85b8e708c46060e025deee8a78>`__.

After running the script, check the RabbitMQ logs and service dashboards to
confirm that the errors have stopped.

Recovery considerations
=======================

* Do not rebalance during a RabbitMQ outage or network partition. Resolve the
  underlying cluster problem first.
* Rebalancing changes queue leadership and can create a short period of extra
  RabbitMQ activity. Perform it during an appropriate maintenance window when
  the deployment is busy.
* If the cluster has missing nodes, partitions, or alarms, follow the relevant
  recovery procedure before attempting to rebalance. The
  ``rabbitmq-reset.yml`` playbook can reset a broken cluster, but it stops and
  restarts OpenStack services and should only be used with an agreed outage
  window.
