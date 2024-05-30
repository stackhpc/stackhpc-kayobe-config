======================================
Bare Metal Compute Hardware Management
======================================

Bare metal compute nodes are managed by the Ironic services.
This section describes elements of the configuration of this service.

.. _ironic-node-lifecycle:

Ironic node life cycle
----------------------

The deployment process is documented in the `Ironic User Guide <https://docs.openstack.org/ironic/latest/user/index.html>`__.
OpenStack deployment uses the
`direct deploy method <https://docs.openstack.org/ironic/latest/user/index.html#example-1-pxe-boot-and-direct-deploy-process>`__.

The Ironic state machine can be found `here <https://docs.openstack.org/ironic/latest/user/states.html>`__. The rest of
this documentation refers to these states and assumes that you have familiarity.

High level overview of state transitions
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

The following section attempts to describe the state transitions for various Ironic operations at a high level.
It focuses on trying to describe the steps where dynamic switch reconfiguration is triggered.
For a more detailed overview, refer to the :ref:`ironic-node-lifecycle` section.

Provisioning
~~~~~~~~~~~~

Provisioning starts when an instance is created in Nova using a bare metal flavor.

- Node starts in the available state (available)
- User provisions an instance (deploying)
- Ironic will switch the node onto the provisioning network (deploying)
- Ironic will power on the node and will await a callback (wait-callback)
- Ironic will image the node with an operating system using the image provided at creation (deploying)
- Ironic switches the node onto the tenant network(s) via neutron (deploying)
- Transition node to active state (active)

.. _baremetal-management-deprovisioning:

Deprovisioning
~~~~~~~~~~~~~~

Deprovisioning starts when an instance created in Nova using a bare metal flavor is destroyed.

If automated cleaning is enabled, it occurs when nodes are deprovisioned.

- Node starts in active state (active)
- User deletes instance (deleting)
- Ironic will remove the node from any tenant network(s) (deleting)
- Ironic will switch the node onto the cleaning network (deleting)
- Ironic will power on the node and will await a callback (clean-wait)
- Node boots into Ironic Python Agent and issues callback, Ironic starts cleaning (cleaning)
- Ironic removes node from cleaning network (cleaning)
- Node transitions to available (available)

If automated cleaning is disabled.

- Node starts in active state (active)
- User deletes instance (deleting)
- Ironic will remove the node from any tenant network(s) (deleting)
- Node transitions to available (available)

Cleaning
~~~~~~~~

Manual cleaning is not part of the regular state transitions when using Nova, however nodes can be manually cleaned by administrators.

- Node starts in the manageable state (manageable)
- User triggers cleaning with API (cleaning)
- Ironic will switch the node onto the cleaning network (cleaning)
- Ironic will power on the node and will await a callback (clean-wait)
- Node boots into Ironic Python Agent and issues callback, Ironic starts cleaning (cleaning)
- Ironic removes node from cleaning network (cleaning)
- Node transitions back to the manageable state (manageable)

Rescuing
~~~~~~~~

Feature not used. The required rescue network is not currently configured.

Baremetal networking
--------------------

Baremetal networking with the Neutron Networking Generic Switch ML2 driver requires a combination of static and dynamic switch configuration.

.. _static-switch-config:

Static switch configuration
~~~~~~~~~~~~~~~~~~~~~~~~~~~

Static physical network configuration is managed via Kayobe.

.. TODO: Fill in the switch configuration

- Some initial switch configuration is required before networking generic switch can take over the management of an interface.
    First, LACP must be configured on the switch ports attached to the baremetal node, e.g:

    .. code-block:: shell

      The interface is then partially configured:

    .. code-block:: shell

      For :ref:`ironic-node-discovery` to work, you need to manually switch the port to the provisioning network:

    **NOTE**: You only need to do this if Ironic isn't aware of the node.

Configuration with kayobe
^^^^^^^^^^^^^^^^^^^^^^^^^

Kayobe can be used to apply the :ref:`static-switch-config`.

- Upstream documentation can be found `here <https://docs.openstack.org/kayobe/latest/configuration/reference/physical-network.html>`__.
- Kayobe does all the switch configuration that isn't :ref:`dynamically updated using Ironic <dynamic-switch-configuration>`.
- Optionally switches the node onto the provisioning network (when using ``--enable-discovery``)

    + NOTE: This is a dangerous operation as it can wipe out the dynamic VLAN configuration applied by neutron/ironic.
      You should only run this when initially enrolling a node, and should always use the ``interface-description-limit`` option. For example:

    .. code-block::

        kayobe physical network configure --interface-description-limit <description> --group switches --display --enable-discovery

    In this example, ``--display`` is used to preview the switch configuration without applying it.

.. TODO: Fill in information about how switches are configured in kayobe-config, with links

- Configuration is done using a combination of ``group_vars`` and ``host_vars``

.. _dynamic-switch-configuration:

Dynamic switch configuration
~~~~~~~~~~~~~~~~~~~~~~~~~~~~

Ironic dynamically configures the switches using the Neutron `Networking Generic Switch <https://docs.openstack.org/networking-generic-switch/latest/>`_ ML2 driver.

- Used to toggle the baremetal nodes onto different networks

  + Can use any VLAN network defined in OpenStack, providing that the VLAN has been trunked to the controllers
    as this is required for DHCP to function.
  + See :ref:`ironic-node-lifecycle`. This attempts to illustrate when any switch reconfigurations happen.

- Only configures VLAN membership of the switch interfaces or port groups. To prevent conflicts with the static switch configuration,
  the convention used is: after the node is in service in Ironic, VLAN membership should not be manually adjusted and
  should be left to be controlled by ironic i.e *don't* use ``--enable-discovery`` without an interface limit when configuring the
  switches with kayobe.
- Ironic is configured to use the neutron networking driver.

.. _ngs-commands:

Commands that NGS will execute
^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^

Networking Generic Switch is mainly concerned with toggling the ports onto different VLANs. It
cannot fully configure the switch.

.. TODO: Fill in the switch configuration

- Switching the port onto the provisioning network

  .. code-block:: shell

- Switching the port onto the tenant network.

  .. code-block:: shell

- When deleting the instance, the VLANs are removed from the port. Using:

  .. code-block:: shell

NGS will save the configuration after each reconfiguration (by default).

Ports managed by NGS
^^^^^^^^^^^^^^^^^^^^

The command below extracts a list of port UUID, node UUID and switch port information.

.. code-block:: bash

    openstack baremetal port list --field uuid --field node_uuid --field local_link_connection --format value

NGS will manage VLAN membership for ports when the ``local_link_connection`` fields match one of the switches in ``ml2_conf.ini``.
The rest of the switch configuration is static.
The switch configuration that NGS will apply to these ports is detailed in :ref:`dynamic-switch-configuration`.

.. _ironic-node-discovery:

Ironic node discovery
---------------------

Discovery is a process used to automatically enrol new nodes in Ironic.
It works by PXE booting the nodes into the Ironic Python Agent (IPA) ramdisk.
This ramdisk will collect hardware and networking configuration from the node in a process known as introspection.
This data is used to populate the baremetal node object in Ironic.
The series of steps you need to take to enrol a new node is as follows:

- Configure credentials on the BMC. These are needed for Ironic to be able to perform power control actions.

- Controllers should have network connectivity with the target BMC.

- (If kayobe manages physical network) Add any additional switch configuration to kayobe config.
  The minimal switch configuration that kayobe needs to know about is described in :ref:`tor-switch-configuration`.

- Apply any :ref:`static switch configration <static-switch-config>`. This performs the initial
  setup of the switchports that is needed before Ironic can take over. The static configuration
  will not be modified by Ironic, so it should be safe to reapply at any point. See :ref:`ngs-commands`
  for details about the switch configuation that Networking Generic Switch will apply.

- (If kayobe manages physical network) Put the node onto the provisioning network by using the
  ``--enable-discovery`` flag and either ``--interface-description-limit`` or ``--interface-limit``
  (do not run this command without one of these limits). See :ref:`static-switch-config`.

    * This is only necessary to initially discover the node. Once the node is in registered in Ironic,
      it will take over control of the the VLAN membership. See :ref:`dynamic-switch-configuration`.

    * This provides ethernet connectivity with the controllers over the `workload provisioning` network

- (If kayobe doesn't manage physical network) Put the node onto the provisioning network.

.. TODO: link to the relevant file in kayobe config

- Add node to the kayobe inventory.

.. TODO: Fill in details about necessary BIOS & RAID config

- Apply any necesary BIOS & RAID configuration.

.. TODO: Fill in details about how to trigger a PXE boot

- PXE boot the node.

- If the discovery process is successful, the node will appear in Ironic and will get populated with the necessary information from the hardware inspection process.

.. TODO: Link to the Kayobe inventory in the repo

- Add node to the Kayobe inventory in the ``baremetal-compute`` group.

- The node will begin in the ``enroll`` state, and must be moved first to ``manageable``, then ``available`` before it can be used.

  If Ironic automated cleaning is enabled, the node must complete a cleaning process before it can reach the available state.

  * Use Kayobe to attempt to move the node to the ``available`` state.

    .. code-block:: console

       source etc/kolla/public-openrc.sh
       kayobe baremetal compute provide --limit <node>

- Once the node is in the ``available`` state, Nova will make the node available for scheduling. This happens periodically, and typically takes around a minute.

.. _tor-switch-configuration:

Top of Rack (ToR) switch configuration
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

Networking Generic Switch must be aware of the Top-of-Rack switch connected to the new node.
Switches managed by NGS are configured in ``ml2_conf.ini``.

.. TODO: Fill in details about how switches are added to NGS config in kayobe-config

After adding switches to the NGS configuration, Neutron must be redeployed.

Considerations when booting baremetal compared to VMs
------------------------------------------------------

- You can only use networks of type: vlan
- Without using trunk ports, it is only possible to directly attach one network to each port or port group of an instance.

  * To access other networks you can use routers
  * You can still attach floating IPs

- Instances take much longer to provision (expect at least 15 mins)
- When booting an instance use one of the flavors that maps to a baremetal node via the RESOURCE_CLASS configured on the flavor.
