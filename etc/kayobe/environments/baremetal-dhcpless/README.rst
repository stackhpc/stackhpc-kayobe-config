StackHPC DHCP-less Ironic environment
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

Mixin that layers on top of the ``baremetal`` environment and adds support for
`DHCP-less deployment
<https://docs.openstack.org/ironic/latest/admin/dhcp-less.html>`__. Nodes boot
the Ironic Python Agent (IPA) from Redfish virtual media, and glean in the
ramdisk configures networking statically from the ``network_data`` in the
virtual media config drive, so no DHCP server is needed on the provisioning
network.

Consuming this environment
^^^^^^^^^^^^^^^^^^^^^^^^^^

Add the ``baremetal-dhcpless`` environment to your ``.kayobe-environment``
file. It depends on ``baremetal``, which does not need to be listed as well:

.. code-block:: yaml
   :caption: $KAYOBE_CONFIG_PATH/environments/$KAYOBE_ENVIRONMENT/.kayobe-environment

   dependencies:
     - baremetal-dhcpless

Redeploy Ironic:

.. code-block:: console

   kayobe overcloud service deploy -kt ironic

Requirements
^^^^^^^^^^^^

* A Redfish-capable BMC (``redfish`` or ``idrac`` hardware type) that
  supports virtual media.
* An IPA ramdisk containing glean. On ``stable/2026.1`` the
  ``ironic-python-agent-ramdisk`` DIB element depends on ``simple-init``
  (glean), so the StackHPC published IPA images can be used. The element also
  includes ``dhcp-all-interfaces``, so the ramdisk may still attempt DHCP on
  NICs that aren't described in ``network_data``.
* The BMCs must be able to reach the Ironic HTTP server to download the
  virtual media ISO. If not, set ``ironic_dhcpless_external_http_url``.
* The deployed image must support network data, e.g. via cloud-init or glean.

UEFI boot
"""""""""

Ironic builds UEFI-bootable ISOs from an EFI System Partition (ESP) image.
``ironic_dhcpless_bootloader`` defaults to the ESP image that the Kolla
ironic-tftp container builds from the distribution's signed shim and grub
(``/var/lib/ironic/httpboot/esp.img``). ``ironic_dhcpless_grub_config_path``
must match the path that grub reads its configuration from, which defaults to
``EFI/<kolla_base_distro>/grub.cfg``.

Networking
""""""""""

The node's ``network_data`` field takes precedence over any network data
Ironic would otherwise generate from Neutron, and is used for every ramdisk
phase: inspection, cleaning, provisioning and rescue. The ramdisk therefore
always uses the same static IP on ``ironic_dhcpless_network``
(``provision_wl_net_name`` by default), so the inspection, cleaning and
provisioning networks must all be that network. The IP is not reserved in
Neutron, so it must be outside the Neutron allocation pool of that network.
DHCP can be disabled on the Neutron subnet.

If the Ironic API isn't on ``ironic_dhcpless_network``, the network needs a
gateway (``inspection_gateway``, ``neutron_gateway`` or ``gateway``) so that
the ramdisk can reach it.

The ``flat`` network interface works with the ports created by this
environment. The ``neutron`` network interface additionally requires each port
to have ``local_link_connection`` set, e.g. from LLDP data collected by in-band
agent inspection.

Registering nodes
^^^^^^^^^^^^^^^^^

Add nodes to the ``baremetal-dhcpless`` inventory group **and** to a driver
group from the ``baremetal`` environment (``baremetal-redfish`` or
``baremetal-idrac``). Each node's static IP defaults to the IP allocated to the
node on ``ironic_dhcpless_network`` in ``network-allocation.yml``, or can be
set with ``ironic_dhcpless_ip_address``.

The MAC address of the NIC on that network is discovered using out-of-band
Redfish inspection, which reads the NICs from the BMC without booting the
node. The NIC is selected as follows:

#. If ``ironic_dhcpless_redfish_interface`` is set, the NIC with that Redfish
   ``EthernetInterface`` ``Id`` (e.g. ``NIC.Integrated.1-1-1`` on Dell).
#. Otherwise, the PXE interface reported by the BMC, if any (iDRAC).
#. Otherwise, the node's only enabled NIC. If it has more than one, the hook
   fails and lists the interfaces found, so that you can set
   ``ironic_dhcpless_redfish_interface``.

``ironic_dhcpless_mac_address`` can be set per host to skip discovery, e.g. if
the BMC doesn't report the NIC. Note that some BMCs, such as HPE iLO, only
report NIC MAC addresses after the server has completed POST at least once.

.. code-block:: ini
   :caption: $KAYOBE_CONFIG_PATH/environments/$KAYOBE_ENVIRONMENT/inventory/hosts

   [baremetal-redfish]
   node0 redfish_address=https://10.1.0.10
   node1 redfish_address=https://10.1.0.11

   [baremetal-dhcpless]
   node0 ironic_dhcpless_redfish_interface=NIC.Integrated.1-1-1
   node1 ironic_dhcpless_mac_address=52:54:00:d3:6a:71

Then register the nodes as usual:

.. code-block:: console

   kayobe baremetal compute register

A ``post.d`` hook for ``baremetal compute register``
(``ansible/baremetal-dhcpless-network-data.yml``) then, for each node in
``baremetal-dhcpless``:

* runs Redfish inspection to discover the MAC address, unless
  ``ironic_dhcpless_mac_address`` is set or the node already has inspection
  data containing the NIC (set ``ironic_dhcpless_reinspect`` to ``true`` to
  force it). The node must be ``manageable``, which it is after
  registration. The Redfish inspect interface is only used for this
  inspection; the node's inspect interface is restored afterwards,
* sets the node's ``network_data`` field from
  ``ironic_dhcpless_network_data``,
* sets the boot interface to ``redfish-virtual-media`` (or
  ``idrac-redfish-virtual-media`` for the ``idrac`` driver). Ironic only
  allows this in the ``enroll``, ``manageable`` and ``available`` states, or
  in maintenance mode, so the hook fails for a deployed node that doesn't
  already have the right boot interface,
* ensures a PXE-enabled Ironic port exists for the MAC address, failing if
  the MAC belongs to a different node. Set ``ironic_dhcpless_create_port`` to
  ``false`` to skip this.

The playbook is idempotent and can also be run on its own:

.. code-block:: console

   kayobe playbook run $KAYOBE_CONFIG_PATH/environments/baremetal-dhcpless/ansible/baremetal-dhcpless-network-data.yml

For more complex layouts (bonds, VLANs, several NICs), override
``ironic_dhcpless_network_data`` per host. It uses the OpenStack config drive
``network_data.json`` format. See
``inventory/group_vars/baremetal-dhcpless/ironic.yml`` for all variables.

Inspection
^^^^^^^^^^

The ``redfish`` and ``idrac-redfish`` inspect interfaces are enabled in
addition to ``agent``, which is set as the default so that other nodes keep
using in-band inspection. In-band agent inspection boots IPA from virtual
media and uses the node's ``network_data``, so it works once the registration
hook has run. Kayobe's IPA inspection kernel options
(``inspector_extra_kernel_options``, e.g. LLDP and collectors) are passed to
the ramdisk.

Virtual media boots have no PXE interface, so this environment sets
``[inspector] update_pxe_enabled = False`` to stop in-band inspection from
disabling PXE on every port, which would make cleaning and provisioning fail.
This applies to all nodes, so in-band inspection no longer updates
``pxe_enabled`` on ports of PXE-booted nodes either.
