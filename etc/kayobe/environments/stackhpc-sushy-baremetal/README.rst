Sushy Baremetal Environment
===========================
This environment creates a virtual baremetal node using libvirt and Sushy Redfish Emulator.
The libvirt VM is exposed via a Redfish endpoint provided by Sushy which allows the node
to be enrolled and managed by Openstack Ironic.
This environment is based on the CI-AIO and stackhpc-baremetal environments.

Set up for AIO testing:

* ``kayobe control host bootstrap``

Check if a network bridge called ``breth1`` for ip address ``192.168.33.3``
by running ``ip a``
If not set up then run the following in the CLI:
.. code-block::
    if ! ip l show breth1 >/dev/null 2>&1; then
        sudo ip l add breth1 type bridge
    fi
        sudo ip l set breth1 up
    if ! ip a show breth1 | grep 192.168.33.3/24; then
        sudo ip a add 192.168.33.3/24 dev breth1
    fi
    if ! ip l show dummy1 >/dev/null 2>&1; then
        sudo ip l add dummy1 type dummy
    fi
    sudo ip l set dummy1 up
    sudo ip l set dummy1 master breth1

* ``kayobe overcloud host configure``

* ``kayobe overcloud service deploy``

* ``source $KAYOBE_CONFIG_PATH/../kolla/admin-openrc.sh``

* ``kayobe overcloud post configure``

Auto-setup playbook used to set up Sushy and create virtual baremetal within libvirt using the
`stackhpc ansible libvirt vm role <https://github.com/stackhpc/ansible-role-libvirt-vm>`_ .

``kayobe playbook run environments/stackhpc-sushy-baremetal/ansible/auto-setup.yml``

This auto-setup playbook runs two separate playbooks:

* ``sushy-setup.yml`` - Installs libvirt and required dependencies, creates a Python virtual
environment for Sushy, templates the configuration, and enables the ``sushyemud`` service.

* ``create-virtual-baremetal.yml`` - Defines and starts the libvirt storage pool, installs required
Python libraries, and uses the ``stackhpc.libvirt-vm`` role to create the virtual baremetal nodes.

Once the virtual baremetal is created from the previous step and configured in Sushy, the enrollment
process which is used for other baremetal can begin. Scripts from the baremetal env can be run
to enroll, inspect and clean virtual baremetal nodes.

``kayobe playbook run environments/stackhpc-baremetal/ansible/baremetal-all.yml``
