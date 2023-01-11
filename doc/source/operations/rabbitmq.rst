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
If you are currently running Wallaby, you will need to enable the HA config option in
``etc/kayobe/kolla/globals.yml``.

.. code-block:: console

  om_enable_rabbitmq_high_availability: true

If you are running Wallaby or Xena, synchronise the Pulp containers.

.. code-block:: console

  kayobe playbook run etc/kayobe/ansible/pulp-container-sync.yml pulp-container-publish.yml -e stackhpc_pulp_images_kolla_filter=rabbitmq

Generate the new config files for the overcloud services.

.. code-block:: console

  kayobe overcloud service configuration generate

Pull the RabbitMQ container image.

.. code-block:: console

  kayobe overcloud container image pull -kt rabbitmq

Stop all the OpenStack services which use RabbitMQ.

.. code-block:: console

  kayobe overcloud host command run --command "docker ps -a | egrep '(barbican|blazar|ceilometer|cinder|cloudkitty|designate|heat|ironic|keystone|magnum|manila|masakari|neutron|nova|octavia)' | awk '{ print $NF }' | xargs docker stop"

Upgrade RabbitMQ.

.. code-block:: console

  kayobe overcloud service upgrade -kt rabbitmq --skip-prechecks

In order to convert the queues to be durable, you will need to reset the state
of RabbitMQ, and restart the services which use it. This can be done with the
RabbitMQ hammer playbook:

.. code-block:: console

  kayobe playbook run stackhpc-kayobe-config/etc/kayobe/ansible/rabbitmq-reset.yml

The hammer playbook only targets the services which are known to have issues
when RabbitMQ breaks. You will still need to start the remaining services:

.. code-block:: console

  kayobe overcloud host command run --command "docker ps -a | egrep '(barbican|blazar|ceilometer|cloudkitty|designate|manila|masakari|octavia)' | awk '{ print $NF }' | xargs docker start"

Check to see if RabbitMQ is functioning as expected.

.. code-block:: console

  kayobe overcloud host command run --show-output --command 'docker exec rabbitmq rabbitmqctl cluster_status'
  kayobe overcloud host command run --show-output --command 'docker exec rabbitmq rabbitmqctl list_queues name durable'

The cluster status should list all controllers. The queues listed should be
durable if their names do not start with the following:

* amq.
* .\*\_fanout\_
* reply\_

If there are issues with the services after this, particularly during upgrades,
you may find it useful to reuse the hammer playbook.
