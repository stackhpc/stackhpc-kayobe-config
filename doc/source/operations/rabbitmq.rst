========
RabbitMQ
========

High Availability
=================

In order to improve the stability of RabbitMQ, some changes need to be rolled,
out. These changes are:

* Update RabbitMQ to version 3.9.22, if you are running old images on Wallaby
  or Xena, by synchronising and then pulling a new RabbitMQ container from
  Pulp.
* Enable the high availability setting via Kolla-Ansible
  ``om_enable_rabbitmq_high_availability``.

By default in Kolla-Ansible, two key options for the high availability of
RabbitMQ are disabled. These are durable queues, where messages are persisted
to disk; and classic queue mirroring, where messages are replicated across
multiple exchanges. Without these, a deployment has a higher risk of experiencing
issues when updating RabbitMQ, or recovering from network outages.
Messages held in RabbitMQ nodes that are stopped will be lost, which causes
knock-on effects to the OpenStack services which either sent or were expecting
to receive them. The Kolla-Ansible flag
``om_enable_rabbitmq_high_availability`` can be used to enable both of these
options. The default will be overridden to ``true`` from Xena onwards in StackHPC Kayobe configuration.

While the `RabbitMQ docs <https://www.rabbitmq.com/queues.html#durability>`_ do
say "throughput and latency of a queue is not affected by whether a queue is
durable or not in most cases", it should be mentioned that there could be a
potential performance hit from replicating all messages to the disk within
large deployments. These changes would therefore be a tradeoff of performance
for stability.

**NOTE:** There is guaranteed to be downtime during this procedure, as it
requires restarting RabbitMQ and all the OpenStack services that use it. The
state of RabbitMQ will also be reset.

Instructions
------------
If you are planning to perform an upgrade, it is recommended to first roll out these changes.

The configuration should be merged with StackHPC Kayobe configuration. If
bringing in the latest changes is not possible for some reason, you may cherry
pick the following changes:

RabbitMQ hammer playbook (all releases):

* ``3933e4520ba512b5bf095a28b791c0bac12c5dd0``
* ``d83cceb2c41c18c2406032dac36cf90e57f37107``
* ``097c98565dd6bd0eb16d49b87e4da7e2f2be3a5c``

RabbitMQ tags (Wallaby):

* ``69c245dc91a2eb4d34590624760c32064c3ac07b``

RabbitMQ tags & HA flag (Xena):

* ``2fd1590eb8ac739a07ad9cccbefc7725ea1a3855``

RabbitMQ HA flag (Yoga):

* ``31406648544372187352e129d2a3b4f48498267c``

If you are currently running Wallaby, you will need to enable the HA config option in
``etc/kayobe/kolla/globals.yml``.

.. code-block:: console

  om_enable_rabbitmq_high_availability: true

If you are running Wallaby or Xena, synchronise the Pulp containers.

.. code-block:: console

  kayobe playbook run $KAYOBE_CONFIG_PATH/ansible/pulp-container-sync.yml $KAYOBE_CONFIG_PATH/ansible/pulp-container-publish.yml -e stackhpc_pulp_images_kolla_filter=rabbitmq

Ensure that Kolla Ansible is up to date.

.. code-block:: console

   kayobe control host bootstrap

Generate the new config files for the overcloud services. This ensures that
queues are created as durable.

.. code-block:: console

  kayobe overcloud service configuration generate --node-config-dir /etc/kolla

Pull the RabbitMQ container image.

.. code-block:: console

  kayobe overcloud container image pull -kt rabbitmq

Stop all the OpenStack services which use RabbitMQ.

.. code-block:: console

  kayobe overcloud host command run -b --command "systemctl -a | egrep '(barbican|blazar|ceilometer|cinder|cloudkitty|designate|heat|ironic|keystone|magnum|manila|masakari|neutron|nova|octavia)' | awk '{ print \$1 }' | xargs systemctl stop"

Upgrade RabbitMQ.

.. code-block:: console

  kayobe overcloud service upgrade -kt rabbitmq --skip-prechecks

In order to convert the queues to be durable, you will need to reset the state
of RabbitMQ. This can be done with the RabbitMQ hammer playbook:

.. code-block:: console

  kayobe playbook run $KAYOBE_CONFIG_PATH/ansible/rabbitmq-reset.yml --skip-tags restart-openstack

Check to see if RabbitMQ is functioning as expected.

.. code-block:: console

  kayobe overcloud host command run --limit controllers --show-output --command 'docker exec rabbitmq rabbitmqctl cluster_status'

The cluster status should list all controllers.

Check to see if all OpenStack queues and exchanges have been removed from the RabbitMQ cluster.

.. code-block:: console

  kayobe overcloud host command run --limit controllers --show-output --command 'docker exec rabbitmq rabbitmqctl list_queues name'
  kayobe overcloud host command run --limit controllers --show-output --command 'docker exec rabbitmq rabbitmqctl list_exchanges name'

There should be no queues listed, and the only exchanges listed should start with `amq.`.

Start the OpenStack services which use RabbitMQ. Note that this will start all
matching services, even if they weren't running prior to starting this
procedure.

.. code-block:: console

  kayobe overcloud host command run -b --command "systemctl -a | egrep '(barbican|blazar|ceilometer|cinder|cloudkitty|designate|heat|ironic|keystone|magnum|manila|masakari|neutron|nova|octavia)' | awk '{ print \$1 }' | xargs systemctl start"

Check to see if the expected queues are durable.

.. code-block:: console

  kayobe overcloud host command run --limit controllers --show-output --command 'docker exec rabbitmq rabbitmqctl list_queues name durable'

The queues listed should be durable if their names do not start with the
following:

* amq.
* .\*\_fanout\_
* reply\_

If there are issues with the services after this, particularly during upgrades,
you may find it useful to reuse the hammer playbook, ``rabbitmq-reset.yml``.

Known issues
------------

If there are any OpenStack services running without durable queues enabled
while the RabbitMQ cluster is reset, they are likely to create non-durable
queues before the other OpenStack services start. This leads to an error
such as the following when other OpenStack services start::

    Unable to connect to AMQP server on <IP>:5672 after inf tries:
    Exchange.declare: (406) PRECONDITION_FAILED - inequivalent arg 'durable'
    for exchange 'neutron' in vhost '/': received 'true' but current is
    'false': amqp.exceptions.PreconditionFailed: Exchange.declare: (406)
    PRECONDITION_FAILED - inequivalent arg 'durable' for exchange 'neutron' in
    vhost '/': received 'true' but current is 'false'

This may happen if a host is not in the inventory, leading to them not being
targeted by the ``systemctl stop`` command. If this does happen, look for the
hostname of the offending node in the queues created after the RabbitMQ reset.

Once the rogue services have been stopped, reset the RabbitMQ cluster again to
clear the queues.
