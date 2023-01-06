Rolling out changes to RabbitMQ
================================

Prior to upgrading, some changes need to be rolled out for RabbitMQ.
This should make RabbitMQ more stable during the upgrade(s). These changes
are:

* Enable the high availability setting via Kolla-Ansible
  ``om_enable_rabbitmq_high_availability``.
* Update RabbitMQ to version 3.9.22

**NOTE:** There is guaranteed to be downtime during this procedure, as it
requires restarting RabbitMQ and all the OpenStack services that use it. The
state of RabbitMQ may also need to be reset.

Instructions
------------

If you are upgrading from Wallaby to Xena, you will need to enable the HA
config option in
``/home/ubuntu/kayobe/config/src/kolla-ansible/ansible/group_vars/all.yml``.
This will default to ``true`` from Xena onwards.

``om_enable_rabbitmq_high_availability: true``

Synchronise the Pulp containers.

``kayobe playbook run etc/kayobe/ansible/pulp-container-sync.yml pulp-container-publish.yml -e stackhpc_pulp_images_kolla_filter=rabbitmq``

Generate the new config files for the overcloud services.

``kayobe overcloud servuce configuration generate``

Pull the RabbitMQ container image.

``kayobe overcloud container image pull -kt rabbitmq``

Stop all the OpenStack services which use RabbitMQ.

``kayobe overcloud host command run --command 'docker ps -a | egrep '(barbican|blazar|ceilometer|cinder|cloudkitty|designate|heat|ironic|keystone|magnum|manila|masakari|neutron|nova|octavia)' | awk '{ print $NF }' | xargs docker stop'``

Upgrade RabbitMQ.

``kayobe overcloud service upgrade -kt rabbitmq --skip-prechecks``

Check to see if RabbitMQ is functioning as expected.

``kayobe overcloud service upgrade -kt rabbitmq --skip-prechecks``

``kayobe overcloud host command run --command 'docker exec rabbitmq rabbitmqctl cluster_status'``

``kayobe overcloud host command run --command 'docker exec rabbitmq rabbitmqctl list_queues name durable'``

The cluster status should list all controllers. The queues listed should be
durable if their names do not start with the following:

* amq.
* .\*\_fanout\_
* reply\_

At this stage, you may find that the above is not correct. If this is the case,
running the rabbitmq hammer playbook will reset the state of the RabbitMQ
nodes, and then bring the services which use RabbitMQ back up.

``kayobe playbook run stackhpc-kayobe-config/etc/kayobe/ansible/rabbitmq-reset.yml``

If you do not need to use the playbook here, then you will need to bring the
services back up yourself:

``kayobe overcloud host command run --command 'docker ps -a | egrep '(barbican|blazar|ceilometer|cinder|cloudkitty|designate|heat|ironic|keystone|magnum|manila|masakari|neutron|nova|octavia)' | awk '{ print $NF }' | xargs docker start'``

If there are issues with the services after this, you may still need to run the
hammer playbook.
