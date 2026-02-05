Sushy Baremetal Environment
===========================
This environment creates a virtual baremetal node using libvirt and Sushy Redfish Emulator.
The libvirt VM is exposed via a Redfish endpoint provided by Sushy which allow the node
to be enrolled and managed by Openstack Ironic.
This environment is based on the CI-AIO and stackhpc-baremetal environments.

Set up for AIO testing:

* ``kayobe control host bootstrap``

* ``kayobe overcloud host configure``

* ``kayobe overcloud service deploy``

* ``source kayobe-config/etc/kolla/admin-openrc.sh``

* ``kayobe overcloud post configure``

Auto-setup script used to set up Sushy and create virtual baremetal within libvirt using the
`stackhpc ansible libvirt vm role <https://github.com/stackhpc/ansible-role-libvirt-vm>`_ .

``kayobe playbook run environments/stackhpc-sushy-baremetal/ansible/auto-setup.yml``

Scripts from the baremetal env can be run to enroll, inspect and clean virtual baremetal nodes.

``kayobe playbook run environments/stackhpc-baremetal/ansible/baremetal-all.yml``
