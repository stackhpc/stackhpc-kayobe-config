==========
ci-builder
==========

The ``ci-builder`` Kayobe environment is used to build Kolla container images.
Images are built using package repositories in the StackHPC development Pulp
service, and pushed there once built.

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
   source kayobe-env --environment ci-builder
   kayobe control host bootstrap

Deployment
==========

Next, configure the host OS & services.

.. code-block:: console

   kayobe seed host configure

Building images
===============

At this point you are ready to build and push some container images.

.. code-block:: console

   kayobe seed container image build --push
   kayobe overcloud container image build --push

The container images are tagged as |current_release|-<datetime>. This Kayobe
configuration includes a hook that writes the tag to ``~/kolla_tag``, since
it is not always simple to determine which tag was last applied to built
images.

To use the new images, edit
``~/src/kayobe-config/etc/kayobe/kolla.yml`` to set the above
tag as the value of the ``kolla_openstack_release`` variable.
