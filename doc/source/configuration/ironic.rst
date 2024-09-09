======
Ironic
======

Ironic networking
=================

Ironic will require the workload provisioning and cleaning networks to be
configured in ``networks.yml``

The workload provisioning network will require an allocation pool for
Ironic Inspection and for Neutron. The Inspector allocation pool will be
used to define static addresses for baremetal nodes during inspection and
the Neutron allocation pool is used to assign addresses dynamically during
baremetal provisioning.

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

Overcloud Ironic will be deployed with a listening TFTP server on the
control plane which will provide baremetal nodes that PXE boot with the
Ironic Python Agent (IPA) kernel and ramdisk. Since the TFTP server is
listening exclusively on the internal API network it's neccessary for a
route to exist between the provisoning/cleaning networks and the internal
API network, we can achieve this is by defining a Neutron router using
`OpenStack Config <https://github.com/stackhpc/openstack-config>`.

It not necessary to define the provision and cleaning networks in this
configuration as they will be generated during

.. code-block:: console

  kayobe overcloud post configure

The openstack config file could resemble the network, subnet and router
configuration shown below:

.. code-block:: yaml

  networks:
    - "{{ openstack_network_internal }}"

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
specific to that type of baremetal host. You will need to replace the custom
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

Enabling conntrack (ML2/OVS only)
=================================

Conntrack_helper will be required when UEFI booting on a cloud with ML2/OVS
and using the iptables firewall_driver, otherwise TFTP traffic is dropped due
to it being UDP. You will need to define some extension drivers in ``neutron.yml``
to ensure conntrack is enabled in neutron server.

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

To add the conntrack_helper to the neutron router, you can use the openstack
CLI

.. code-block:: console

  openstack network l3 conntrack helper create \
  --helper tftp \
  --protocol udp \
  --port 69 \
  <ironic_router_uuid>

Baremetal inventory
===================

The baremetal inventory is constructed with three different group types.
The first group is the default baremetal compute group for Kayobe called
[baremetal-compute] and will contain all baremetal nodes including tenant
and hypervisor nodes. This group acts as a parent for all baremetal nodes
and config that can be shared between all baremetal nodes will be defined
here.

We will need to create a Kayobe group_vars file for the baremetal-compute
group that contains all the variables we want to define for the group. We
can put all these variables in the inventory in
‘inventory/group_vars/baremetal-compute/ironic-vars’ The ironic_driver_info
template dict contains all variables to be templated into the driver_info
property in Ironic. This includes the BMC address, username, password,
IPA configuration etc. We also currently define the ironic_driver here as
all nodes currently use the Redfish driver.

.. code-block:: yaml

    ironic_driver: redfish

    ironic_driver_info:
      redfish_system_id: "{{ ironic_redfish_system_id }}"
      redfish_address: "{{ ironic_redfish_address }}"
      redfish_username: "{{ ironic_redfish_username }}"
      redfish_password: "{{ ironic_redfish_password }}"
      redfish_verify_ca: "{{ ironic_redfish_verify_ca }}"
      ipmi_address: "{{ ipmi_address }}"

    ironic_properties:
      capabilities: "{{ ironic_capabilities }}"

    ironic_redfish_address: "{{ ipmi_address }}"
    ironic_redfish_username: "{{ inspector_redfish_username }}"
    ironic_redfish_password: "{{ inspector_redfish_password }}"
    ironic_capabilities: "boot_option:local,boot_mode:uefi"

The second group type will be the hardware type that a baremetal node belongs
to, These variables will be in the inventory too in ‘inventory/group_vars/
baremetal-<YOUR_BAREMETAL_HARDWARE_TYPE>’

Specific variables to the hardware type include the resource_class which is
used to associate the hardware type to the flavour in Nova we defined earlier
in Openstack Config.

.. code-block:: yaml

    ironic_resource_class: "example_resource_class"
    ironic_redfish_system_id: "example_system_id"
    ironic_redfish_verify_ca: "{{ inspector_rule_var_redfish_verify_ca }}"

The third group type will be the rack where the node is installed. This is the
group in which the rack specific networking configuration is defined here and
where the BMC address is entered as a host variable for each baremetal node.
Nodes can now be entered directly into the hosts file as part of this group.

.. code-block:: ini

    [rack1]
    hv001 ipmi_address=10.1.28.16
    hv002 ipmi_address=10.1.28.17
    …

This rack group contains the baremetal hosts but will also need to be
associated with the baremetal-compute and baremetal-sr645 groups in order for
those variables to be associated with the rack group.
	
.. code-block:: ini

	[baremetal-<YOUR_BAREMETAL_HARDWARE_TYPE>:children]
	rack1
	…

	[baremetal-compute:children]
	rack1
	…

Node enrollment
===============

When nodes are defined in the inventory you can begin enrolling them by
invoking the Kayobe commmand

.. code-block:: console

  (kayobe) $ kayobe baremetal compute register

All nodes that were not defined in Ironic previously should’ve been enrolled
following this playbook and should now be in ‘manageable’ state if Ironic was
able to reach the BMC of the node. We will need to inspect the baremetal nodes
to gather information about their hardware to prepare for deployment. Kayobe
provides an inspection workflow and can be run using:

.. code-block:: console

  (kayobe) $ kayobe baremetal compute inspect

Inspection would require PXE booting the nodes into IPA. If the nodes were able
to PXE boot properly they would now be in ‘manageable’ state again. If an error
developed during PXE booting, the nodes will now be in ‘inspect failed’ state
and issues preventing the node from booting or returning introspection data
will need to be resolved before continuing. If the nodes did inspect properly,
they can be cleaned and made available to Nova by running the provide workflow.

.. code-block:: console

  (kayobe) $ kayobe baremetal compute provide

Baremetal hypervisors
=====================

Nodes that will not be dedicated as baremetal tenant nodes can be converted
into hypervisors as required. StackHPC Kayobe configuration provides a workflow
to provision baremetal tenants with the purpose of converted these nodes to
hypervisors. To begin the process of converting nodes we will need to define a
child group of the rack which will contain baremetal nodes dedicated to compute
hosts.

.. code-block:: ini

	[rack1]
  hv001 ipmi_address=10.1.28.16
  hv002 ipmi_address=10.1.28.17
  …

	[rack1-compute]
  hv003 ipmi_address=10.1.28.18
  hv004 ipmi_address=10.1.28.19
  …

	[rack1:children]
	rack1-compute

	[compute:children]
	rack1-compute

The rack1-compute group as shown above is also associated with the Kayobe
compute group in order for Kayobe to run the compute Kolla workflows on these
nodes during service deployment.

You will also need to setup the Kayobe network configuration for the rack1
group. In networks.yml you should create an admin network for the rack1 group,
this should consist of the correct CIDR for the rack being deployed.
The configuration should resemble below in networks.yml:

.. code-block:: yaml

	physical_rack1_admin_oc_net_cidr: “172.16.208.128/27”
	physical_rack1_admin_oc_net_gateway: “172.16.208.129”
	physical_rack1_admin_net_defroute: true

You will also need to configure a neutron network for racks to deploy instances
on, we can configure this in openstack-config as before. We will need to define
this network and associate a subnet for it for each rack we want to enroll in
Ironic.

.. code-block:: yaml

	openstack_network_rack:
  name: "rack-net"
  project: "admin"
  provider_network_type: "vlan"
  provider_physical_network: "provider"
  provider_segmentation_id: 450
  shared: false
  external: false
  subnets:
	- "{{ openstack_subnet_rack1 }}"

  openstack_subnet_rack1:
    name: "rack1-subnet"
    project: "admin"
    cidr: "172.16.208.128/27"
    enable_dhcp: false
    gateway_ip: "172.16.208.129"
    allocation_pool_start: "172.16.208.130"
    allocation_pool_end: "172.16.208.130"

The subnet configuration largely resembles the Kayobe network configuration,
however we do not need to define an allocation pool or enable dhcp as we will
be associating neutron ports with our hypervisor instances per IP address to
ensure they match up properly.

Now we should ensure the network interfaces are properly configured for the
rack1-compute group, the interfaces should include the kayobe admin network
for rack1 and the kayobe internal API network and be defined in the group_vars.

.. code-block:: yaml

 network_interfaces:
  - "internal_net"
  - "physical_rack1_admin_oc_net"

  admin_oc_net_name: "physical_rack1_admin_oc_net"

  physical_rack1_admin_oc_net_bridge_ports:
    - eth0
  physical_rack1_admin_oc_net_interface: br0

  internal_net_interface: "br0.{{ internal_net_vlan }}"

We should also ensure some variables are configured properly for our group,
such as the hypervisor image. These variables can be defined anywhere in
group_vars, we can place them in the ironic-vars file we used before for
baremetal node registration.

.. code-block:: yaml

	hypervisor_image: "<image_uuid>"
	key_name: "<key_name>"
	availability_zone: "nova"
	baremetal_flavor: "<ironic_flavor_name>"
	baremetal_network: "rack-net"
	auth:
    auth_url: "{{ lookup('env', 'OS_AUTH_URL') }}"
    username: "{{ lookup('env', 'OS_USERNAME') }}"
    password: "{{ lookup('env', 'OS_PASSWORD') }}"
    project_name: "{{ lookup('env', 'OS_PROJECT_NAME') }}"

With these variables defined we can now begin deploying the baremetal nodes as
instances, to begin we invoke the deploy-baremetal-hypervisor ansible playbook.

.. code-block:: console

	kayobe playbook run $KAYOBE_CONFIG_PATH/ansible/deploy-baremetal-hypervisor.yml

This playbook will update the Kayobe network allocations with the the admin
network addresses associated with that rack for each baremetal server, e.g.
in the case of rack 1 this will appear in network-allocations.yml as 

.. code-block:: yaml

  physical_rack1_admin_oc_net_ips:
    hv003: 172.16.208.133
    hv004: 172.16.208.134

Once the network allocations have been updated, the playbook will then create a
Neutron port configured with the address of the baremetal node admin network.
The baremetal hypervisors will then be imaged and deployed associated with that
Neutron port. You should ensure that all nodes are correctly associated with
the right baremetal instance, you can do this by running a baremetal node show
on any given hypervisor node and comparing the server uuid to the metadata on
the Nova instance.

Once the nodes are deployed, we can use Kayobe to configure them as compute
hosts, running kayobe overcloud host configure on these nodes will ensure that
all networking, package and various other host configurations are setup

.. code-block:: console

  kayobe overcloud host configure --limit baremetal-<YOUR_BAREMETAL_HARDWARE_TYPE>

Following host configuration we can begin deploying OpenStack services to the
baremetal hypervisors by invoking kayobe overcloud service deploy. Nova
services will be deployed to the baremetal hosts.

.. code-block:: console

  kayobe overcloud service deploy --kolla-limit baremetal-<YOUR_BAREMETAL_HARDWARE_TYPE>

Un-enrolling hypervisors
========================

To convert baremetal hypervisors into regular baremetal compute instances you
will need to drain the hypervisor of all running compute instances, you should
first invoke the nova-compute-disable playbook to ensure all Nova services on
the baremetal node are disabled and compute instances will not be allocated to
this node.

.. code-block:: console

  (kayobe) $ kayobe playbook run $KAYOBE_CONFIG_PATH/ansible/nova-compute-disable.yml

Now the Nova services are disabled you should also ensure any existing compute
instances are moved elsewhere by invoking the nova-compute-drain playbook

.. code-block:: console

  (kayobe) $ kayobe playbook run $KAYOBE_CONFIG_PATH/ansible/nova-compute-drain.yml

Now the node has no instances allocated to it you can delete the instance using
the OpenStack CLI and the node will be moved back to ``available`` state.

.. code-block:: console

  (os-venv) $ openstack server delete ...
