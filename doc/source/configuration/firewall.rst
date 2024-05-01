.. _firewall:

========
Firewall
========

StackHPC Kayobe configuration provides a standardised firewalld configuration.
The configuration uses the :kayobe-doc:`firewall
<configuration/reference/hosts.html#firewalld>` host configuration
functionality of Kayobe.

The firewall configuration is provided in
``etc/kayobe/inventory/group_vars/all/firewall``.

Enabling StackHPC firewalld rules
=================================

The standardised firewalld configuration is not enabled by default and must be
actively opted into. To do so, make the following changes in
``etc/kayobe/<group>.yml`` (or
``etc/kayobe/environments/<enviroment>/<group>.yml`` if environments are being
used).

Controller firewalld Configuration
----------------------------------

.. code-block:: yaml
   :caption: ``controllers.yml``

   ###############################################################################
   # Controller node firewalld configuration.

   # Whether to install and enable firewalld.
   controller_firewalld_enabled: true

   # A list of zones to create. Each item is a dict containing a 'zone' item.
   controller_firewalld_zones: "{{ stackhpc_firewalld_zones }}"

   # A firewalld zone to set as the default. Default is unset, in which case
   # the default zone will not be changed.
   # Predefined zones are listed here:
   # https://firewalld.org/documentation/zone/predefined-zones.html
   controller_firewalld_default_zone: trusted

   # A list of firewall rules to apply. Each item is a dict containing
   # arguments to pass to the firewalld module. Arguments are omitted if not
   # provided, with the following exceptions:
   # - offline: true
   # - permanent: true
   # - state: enabled
   controller_firewalld_rules: "{{ stackhpc_firewalld_rules }}"

Compute firewalld Configuration
-------------------------------

.. code-block:: yaml
   :caption: ``compute.yml``

   ###############################################################################
   # Compute node firewalld configuration.

   # Whether to install and enable firewalld.
   compute_firewalld_enabled: true

   # A list of zones to create. Each item is a dict containing a 'zone' item.
   compute_firewalld_zones: "{{ stackhpc_firewalld_zones }}"

   # A firewalld zone to set as the default. Default is unset, in which case
   # the default zone will not be changed.
   # Predefined zones are listed here:
   # https://firewalld.org/documentation/zone/predefined-zones.html
   compute_firewalld_default_zone: trusted

   # A list of firewall rules to apply. Each item is a dict containing
   # arguments to pass to the firewalld module. Arguments are omitted if not
   # provided, with the following exceptions:
   # - offline: true
   # - permanent: true
   # - state: enabled
   compute_firewalld_rules: "{{ stackhpc_firewalld_rules }}"

Storage firewalld Configuration
-------------------------------

.. code-block:: yaml
   :caption: ``storage.yml``

   ###############################################################################
   # storage node firewalld configuration.

   # Whether to install and enable firewalld.
   storage_firewalld_enabled: true

   # A list of zones to create. Each item is a dict containing a 'zone' item.
   storage_firewalld_zones: "{{ stackhpc_firewalld_zones }}"

   # A firewalld zone to set as the default. Default is unset, in which case
   # the default zone will not be changed.
   # Predefined zones are listed here:
   # https://firewalld.org/documentation/zone/predefined-zones.html
   storage_firewalld_default_zone: trusted

   # A list of firewall rules to apply. Each item is a dict containing
   # arguments to pass to the firewalld module. Arguments are omitted if not
   # provided, with the following exceptions:
   # - offline: true
   # - permanent: true
   # - state: enabled
   storage_firewalld_rules: "{{ stackhpc_firewalld_rules }}"

Monitoring firewalld Configuration
----------------------------------

.. code-block:: yaml
   :caption: ``monitoring.yml``

   ###############################################################################
   # monitoring node firewalld configuration.

   # Whether to install and enable firewalld.
   monitoring_firewalld_enabled: true

   # A list of zones to create. Each item is a dict containing a 'zone' item.
   monitoring_firewalld_zones: "{{ stackhpc_firewalld_zones }}"

   # A firewalld zone to set as the default. Default is unset, in which case
   # the default zone will not be changed.
   # Predefined zones are listed here:
   # https://firewalld.org/documentation/zone/predefined-zones.html
   monitoring_firewalld_default_zone: trusted

   # A list of firewall rules to apply. Each item is a dict containing
   # arguments to pass to the firewalld module. Arguments are omitted if not
   # provided, with the following exceptions:
   # - offline: true
   # - permanent: true
   # - state: enabled
   monitoring_firewalld_rules: "{{ stackhpc_firewalld_rules }}"

Infrastructure VM firewalld Configuration
-----------------------------------------

The standard firewalld configuration has rules for wazuh-manager and Ansible
control host Infrastructure VMs.

.. code-block:: yaml
   :caption: ``infra-vms.yml``

   ###############################################################################
   # Infrastructure VM node firewalld configuration

   # Whether to install and enable firewalld.
   infra_vm_firewalld_enabled: true

   # A list of zones to create. Each item is a dict containing a 'zone' item.
   infra_vm_firewalld_zones: "{{ stackhpc_firewalld_zones }}"

   # A firewalld zone to set as the default. Default is unset, in which case
   # the default zone will not be changed.
   # Predefined zones are listed here:
   # https://firewalld.org/documentation/zone/predefined-zones.html
   infra_vm_firewalld_default_zone: trusted

   # A list of firewall rules to apply. Each item is a dict containing
   # arguments to pass to the firewalld module. Arguments are omitted if not
   # provided, with the following exceptions:
   # - offline: true
   # - permanent: true
   # - state: enabled
   infra_vm_firewalld_rules: "{{ stackhpc_firewalld_rules }}"

Seed firewalld Configuration
----------------------------

.. code-block:: yaml
   :caption: ``seed.yml``

   ###############################################################################
   # seed node firewalld configuration.

   # Whether to install and enable firewalld.
   seed_firewalld_enabled: true

   # A list of zones to create. Each item is a dict containing a 'zone' item.
   seed_firewalld_zones: "{{ stackhpc_firewalld_zones }}"

   # A firewalld zone to set as the default. Default is unset, in which case
   # the default zone will not be changed.
   # Predefined zones are listed here:
   # https://firewalld.org/documentation/zone/predefined-zones.html
   seed_firewalld_default_zone: trusted

   # A list of firewall rules to apply. Each item is a dict containing
   # arguments to pass to the firewalld module. Arguments are omitted if not
   # provided, with the following exceptions:
   # - offline: true
   # - permanent: true
   # - state: enabled
   seed_firewalld_rules: "{{ stackhpc_firewalld_rules }}"

Seed Hypervisor firewalld Configuration
---------------------------------------

.. code-block:: yaml
   :caption: ``seed_hypervisor.yml``

   ###############################################################################
   # seed_hypervisor node firewalld configuration.

   # Whether to install and enable firewalld.
   seed_hypervisor_firewalld_enabled: true

   # A list of zones to create. Each item is a dict containing a 'zone' item.
   seed_hypervisor_firewalld_zones: "{{ stackhpc_firewalld_zones }}"

   # A firewalld zone to set as the default. Default is unset, in which case
   # the default zone will not be changed.
   # Predefined zones are listed here:
   # https://firewalld.org/documentation/zone/predefined-zones.html
   seed_hypervisor_firewalld_default_zone: trusted

   # A list of firewall rules to apply. Each item is a dict containing
   # arguments to pass to the firewalld module. Arguments are omitted if not
   # provided, with the following exceptions:
   # - offline: true
   # - permanent: true
   # - state: enabled
   seed_hypervisor_firewalld_rules: "{{ stackhpc_firewalld_rules }}"

Custom rules
------------

Custom firewalld rules can be added for any of the following groups using their
corresponding variables:

* All hosts - ``stackhpc_common_firewalld_rules_extra``
* Controllers - ``stackhpc_controller_firewalld_rules_extra``
* Compute - ``stackhpc_compute_firewalld_rules_extra``
* Storage - ``stackhpc_storage_firewalld_rules_extra``
* Monitoring - ``stackhpc_monitoring_firewalld_rules_extra``
* Wazuh Manager Infrastructure VM - ``stackhpc_wazuh_manager_infra_vm_firewalld_rules_extra``
* Ansible Control host Infrastructure VM - ``stackhpc_ansible_control_infra_vm_firewalld_rules_extra``
* Seed - ``stackhpc_seed_firewalld_rules_extra``
* Seed Hypervisor - ``stackhpc_seed_hypervisor_firewalld_rules_extra``

Each variable is a list of firewall rules to apply. Each item is a dict
containing arguments to pass to the firewalld module. The variables can be
defined as group vars, host vars, or in the extra vars files.

The example below would enable SSH on the ``provision_oc`` network, and disable
UDP port 1000 on the ``admin_oc`` network for the Wazuh manager Infrastructure
VM:

.. code-block:: yaml
   :caption: ``etc/kayobe/inventory/group_vars/wazuh_manager/firewall``

   stackhpc_wazuh_manager_infra_vm_firewalld_rules_extra:
     -  service: ssh
        network: "{{ provision_oc_net_name }}"
        zone: "{{ provision_oc_net_name | net_zone }}"
        state: enabled
     -  port: 1000/udp
        network: "{{ admin_oc_net_name }}"
        zone: "{{ admin_oc_net_name | net_zone }}"
        state: disabled

Beware that if any rules are found that directly conflict (a service or port is
both enabled and disabled) the configuration will fail. There is currently no
way to override rules in the standard configuration, other than to find the
rule and delete it manually. If you find a standard rule that does not work for
your deployment, please consider merging your changes back in to upstream SKC.

Validation
----------

The ``kayobe configuration dump`` command can be used to view all the rules
that will be applied to a host.

.. code-block:: bash

   kayobe configuration dump --var-name stackhpc_firewalld_rules --limit <host>

If the command above prints a template, rather than a clean list of rules, the
configuration is invalid. The kayobe configuration dump command can be used on
other variables such as ``stackhpc_firewalld_rules_unverified`` or
``stackhpc_*_firewalld_rules`` to debug the configuration. See the `How it
works`_ section for more details.

Kolla-Ansible configuration
---------------------------

Ensure Kolla Ansible opens up ports in firewalld for services on the public
API network:

.. code-block:: yaml
   :caption: ``etc/kayobe/kolla/globals.yml``

   enable_external_api_firewalld: true
   external_api_firewalld_zone: "{{ public_net_name | net_zone }}"

Ensure every network in ``networks.yml`` has a zone defined. The standard
configuration is to set the internal network zone to ``trusted`` and every
other zone to the name of the network. See
``etc/kayobe/environments/ci-multinode/networks.yml`` for a practical example.

Applying changes
----------------

Use the ``kayobe * host configure`` commands to apply the changes:

.. code-block:: bash

   # For Seed Hypervisor hosts
   kayobe seed hypervisor host configure -t network,firewall
   # For Seed hosts
   kayobe seed host configure -t network,firewall
   # For Infrastructure VM hosts
   kayobe infra vm host configure -t network,firewall
   # For Overcloud hosts
   kayobe overcloud host configure -t network,firewall

How it works
============

The standard firewall rule configuration is stored in
``etc/kayobe/inventory/group_vars/all/firewall``.

The file contains sections for different host groups. There are sections for:

* Common (all hosts)
* Controllers
* Compute
* Storage
* Monitoring
* Wazuh Manager Infrastructure VM
* Ansible Control host Infrastructure VM
* Seed
* Seed Hypervisor

Each of these sections contains a template. The template is made of sets of
rules. The rules can then be enabled and disabled in sets, based on properties
of the cloud. For example, if ``kolla_enable_designate`` is true, a set of
rules will be enabled in ``stackhpc_controller_firewalld_rules_template``.

The rules are then formatted into a single list of the enabled default rules
for a group e.g. ``stackhpc_controller_firewalld_rules_default`` for
controllers. It is worth noting that the rules are also manipulated to reduce
duplication. When no zone is specified in a rule template, it is inferred from
the network.

The default rules are combined with any extra rules defined for the deployment.
For controllers, these are ``stackhpc_controller_firewalld_rules_extra``. The
complete set of controller firewalld rules is
``stackhpc_controller_firewalld_rules``.

Each group-specific list of rules is combined into
``stackhpc_firewalld_rules_unverified`` based on the host's group membership,
as well as a set of common rules, which is enabled for all hosts.

``stackhpc_firewalld_rules`` is the final list of rules that have been verified
for correctness.
