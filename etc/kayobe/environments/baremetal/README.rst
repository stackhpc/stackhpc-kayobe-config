StackHPC Ironic environment
~~~~~~~~~~~~~~~~~~~~~~~~~~~

Mixin that adds StackHPC opinionated defaults for Ironic.

Consuming this environment
^^^^^^^^^^^^^^^^^^^^^^^^^^

Add the ``baremetal`` environment to your  ``.kayobe-environment`` file:

.. code-block:: yaml
   :caption: $KAYOBE_CONFIG_PATH/environments/$KAYOBE_ENVIRONMENT/.kayobe-environment

   dependencies:
     - baremetal

Redeploy the loadbalancer, Neutron, Nova, and Ironic:

.. code-block:: console

   kayobe overcloud service deploy -kt loadbalancer,ironic,nova,neutron

Cleaning
^^^^^^^^

Storage
"""""""

Hardware assisted secure erase, i.e the ``erase_devices`` clean step, is
enabled by default. This is normally dependent on the `Hardware Manager
<https://docs.openstack.org/ironic-python-agent/latest/contributor/hardware_managers.html>`__
in use. For example, when using the GenericHardwareManager the priority would
be 10, whereas if using the `ProliantHardwareManager
<https://docs.openstack.org/ironic/latest/admin/drivers/ilo.html#disk-erase-support>`__
it would be 0. The idea is that we will prevent the catastrophic case where
data could be leaked to another tenant; forcing you to have to explicitly relax
this setting if this is a risk you want to take. This can be customised by
editing the following variables:

.. code-block:: yaml
    :caption: $KAYOBE_CONFIG_PATH/environments/$KAYOBE_ENVIRONMENT/kolla/config/ironic.conf

    [deploy]
    erase_devices_priority=10
    erase_devices_metadata_priority=0

See `Ironic documentation
<https://docs.openstack.org/ironic/latest/admin/cleaning.html>`__ for more
details.

Baremetal workflow
^^^^^^^^^^^^^^^^^^

Idempotent playbooks to enroll, inspect and clean baremetal nodes in Ironic.

Inventory
"""""""""

Add nodes to the consuming environment's inventory. All are members of
``baremetal-compute``. Choose the group by role and driver:

* ``baremetal-compute-<driver>``: provided to tenants as Nova instances
* ``baremetal-overcloud-<driver>``: deployed as overcloud hosts (e.g.
  controllers or hypervisors) by ``provision-nova.yml``

where ``<driver>`` is ``redfish`` (preferred), ``idrac`` or ``ipmi``. The
workflow playbooks only support Redfish, so add Dell nodes to the ``redfish``
groups rather than ``idrac`` to use them.

Redfish nodes boot using virtual media by default. To use iPXE, set
``ironic_boot_interface: ipxe`` for those nodes, and set
``inspector_enable_discovery: true``, since iPXE inspection needs discovery
DHCP rather than Ironic-managed boot.

.. code-block:: ini
   :caption: $KAYOBE_CONFIG_PATH/environments/$KAYOBE_ENVIRONMENT/inventory/hosts

   [baremetal-compute-redfish]
   gpu-01 redfish_address=10.0.0.11

   [baremetal-overcloud-redfish]
   ctl-01 redfish_address=10.0.0.21

Set ``ironic_resource_class`` and the BMC credentials
(``inspector_redfish_username``/``inspector_redfish_password``, or
``ironic_username``/``ironic_password``). Other defaults are in
``inventory/group_vars/baremetal-compute/ironic.yml``, and mirror
https://review.opendev.org/c/openstack/kayobe/+/952979, which has not merged
yet. For virtual media, the controllers need an address on the OOB network
(``oob_oc_net_name``).

Enrollment
""""""""""

.. code-block:: console

   kayobe baremetal compute register
   kayobe playbook run $KAYOBE_CONFIG_PATH/environments/baremetal/ansible/baremetal-update.yml

``baremetal-update.yml`` applies the interfaces from group_vars, which Kayobe
2026.1 does not set at registration.

Inspection and cleaning
"""""""""""""""""""""""

.. code-block:: console

   kayobe playbook run $KAYOBE_CONFIG_PATH/environments/baremetal/ansible/baremetal-all.yml

Stages, each skipped once recorded in the node's ``extra`` field:

1. Check BMC is up, move to ``manageable`` and set the resource class to
   ``<ironic_resource_class>_enroll`` (``kayobe_bmc_up``)
2. Redfish inspection (``kayobe_redfish_inspect_done``)
3. Agent inspection, to collect LLDP (``kayobe_agent_inspect_done``)
4. Clean and move to ``available`` (``kayobe_clean_done``)
5. Release for scheduling by setting ``ironic_resource_class``
   (``kayobe_released``)

Run ``baremetal-clear-prev-inspection.yml`` to repeat inspection.
