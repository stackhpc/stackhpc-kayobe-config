======
ci-aio
======

This environment deploys an all-in-one converged control/compute cloud for
testing.

Prerequisites
=============

* a CentOS Stream 8 or Ubuntu Focal 20.04 host
* access to the local Pulp server

Setup
=====

Access the host via SSH.

Install package dependencies.

On CentOS:

.. code-block:: console

   sudo dnf install -y python3-virtualenv

On Ubuntu:

.. code-block:: console

   sudo apt update
   sudo apt install -y python3-virtualenv

Clone the Kayobe and Kayobe configuration repositories (this one):

.. code-block:: console

   cd
   mkdir -p src
   pushd src
   git clone https://github.com/stackhpc/kayobe.git -b stackhpc/xena
   git clone https://github.com/stackhpc/stackhpc-kayobe-config -b stackhpc/xena kayobe-config
   popd

Create a virtual environment and install Kayobe:

.. code-block:: console

   cd
   mkdir -p venvs
   pushd venvs
   virtualenv kayobe
   source kayobe/bin/activate
   pip install -U pip
   pip install ../src/kayobe
   popd

Add initial network configuration:

.. code-block:: console

   sudo ip l add breth1 type bridge
   sudo ip l set breth1 up
   sudo ip a add 192.168.33.3/24 dev breth1
   sudo ip l add dummy1 type dummy
   sudo ip l set dummy1 up
   sudo ip l set dummy1 master breth1

Installation
============

Acquire the Ansible Vault password for this repository, and store a copy at
``~/vault-pw``.

The following commands install Kayobe and its dependencies, and prepare the
Ansible control host.

.. code-block:: console

   export KAYOBE_VAULT_PASSWORD=$(cat ~/vault-pw)
   pushd ~/venvs/kayobe
   source bin/activate
   popd
   pushd ~/src/kayobe-config
   source kayobe-env --environment ci-aio
   kayobe control host bootstrap

Deployment
==========

Next, configure the host OS & services.

.. code-block:: console

   kayobe overcloud host configure

Finally, deploy the overcloud services.

.. code-block:: console

   kayobe overcloud service deploy

The control plane should now be running.

Testing
=======

Run a smoke test:

.. code-block:: console

   cd ~/kayobe
   ./dev/overcloud-test-vm.sh
