======
ci-aio
======

This environment deploys an all-in-one converged control/compute cloud for
testing.

There are two ways to set up the environment. The automated setup script
automates the manual setup steps below, and is recommended for most users.
The manual setup steps are provided for reference, and for users who wish to
make changes to the setup process.

.. warning::

    This guide was written for the Yoga release and has not been validated for
    Caracal. Proceed with caution.

Prerequisites
=============

* a Rocky Linux 9 or Ubuntu Jammy 22.04 host

Automated Setup
===============

Access the host via SSH. You may wish to start a ``tmux`` session.

Download the setup script:

.. parsed-literal::

   wget https://raw.githubusercontent.com/stackhpc/stackhpc-kayobe-config/stackhpc/2024.1/etc/kayobe/environments/ci-aio/automated-setup.sh

Change the permissions on the script:

.. parsed-literal::

   sudo chmod 700 automated-setup.sh

Acquire the Ansible Vault password for this repository, and store a
copy at ``~/vault-pw``.

Run the setup script:

.. parsed-literal::

   ./automated-setup.sh

The script will pull the current version of Kayobe and this repository, and
then run the manual setup steps below. The script can be easily edited with the
following options:

* ``BASE_PATH`` (default: ``~``) - Directory to deploy from. The directory must
  exist before running the script.
* ``KAYOBE_BRANCH`` (default: ``stackhpc/2023.1``) - The branch of Kayobe
  source code to use.
* ``KAYOBE_CONFIG_BRANCH`` (default: ``stackhpc/2023.1``) - The branch of
  ``stackhpc-kayobe-config`` to use.
* ``KAYOBE_AIO_LVM`` (default: ``true``) - Whether the image uses LVM.
* ``KAYOBE_CONFIG_EDIT_PAUSE`` (default: ``false``) - Option to pause
  deployment after cloning the kayobe-config branch, so the environment can be
  customised before continuing.
* ``AIO_RUN_TEMPEST`` (default: ``false``) - Whether to run Tempest Refstack
  after deployment instead of the default VM smoke test.

Manual Setup
============

Host Configuration
------------------

Access the host via SSH.

If using an LVM-based image, extend the ``lv_home`` and ``lv_tmp`` logical
volumes.

.. parsed-literal::

   sudo pvresize $(sudo pvs --noheadings | head -n 1 | awk '{print $1}')
   sudo lvextend -L 4G /dev/rootvg/lv_home -r
   sudo lvextend -L 4G /dev/rootvg/lv_tmp -r

Install package dependencies.

On Rocky Linux:

.. parsed-literal::

   sudo dnf install -y git

On Ubuntu:

.. parsed-literal::

   sudo apt update
   sudo apt install -y gcc git libffi-dev python3-dev python-is-python3 python3-venv

Clone the Kayobe and Kayobe configuration repositories (this one):

.. parsed-literal::

   cd
   mkdir -p src
   pushd src
   git clone https://github.com/stackhpc/stackhpc-kayobe-config -b |current_release_git_branch_name| kayobe-config
   popd

Create a virtual environment and install Kayobe:

.. parsed-literal::

   cd
   mkdir -p venvs
   pushd venvs
   python3 -m venv kayobe
   source kayobe/bin/activate
   pip install -U pip
   pip install ../src/kayobe-config/requirements.txt
   popd

Add initial network configuration:

.. parsed-literal::

   sudo ip l add breth1 type bridge
   sudo ip l set breth1 up
   sudo ip a add 192.168.33.3/24 dev breth1
   sudo ip l add dummy1 type dummy
   sudo ip l set dummy1 up
   sudo ip l set dummy1 master breth1

On Ubuntu systems, persist the running network configuration.

.. parsed-literal::

   sudo cp /run/systemd/network/* /etc/systemd/network

Configuration
=============

If using Ironic:

.. parsed-literal::

   cd src/kayobe-config
   cat << EOF > etc/kayobe/aio.yml
   kolla_enable_ironic: true
   EOF

Installation
------------

Acquire the Ansible Vault password for this repository, and store a copy at
``~/vault-pw``.

The following commands install Kayobe and its dependencies, and prepare the
Ansible control host.

.. parsed-literal::

   export KAYOBE_VAULT_PASSWORD=$(cat ~/vault-pw)
   pushd ~/venvs/kayobe
   source bin/activate
   popd
   pushd ~/src/kayobe-config
   source kayobe-env --environment ci-aio
   kayobe control host bootstrap

Deployment
----------

If using an LVM-based image, grow the root volume group.

.. parsed-literal::

   kayobe playbook run etc/kayobe/ansible/growroot.yml

On Ubuntu systems, purge the command-not-found package.

.. parsed-literal::

   kayobe playbook run etc/kayobe/ansible/purge-command-not-found.yml

Next, configure the host OS & services.

.. parsed-literal::

   kayobe overcloud host configure

Finally, deploy the overcloud services.

.. parsed-literal::

   kayobe overcloud service deploy

The control plane should now be running.

If using Ironic, run overcloud post configuration:

.. parsed-literal::

   source ~/src/kayobe-config/etc/kolla/public-openrc.sh
   kayobe overcloud post configure

Testing
-------

Run a smoke test:

.. parsed-literal::

   cd ~/src/kayobe
   ./dev/overcloud-test-vm.sh

Ironic
------

For a control plane with Ironic enabled, a "bare metal" instance can be
deployed. We can use the Tenks project to create fake bare metal nodes.

Clone the tenks repository:

.. parsed-literal::

   cd ~/src/kayobe
   git clone https://opendev.org/openstack/tenks.git

Optionally, edit the Tenks configuration file,
``~/src/kayobe/dev/tenks-deploy-config-compute.yml``.

Run the ``dev/tenks-deploy-compute.sh`` script to deploy Tenks:

.. parsed-literal::

   cd ~/src/kayobe
   export KAYOBE_CONFIG_SOURCE_PATH=~/src/kayobe-config
   export KAYOBE_VENV_PATH=~/venvs/kayobe
   ./dev/tenks-deploy-compute.sh ./tenks/

Check that Tenks has created VMs called tk0 and tk1:

.. parsed-literal::

   sudo virsh list --all

Verify that VirtualBMC is running:

.. parsed-literal::

   ~/tenks-venv/bin/vbmc list

We are now ready to run the ``dev/overcloud-test-baremetal.sh`` script. This
will run the ``init-runonce`` setup script provided by Kolla Ansible that
registers images, networks, flavors etc. It will then deploy a bare metal
server instance, and delete it once it becomes active:

.. parsed-literal::

   ./dev/overcloud-test-baremetal.sh

The machines and networking created by Tenks can be cleaned up via
``dev/tenks-teardown-compute.sh``:

.. parsed-literal::

   ./dev/tenks-teardown-compute.sh ./tenks
