======
ci-aio
======

This environment deploys an all-in-one converged control/compute cloud for
testing.

There are two ways to set up the environment. The automated setup script
automates the manual setup steps below, and is recommended for most users.
The manual setup steps are provided for reference, and for users who wish to
make changes to the setup process.

Prerequisites
=============

* a CentOS Stream 8 or Ubuntu Focal 20.04 host
* access to the Test Pulp server on SMS lab

Automated Setup
===============

Access the host via SSH.

Download the setup script:

.. parsed-literal::

   wget https://raw.githubusercontent.com/stackhpc/stackhpc-kayobe-config/stackhpc/yoga/etc/kayobe/environments/ci-aio/automated-setup.sh

Change the permissions on the script:

.. parsed-literal::

   sudo chmod 700 automated-setup.sh

Acquire the Ansible Vault password for this repository, and store a
copy at ``~/vault-pw``.

Run the setup script:

.. parsed-literal::

   ./automated-setup.sh

The script will pull the current version of Kayobe and this repository, and
then run the manual setup steps below. The script can be easily edited to use
a different branch of Kayobe or this repository.

Manual Setup
============

Host Configuration
------------------

Access the host via SSH.

Install package dependencies.

On CentOS:

.. parsed-literal::

   sudo dnf install -y python3-virtualenv

On Ubuntu:

.. parsed-literal::

   sudo apt update
   sudo apt install -y python3-virtualenv

Clone the Kayobe and Kayobe configuration repositories (this one):

.. parsed-literal::

   cd
   mkdir -p src
   pushd src
   git clone https://github.com/stackhpc/kayobe.git -b |current_release_git_branch_name|
   git clone https://github.com/stackhpc/stackhpc-kayobe-config -b |current_release_git_branch_name| kayobe-config
   popd

Create a virtual environment and install Kayobe:

.. parsed-literal::

   cd
   mkdir -p venvs
   pushd venvs
   virtualenv kayobe
   source kayobe/bin/activate
   pip install -U pip
   pip install ../src/kayobe
   popd

Add initial network configuration:

.. parsed-literal::

   sudo ip l add breth1 type bridge
   sudo ip l set breth1 up
   sudo ip a add 192.168.33.3/24 dev breth1
   sudo ip l add dummy1 type dummy
   sudo ip l set dummy1 up
   sudo ip l set dummy1 master breth1

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
