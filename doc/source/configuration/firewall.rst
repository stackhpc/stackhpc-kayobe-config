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

Kolla-Ansible configuration
---------------------------

Ensure Kolla Ansible opens up ports in firewalld for services on the public
API network:

.. code-block:: yaml
   :caption: ``etc/kayobe/kolla/globals.yml``

   enable_external_api_firewalld: true
   external_api_firewalld_zone: "{{ public_net_name | net_zone }}"

Network configuration
---------------------

Ensure every network in ``networks.yml`` has a zone defined. The standard
configuration is to set the internal network zone to ``trusted`` and every
other zone to the name of the network. See
``etc/kayobe/environments/ci-multinode/networks.yml`` for a practical example.

Custom rules
------------

Custom firewalld rules can be added to ``stackhpc_firewalld_rules_extra``

The variable is a list of firewall rules to apply. Each item is a dictionary
containing arguments to pass to the firewalld module. The variable can be
defined as a group var or host var in the kayobe inventory.

The structure of custom rules is different from the default rules. Custom rules
use the firewalld Ansible module format. Arguments are omitted if not provided,
with the following exceptions:

* ``offline: true``
* ``permanent: true``
* ``state: enabled``

The main differences are that the ``zone`` argument is mandatory, and the
``network`` argument is not.

The example below would enable SSH in the ``provision_oc`` zone, and disable
UDP port 1000 in the ``admin_oc`` zone for the Wazuh manager Infrastructure
VM:

.. code-block:: yaml
   :caption: ``etc/kayobe/inventory/group_vars/wazuh_manager/firewall``

   stackhpc_firewalld_rules_extra:
     -  service: ssh
        zone: "{{ provision_oc_net_name | net_zone }}"
        state: enabled
     -  port: 1000/udp
        zone: "{{ admin_oc_net_name | net_zone }}"
        state: disabled

Extra rules have higher precedence than the default rules but are not
validated before being applied. Use with caution. If you need to add a custom
rule, consider adding it to the default rule list with an appropriate boolean
condition, and where possible merge your changes back into upstream SKC.

Validation
----------

The ``kayobe configuration dump`` command can be used to view all the rules
that will be applied to a host.

.. code-block:: bash

   kayobe configuration dump --var-name stackhpc_firewalld_rules --limit <host>

A shorter version, ``stackhpc_firewalld_rules_debug`` prints the rules in a
simplified format:

.. code-block:: bash

   kayobe configuration dump --var-name stackhpc_firewalld_rules_debug --limit <host>

If the commands above print a template, rather than a list of rules, the
configuration may be invalid. The ``kayobe configuration dump`` command can be
used on other variables such as ``stackhpc_firewalld_rules_default`` or
``stackhpc_*_firewalld_rules_template`` to debug the configuration. See the
`How it works`_ section for more details.

It can be useful to print the active ports on each type of host, to create
rules for running services. The internal network is currently left open. The
below command will print all other open ports:

.. code-block:: bash

   ss -lntpu | grep --invert-match '<internal net ip>'

It is strongly recommended that you dry-run the changes using ``--diff`` and
``--check`` before applying to a production system:

.. code-block:: bash
   :caption: ``Overcloud diff example``

   kayobe overcloud host configure -t firewall --diff --check

Baseline checks
^^^^^^^^^^^^^^^

Before applying, it is a good idea to take note of any actively firing alerts
and run Tempest to gather a baseline. See the :doc:`Tempest
</operations/tempest>` page for more details.

Applying changes
----------------

Before applying these changes, you should be completely sure you are not going
to lock yourself out of any hosts. If you are deploying these changes to a test
environment, consider setting a password on the stack user so that you can
access the host through a BMC or other virtual console.

The following Kayobe command can be used to set a password on all overcloud
hosts:

.. code-block:: bash

   kayobe overcloud host command run --command "echo 'stack:super-secret-password' | sudo chpasswd" --show-output

The ``firewalld-watchdog.yml`` playbook can be used to set up a timer that
disables the firewalld service after a period of time (default 600s). It should
be used as follows:

.. code-block:: bash

   # Enable the watchdog BEFORE applying the firewall configuration
   kayobe playbook run etc/kayobe/ansible/firewalld-watchdog.yml -l <hosts>

   # Disable the watchdog after applying the firewall configuration
   kayobe playbook run etc/kayobe/ansible/firewalld-watchdog.yml -l <hosts> -e firewalld_watchdog_state=absent

If the firewall rules block connectivity, the second playbook run (disabling
the watchdog) will fail. You will still be able to get in after the watchdog
triggers. Remember to disable the watchdog when you are finished, otherwise the
firewall will be disabled!

Changes should be applied to controllers one at a time to ensure connectivity
is not lost.

Once you are sure you know what you are doing, use the ``kayobe * host
configure`` commands to apply the firewall changes:

.. code-block:: bash

   # For Seed Hypervisor hosts
   kayobe seed hypervisor host configure -t network,firewall
   # For Seed hosts
   kayobe seed host configure -t network,firewall
   # For Infrastructure VM hosts
   kayobe infra vm host configure -t network,firewall
   # For the First Controller
   kayobe overcloud host configure -t network,firewall -l controllers[0]
   # For the Second Controller
   kayobe overcloud host configure -t network,firewall -l controllers[1]
   # For the Third Controller
   kayobe overcloud host configure -t network,firewall -l controllers[2]
   # For the rest of the Overcloud hosts
   kayobe overcloud host configure -t network,firewall

Debugging
---------

To test the changes, first check for any firing alerts, then try simple smoke
tests (create a VM, list OpenStack endpoints etc.), then run Tempest.

If the firewall configuration is causing errors, it is often useful to log
blocked packets.

.. code-block:: bash

   sudo sed -i s/LogDenied=off/LogDenied=all/g /etc/firewalld/firewalld.conf
   sudo systemctl restart firewalld

Dropped packets will be logged to ``dmesg``.

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

The templates are combined into a single list,
``stackhpc_firewalld_rules_template``. Templates are selected according to the
host's group membership, as well as a set of common rules, which is enabled for
all hosts.

The rules are then formatted into a single list of the enabled default rules:
``stackhpc_firewalld_rules_default``. The Rules are manipulated to reduce
duplication. When no zone is specified in a rule template, it is inferred from
the network. They are also validated. Conflicting rules will result in an
error. Non-applicable rules are dropped.

The default rules are combined with any extra rules defined for the deployment.
The complete set of controller firewalld rules is
``stackhpc_firewalld_rules``.
