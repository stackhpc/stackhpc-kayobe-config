Baremetal Environment
=====================

This environment provides playbooks to automate the enrollment, inspection
and cleaning of baremetal nodes in Ironic. It is designed to be idempotent
and safe to re-run.

The purpose of this environment is to enroll baremetal nodes in Ironic,
verify the nodes BMC (redfish) connection, then perform refish and agent-based
inspection, and finally clean the nodes and make them available.

Inventory
---------

Baremetal nodes are defined in the inventory located ``stackhpc-baremetal/inventory/hosts`` file
This inventory can be hand-written or generated (eg from a python script).
Each nodes must have the required Ironic and Redfish variables.
These variables can be set in ``inventory/group_vars/baremetal-redfish/ironic``

Enable the Environment
-----------------------

This environment is intended to be layered on top of a base Kayobe environment
(e.g. ``ci-aio``), so that baremetal-specific defaults override those provided
by the base environment.
Create a ``.kayobe-environment`` file in the base of stackhpc-baremetal environment and add your
base environment as a dependency, for example if using CI-AIO as a base environment::
    file `.kayobe-environment`

    dependencies:
      - ci-aio

Activate the environment using ``source kayobe-config/kayobe-env --environment stackhpc-baremetal``

How to Run
----------

Run the full baremetal workflow using::

  kayobe playbook run \
    etc/kayobe/environments/stackhpc-baremetal/ansible/baremetal-all.yml

Workflow Overview
-----------------

The workflow is executed in the following order when ``baremetal-all.yml`` is run:

1. **Enroll nodes** – create Ironic nodes and move them to ``manageable``
2. **Check BMC is up** – verify Redfish connection
3. **Redfish inspection** – discover hardware
4. **Agent inspection** – collect LLDP
5. **Clean and provide** – clean nodes and move them to ``available``


Progress is tracked using the Ironic node ``extra`` field:

* ``kayobe_bmc_up``
* ``kayobe_redfish_inspect_done``
* ``kayobe_agent_inspect_done``
* ``kayobe_clean_done``

Completed stages are skipped on subsequent runs.

Inspection Notes
----------------

* Redfish is the primary inspection mechanism
* Agent inspection is required for LLDP discovery
* iPXE / IPMI inspection is only supported when using discovery DHCP and *not* Ironic-managed boot
