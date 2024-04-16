.. _firewall:

========
Firewall
========

StackHPC Kayobe configuration provides a standardised firewalld configuration.
The configuration uses the :kayobe-doc:`firewall
<configuration/reference/hosts.html#firewalld>` host configuration
functionality of Kayobe.

The firewall configuration is provided in
``etc/kayobe/inventory/group_vars/all/firewall``. This allows configuration
variables to be overridden on a per-group or per-host basis (which would not be
possible for an "extra variable" in ``etc/kayobe/*.yml``). This configuration
is not used by default, and must be actively opted into. This can be done as
follows:

.. code-block:: yaml
   :caption: ``etc/kayobe/controllers.yml``

   controller_firewalld_enabled: true
   controller_firewalld_rules: "{{ stackhpc_firewalld_rules }}"
   controller_firewalld_zones: "{{ stackhpc_firewalld_zones }}"
   # Predefined zones are listed here:
   # https://firewalld.org/documentation/zone/predefined-zones.html
   # Unset to leave the default zone unchanged
   controller_firewalld_default_zone: drop

This will configure the standard set of firewalld rules on controller hosts.
Rule definitions are automatically added according to group membership. Rule
sets exist for the following groups:

* Controllers - ``stackhpc_controller_firewalld_rules``
* Compute - ``stackhpc_compute_firewalld_rules``
* Storage - ``stackhpc_storage_firewalld_rules``
* Monitoring - ``stackhpc_monitoring_firewalld_rules``
* Wazuh Manager Infrastructure VM - ``stackhpc_wazuh_manager_infra_vm_firewalld_rules``
* Ansible Control host Infrastructure VM - ``stackhpc_ansible_control_infra_vm_firewalld_rules``
* Seed - ``stackhpc_seed_firewalld_rules``
* Seed Hypervisor - ``stackhpc_seed_hypervisor_firewalld_rules``
