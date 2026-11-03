=============================
Deprovisioning a Compute Node
=============================

This procedure removes a compute node from service, drains it, removes all
traces of it from the control plane and Kayobe configuration, and finally
deprovisions the hardware in Bifrost.

Check the Hypervisor
====================

.. code-block:: console

   openstack compute service list --host <node>
   openstack server list --all-projects --host <node>

Put It Into Maintenance Mode
============================

.. code-block:: console

   source ~/<your_kayobe_config_checkout_dir>/src/kayobe-config/etc/kolla/public-openrc.sh
   kayobe playbook run $KAYOBE_CONFIG_PATH/ansible/maintenance/nova-compute-disable.yml --limit <node> -e disabled_reason="decommission <ticket>"

Or use the OpenStack CLI:

.. code-block:: console

   openstack compute service set --disable --disable-reason "decommission <ticket>" <node> nova-compute

Drain the Node
==============

.. code-block:: console

   kayobe playbook run $KAYOBE_CONFIG_PATH/ansible/maintenance/nova-compute-drain.yml --limit <node>

The playbook only handles ``--status ACTIVE``, so clear the rest by hand:

.. code-block:: console

   openstack server list --all-projects --host <node> --status SHUTOFF
   openstack server list --all-projects --host <node> --status PAUSED
   openstack server list --all-projects --host <node> --status ERROR

Cold migrate each one:

.. code-block:: console

   openstack server migrate <id> --wait

Confirm It's Empty
==================

On the to-be-decommissioned node:

.. code-block:: console

   docker exec nova_libvirt virsh list --all

Destroy Containers and Systemd Units
====================================

.. code-block:: console

   sudo systemctl disable --now $(systemctl list-units 'kolla*' --all --plain --no-legend | awk '{print $1}')
   docker stop $(docker ps -aq); docker rm $(docker ps -aq)

Remove It From the Control Plane
================================

.. warning::

   Only now, with nothing running. Delete any of these while its container is
   up and it re-registers, the OVN metadata agent especially
   (``Chassis_Private`` derived).

.. code-block:: console

   openstack compute service delete <service-id>

If present:

.. code-block:: console

   openstack resource provider list --name <node>
   openstack resource provider delete <uuid>

Get the list of network agents:

.. code-block:: console

   openstack network agent list --host <node>
   openstack network agent delete <agent-id>

On a controller, check if the chassis exists and delete it:

.. code-block:: console

   sudo docker exec ovn_sb_db ovn-sbctl --no-leader-only --columns=chassis_name,ip,type list Encap
   sudo docker exec ovn_sb_db ovn-sbctl --no-leader-only chassis-del <node>

Remove It From Kayobe and Monitoring
====================================

Until this runs, Prometheus keeps scraping its exporters, and haproxy/fluentd
keep referencing it.

.. code-block:: console

   grep -rn '<node>' $KAYOBE_CONFIG_PATH/

Remove it from ``etc/kayobe/inventory/overcloud`` and any group vars, then:

.. code-block:: console

   kayobe overcloud service reconfigure --kolla-limit controllers,monitoring

Deprovision the Hardware
========================

From the seed.

.. code-block:: console

   sudo docker exec -it bifrost_deploy bash -c 'export OS_CLOUD=bifrost; openstack baremetal node undeploy <node>'

.. code-block:: console

   sudo docker exec -it bifrost_deploy bash -c 'export OS_CLOUD=bifrost; openstack baremetal node delete <node>'

.. code-block:: console

   kayobe overcloud inventory discover

Verification
============

.. code-block:: console

   sudo docker exec rabbitmq rabbitmqctl list_connections --silent peer_host | sort -u
   sudo docker exec ovn_sb_db ovn-sbctl --no-leader-only --columns=chassis_name,ip,type list Encap
   openstack compute service list
   openstack network agent list
