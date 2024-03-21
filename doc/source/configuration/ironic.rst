======
Ironic
======

Ironic networking
=================

Ironic will require the workload provisioning and cleaning networks to be
configured in ``networks.yml``

The workload provisioning network will require an allocation pool for
Ironic inspection and for Neutron, an example configuration is shown
below.

.. code-block:: yaml

  # Workload provisioning network IP information.
  provision_wl_net_cidr: "172.0.0.0/16"
  provision_wl_net_allocation_pool_start: "172.0.0.4"
  provision_wl_net_allocation_pool_end: "172.0.0.6"
  provision_wl_net_inspection_allocation_pool_start: "172.0.1.4"
  provision_wl_net_inspection_allocation_pool_end: "172.0.1.250"
  provision_wl_net_neutron_allocation_pool_start: "172.0.2.4"
  provision_wl_net_neutron_allocation_pool_end: "172.0.2.250"
  provision_wl_net_neutron_gateway: "172.0.1.1"

The cleaning network will also require a Neutron allocation pool.

.. code-block:: yaml

  # Cleaning network IP information.
  cleaning_net_cidr: "172.1.0.0/16"
  cleaning_net_allocation_pool_start: "172.1.0.4"
  cleaning_net_allocation_pool_end: "172.1.0.6"
  cleaning_net_neutron_allocation_pool_start: "172.1.2.4"
  cleaning_net_neutron_allocation_pool_end: "172.1.2.250"
  cleaning_net_neutron_gateway: "172.1.0.1"

OpenStack Config
================

Overcloud Ironic will require a router to exist between the internal API
network and the provision workload network, a way to achieve this is by
using `OpenStack Config <https://github.com/stackhpc/openstack-config>`
to define the internal API network in Neutron and set up a router with
a gateway.

It not necessary to define the provision and cleaning networks in this
configuration as they will be generated during

.. code-block:: console

  kayobe overcloud post configure

The openstack config file could resemble the network, subnet and router
configuration shown below:

.. code-block:: yaml

  networks:
    - "{{ openstack_network_intenral }}"
  openstack_network_internal:
    name: "internal-net"
    project: "admin"
    provider_network_type: "vlan"
    provider_physical_network: "physnet1"
    provider_segmentation_id: 458
    shared: false
    external: true

  subnets:
    - "{{ openstack_subnet_internal }}"
  openstack_subnet_internal:
    name: "internal-net"
    project: "admin"
    cidr: "10.10.3.0/24"
    enable_dhcp: true
    allocation_pool_start: "10.10.3.3"
    allocation_pool_end: "10.10.3.3"

  openstack_routers:
    - "{{ openstack_router_ironic }}"

  openstack_router_ironic:
    - name: ironic
      project: admin
      interfaces:
        - net: "provision-net"
          subnet: "provision-net"
          portip: "172.0.1.1"
        - net: "cleaning-net"
          subnet: "cleaning-net"
          portip: "172.1.0.1"
          network: internal-net

To provision baremetal nodes in Nova you will also require setting a flavour
speciifc to that type of baremetal host. You will need to replace the custom
resource ``resources:CUSTOM_<YOUR_BAREMETAL_RESOURCE_CLASS>`` placeholder with
the resource class of your baremetal hosts, you will also need this later when
configuring the baremetal-compute inventory.

.. code-block:: yaml

  openstack_flavors:
    - "{{ openstack_flavor_baremetal_A }}"
    # Bare metal compute node.
    openstack_flavor_baremetal_A:
    name: "baremetal-A"
    ram: 1048576
    disk: 480
    vcpus: 256
    extra_specs:
    "resources:CUSTOM_<YOUR_BAREMETAL_RESOURCE_CLASS>": 1
    "resources:VCPU": 0
    "resources:MEMORY_MB": 0
    "resources:DISK_GB": 0

Enabling conntrack
==================

UEFI booting requires conntrack_helper to be configured on the Ironic neutron
router, this is due to TFTP traffic being dropped due to being UDP. You will
need to define some extension drivers in ``neutron.yml`` to ensure conntrack is
enabled in neutron server.

.. code-block:: yaml

  kolla_neutron_ml2_extension_drivers:
    port_security
    conntrack_helper
    dns_domain_ports

The neutron l3 agent also requires conntrack to be set as an extension in
``kolla/config/neutron/l3_agent.ini``

.. code-block:: ini

  [agent]
  extensions = conntrack_helper

It is also required to load the conntrack kernel module ``nf_nat_tftp``,
``nf_conntrack`` and ``nf_conntrack_tftp`` on network nodes. You can load these
modules using modprobe or define these in /etc/module-load.

The Ironic neutron router will also need to be configured to use
conntrack_helper.

.. code-block:: json

  "conntrack_helpers": {
    "protocol": "udp",
    "port": 69,
    "helper": "tftp"
  }

Currently it's not possible to add this helper via the OpenStack CLI, to add
this to the Ironic router you will need to make a request to the API directly,
for example via cURL.

.. code-block:: console

  curl -g -i -X POST \
  http://<internal_api_vip>:9696/v2.0/routers/<ironic_router_uuid>/conntrack_helpers \
  -H "Accept: application/json" \
  -H "User-Agent: openstacksdk/2.0.0 keystoneauth1/5.4.0 python-requests/2.31.0 CPython/3.9.18" \
  -H "X-Auth-Token: <issued_token>" \
  -d '{ "conntrack_helper": {"helper": "tftp", "protocol": "udp", "port": 69 } }'

TFTP server
===========

By default the Ironic TFTP server (ironic_pxe container) will call the UEFI
boot file ``ipxe-x86_64.efi`` instead of ``ipxe.efi`` meaning no boot file will
be sent during the PXE boot process in the default configuration.

As of now this is solved by using a hack workaround by changing the boot file
in the ``ironic_pxe`` container. To do this you will need to enter the
container and rename the file manually.

.. code-block:: console

  docker exec ironic_pxe “mv /tftpboot/ipxe-x86_64.efi /tftpboot/ipxe.efi”

Baremetal inventory
===================

To begin enrolling nodes you will need to define them in the hosts file.

.. code-block:: ini

  [r1]
  hv1 ipmi_address=10.1.28.16
  hv2 ipmi_address=10.1.28.17
  …

  [r1:vars]
  ironic_driver=redfish
  resource_class=<your_resource_class>
  redfish_system_id=<your_redfish_systen_id>
  redfish_verify_ca=<your_redfish_verify_ca>
  redfish_username=<your_redfish_username>
  redfish_password=<your_redfish_password>

  [baremetal-compute:children]
  r1

The typical layout for baremetal nodes are separated by racks, for instance
in rack 1 we have the following configuration set up where the BMC addresses
are defined for all nodes, and Redfish information such as username, passwords
and the system ID are defined for the rack as a whole.

You can add more racks to the deployment by replicating the rack 1 example and
adding that as an entry to the baremetal-compute group.

Node enrollment
===============

When nodes are defined in the inventory you can begin enrolling them by
invoking the Kayobe commmand (Note that only the Redfish driver is supported
by this command)

.. code-block:: console

  kayobe baremetal compute register

Following registration, the baremetal nodes can be inspected and made
available for provisioning by Nova via the Kayobe commands

.. code-block:: console

  kayobe baremetal compute inspect
  kayobe baremetal compute provide
