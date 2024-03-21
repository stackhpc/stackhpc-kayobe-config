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

Enabling conntrack
==================

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

To begin enrolling nodes you will need to define them in the hosts file.

.. code-block:: ini

  [r1]
  hv1 ipmi_address=10.1.28.16
  hv2 ipmi_address=10.1.28.17
  …

  [baremetal-compute:children]
  r1

The baremetal nodes will also require some extra variables to be defined
in the group_vars for your rack, these should include the BMC credentials
and the Ironic driver you wish to use.

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

    ironic_resource_class: "example_resouce_class"
    ironic_redfish_system_id: "/redfish/v1/Systems/System.Embedded.1"
    ironic_redfish_verify_ca: "{{ inspector_rule_var_redfish_verify_ca }}"
    ironic_redfish_address: "{{ ipmi_address }}"
    ironic_redfish_username: "{{ inspector_redfish_username }}"
    ironic_redfish_password: "{{ inspector_redfish_password }}"
    ironic_capabilities: "boot_option:local,boot_mode:uefi"

The typical layout for baremetal nodes are separated by racks, for instance
in rack 1 we have the following configuration set up where the BMC addresses
are defined for all nodes, and Redfish information such as username, passwords
and the system ID are defined for the rack as a whole.

You can add more racks to the deployment by replicating the rack 1 example and
adding that as an entry to the baremetal-compute group.

Node enrollment
===============

When nodes are defined in the inventory you can begin enrolling them by
invoking the Kayobe commmand

.. code-block:: console

  (kayobe) $ kayobe baremetal compute register

Following registration, the baremetal nodes can be inspected and made
available for provisioning by Nova via the Kayobe commands

.. code-block:: console

  (kayobe) $ kayobe baremetal compute inspect
  (kayobe) $ kayobe baremetal compute provide

Baremetal hypervisors
=====================

To deploy baremetal hypervisor nodes it will be neccessary to split out
the nodes you wish to use as hypervisors and add it to the Kayobe compute
group to ensure the hypervisor is configured as a compute node during
host configure.

.. code-block:: ini

    [r1]
    hv1 ipmi_address=10.1.28.16

    [r1-hyp]
    hv2 ipmi_address=10.1.28.17

    [r1:children]
    r1-hyp

    [compute:children]
    r1-hyp

    [baremetal-compute:children]
    r1

The hypervisor nodes will also need to define hypervisor specific variables
such as the image to be used, network to provision on and the availability zone.
These can be defined under group_vars.

.. code-block:: yaml

    hypervisor_image: "37825714-27da-48e0-8887-d609349e703b"
    key_name: "testing"
    availability_zone: "nova"
    baremetal_flavor: "baremetal-A"
    baremetal_network: "rack-net"
    auth:
      auth_url: "{{ lookup('env', 'OS_AUTH_URL') }}"
      username: "{{ lookup('env', 'OS_USERNAME') }}"
      password: "{{ lookup('env', 'OS_PASSWORD') }}"
      project_name: "{{ lookup('env', 'OS_PROJECT_NAME') }}"

To begin deploying these nodes as instances you will need to run the Ansible
playbook deploy-baremetal-instance.yml.

.. code-block:: console

  (kayobe) $ kayobe playbook run $KAYOBE_CONFIG_PATH/ansible/deploy-baremetal-instance.yml

This playbook will update network allocations with the new baremetal hypervisor
IP addresses, create a Neutron port corresponding to the address and deploy
an image on the baremetal instance.

When the playbook has finished and the rack is successfully imaged, they can be
configured with ``kayobe overcloud host configure`` and kolla compute services
can be deployed with ``kayobe overcloud service deploy``.

Un-enrolling hypervisors
========================

To convert baremetal hypervisors into regular baremetal compute instances you will need
to drain the hypervisor of all running compute instances, you should first invoke the
nova-compute-disable playbook to ensure all Nova services on the baremetal node are disabled
and compute instances will not be allocated to this node.

.. code-block:: console

  (kayobe) $ kayobe playbook run $KAYOBE_CONFIG_PATH/ansible/nova-compute-disable.yml

Now the Nova services are disabled you should also ensure any existing compute instances
are moved elsewhere by invoking the nova-compute-drain playbook

.. code-block:: console

  (kayobe) $ kayobe playbook run $KAYOBE_CONFIG_PATH/ansible/nova-compute-drain.yml

Now the node has no instances allocated to it you can delete the instance using
the OpenStack CLI and the node will be moved back to ``available`` state.

.. code-block:: console

  (os-venv) $ openstack server delete ...
