Sushy Baremetal Environment
===========================

Set up for AIO testing:
`kayobe control host bootstrap`
`kayobe overcloud host configure`
`kayobe overcloud service deploy`
`kayobe overcloud post configure`

Auto-step script used to set up Sushy and create virtual baremetal within libvirt
`kayobe playbook run environments/stackhpc-sushy-baremetal/ansible/auto-setup.yml`

Scripts from the baremetal env can now be ran to enroll, inspect and provide virtual baremetal nodes
`kayobe playbook run environments/stackhpc-baremetal/ansible/baremetal-all.yml`