=============================
StackHPC Kayobe Configuration
=============================

This repository provides a base Kayobe configuration for the Yoga release
of StackHPC OpenStack.

StackHPC release train
======================

StackHPC provides packages and container images for OpenStack via `Ark
<https://ark.stackhpc.com>`__.

Deployments should use a local `Pulp <https://pulpproject.org/>`__ repository
server to synchronise content from Ark and serve it locally. Access to the
repositories on Ark is controlled via X.509 certificates issued by StackHPC.

This configuration is a base, and should be merged with any existing Kayobe
configuration. It currently provides the following:

* Configuration to deploy a local Pulp service as a container on the seed
* Pulp repository definitions for CentOS Stream 8
* Playbooks to synchronise a local Pulp service with Ark
* Configuration to use the local Pulp repository mirrors on control plane hosts
* Configuration to use the local Pulp container registry on control plane hosts

This configuration defines two `Pulp distributions
<https://docs.pulpproject.org/pulpcore/workflows/promotion.html>`__ for
packages, ``development`` and ``production``. This allows packages to be
updated and tested in a development or staging environment before rolling them
out to production.

How to consume this configuration
=================================

This configuration is not a complete Kayobe configuration, rather it should be
treated as a base, in place of the `upstream kayobe-config
<https://opendev.org/openstack/kayobe-config>`__. Indeed, this repository is
based on the upstream kayobe-config, with some opinionated configuration
changes applied.

Since this repository makes changes to the base configuration, it works best
when used with Kayobe's `multiple environments
<https://docs.openstack.org/kayobe/latest/multiple-environments.html>`__
feature.

This configuration should be consumed using the `StackHPC Kayobe fork
<https://github.com/stackhpc/kayobe/tree/stackhpc/yoga>`__, which includes
backported support for Ansible collections.

New deployments
---------------

If starting a new deployment, clone this repository as the starting point for
your configuration.

.. code-block:: console

   git clone https://github.com/stackhpc/stackhpc-kayobe-config -b stackhpc/yoga

Existing deployments
--------------------

If migrating an existing deployment to StackHPC Kayobe configuration, you will
need to merge the changes in this repository into your repository.

.. code-block:: console

   git remote add stackhpc https://github.com/stackhpc/stackhpc-kayobe-config
   git fetch stackhpc
   git merge stackhpc/stackhpc/yoga

Updating
--------

This base configuration will be updated over time, to update repository
versions, container image tags, and other configuration. Deployments may
consume these updates by merging in the changes with their local configuration.

.. code-block:: console

   git fetch stackhpc
   git merge stackhpc/stackhpc/yoga

The intention is to avoid merge conflicts where possible, but there may be
cases where this is difficult. We are open to discussion on how best to
approach this on both sides.

Configuration
=============

Local Pulp server
-----------------

The URL and credentials of the local Pulp server are configured in
``etc/kayobe/pulp.yml`` via ``pulp_url``, ``pulp_username`` and
``pulp_password``. In most cases, the default values should be sufficient.
An admin password must be generated and set as the value of a
``secrets_pulp_password`` variable, typically in an Ansible Vault encrypted
``etc/kayobe/secrets.yml`` file. This password will be automatically set on
Pulp startup.

StackHPC Ark
------------

The container image registry credentials issued by StackHPC should be
configured in ``etc/kayobe/pulp.yml``, using Ansible Vault to encrypt the
password:

.. code-block:: yaml

   stackhpc_release_pulp_username: <username>
   stackhpc_release_pulp_password: <password>

The client certificate and private key issued by StackHPC should be stored in
``etc/kayobe/ansible/certs/ark.stackhpc.com/client-cert.pem`` and
``etc/kayobe/ansible/certs/ark.stackhpc.com/client-key.pem``, respectively,
with the private key encrypted via Ansible Vault.

The distribution name for the environment should be configured as either
``development`` or ``production`` via ``stackhpc_repo_distribution`` in
``etc/kayobe/stackhpc.yml``.

Usage
=====

The local Pulp service will be deployed as a `Seed custom container
<https://docs.openstack.org/kayobe/yoga/configuration/reference/seed-custom-containers.html>`__
on next ``kayobe seed service deploy`` or ``kayobe seed service upgrade``.

The following custom playbooks are provided in ``etc/kayobe/ansible/``:

See the Kayobe `custom playbook documentation
<https://docs.openstack.org/kayobe/yoga/custom-ansible-playbooks.html>`__
for information on how to run them.

* ``pulp-repo-sync.yml``: Pull packages from Ark to the local Pulp. This will
  create a new repository version (snapshot) for each repository in the local
  Pulp server when new packages are available. The new packages will not be
  available to cloud nodes until they have been published.
* ``pulp-repo-publish.yml``: Publish synchronised packages to the
  ``development`` distribution in the local Pulp. This will make synchronised
  packages available to cloud nodes using the ``development`` distribution
  (typically a development or staging environment). The new packages will not
  be available to cloud nodes using the ``production`` distribution until they
  have been promoted.
* ``pulp-repo-promote-production.yml``: Promote packages in the ``development``
  distribution to the ``production`` distribution in the local Pulp. This will
  make all packages currently available to cloud nodes using the
  ``development`` distribution also available to cloud nodes using the
  ``production`` distribution. Typically this would be done only once the new
  packages have been validated in a development or staging environment.
* ``pulp-container-sync.yml``: Pull container images from Ark to the local
  Pulp. This will create a new repository version (snapshot) for each
  repository in the local Pulp server when new image tags are available. The
  new image tags will not be available to cloud nodes until they have been
  published.
* ``pulp-container-publish.yml``: Publish synchronised container images in the
  local Pulp. This will make synchonised container images available to cloud
  nodes.

Working with pulp
=================

The `pulp CLI
<https://docs.pulpproject.org/pulp_cli/>`__  tool can be used to administer your local
pulp installation. Please follow the upstream documentation for installation
instructions.

pulp CLI tricks
---------------

Saving credentials
~~~~~~~~~~~~~~~~~~

This is useful to avoid the need to always supply your credentials when running commands
from the command line:

.. code-block:: console

    (venv-pulp) [stack@seed ~]$ pulp config create --username admin --base-url http://<pulp server>:8080 --password <password>


Troubleshooting
--------------

HTTP Error 400: Bad Request {"name":["This field must be unique."]}
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

If you have previously tried to push an image to pulp e.g for local testing, you may
see this message when you later try to run ``pulp-container-sync.yml``:

.. code-block:: console

    TASK [stackhpc.pulp.pulp_repository : Setup container repositories] *****************************
    failed: [localhost] (item=stackhpc/centos-source-prometheus-jiralert) => changed=false
    ansible_loop_var: item
    item:
      name: stackhpc/centos-source-prometheus-jiralert
      policy: on_demand
      remote_password: password
      remote_username: username
      state: present
      url: https://ark.stackhpc.com
    msg: 'HTTP Error 400: Bad Request b''{"name":["This field must be unique."]}'''

The issue is that pushing an image automatically creates a `container-push repository
<https://docs.pulpproject.org/pulp_container/restapi.html#tag/Repositories:-Container-Push>`__
which conflicts with the creation of a regular container repository of the same
name. You can resolve this conflict by deleting the distribution associated 
with the push repository using the pulp CLI:

.. code-block:: console

    (venv-pulp) [stack@seed ~]$ pulp --base-url http://<pulp server>:8080--username admin --password <password> container distribution destroy --name stackhpc/centos-source-prometheus-jiralert
    Started background task /pulp/api/v3/tasks/1f0a474a-b7c0-44b4-9ef4-ed633077f4d8/
    .Done.

Environments
============

The following Kayobe environments are provided with this configuration:

* ``ci-aio``: deploys an all-in-one converged control/compute cloud for testing
* ``ci-builder``: builds container images

ci-aio
------

Prerequisites
^^^^^^^^^^^^^

* a CentOS Stream 8 or Ubuntu Focal 20.04 host
* access to the local Pulp server

Setup
^^^^^

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
   git clone https://github.com/stackhpc/kayobe.git -b stackhpc/yoga
   git clone https://github.com/stackhpc/stackhpc-kayobe-config -b stackhpc/yoga kayobe-config
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
^^^^^^^^^^^^

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
^^^^^^^^^^

Next, configure the host OS & services.

.. code-block:: console

   kayobe overcloud host configure

Finally, deploy the overcloud services.

.. code-block:: console

   kayobe overcloud service deploy

The control plane should now be running.

Testing
^^^^^^^

Run a smoke test:

.. code-block:: console

   cd ~/kayobe
   ./dev/overcloud-test-vm.sh

ci-builder
----------

The ``ci-builder`` Kayobe environment is used to build Kolla container images.
Images are built using package repositories in the StackHPC development Pulp
service, and pushed there once built.

Prerequisites
^^^^^^^^^^^^^

* a CentOS Stream 8 or Ubuntu Focal 20.04 host
* access to the local Pulp server

Setup
^^^^^

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
   git clone https://github.com/stackhpc/kayobe.git -b stackhpc/yoga
   git clone https://github.com/stackhpc/stackhpc-kayobe-config -b stackhpc/yoga kayobe-config
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
^^^^^^^^^^^^

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
^^^^^^^^^^

Next, configure the host OS & services.

.. code-block:: console

   kayobe seed host configure

Building images
^^^^^^^^^^^^^^^

At this point you are ready to build and push some container images.

.. code-block:: console

   kayobe seed container image build --push
   kayobe overcloud container image build --push

The container images are tagged as ``yoga-<datetime>``. This Kayobe
configuration includes a hook that writes the tag to ``~/kolla_tag``, since
it is not always simple to determine which tag was last applied to built
images.

To use the new images, edit
``~/src/kayobe-config/etc/kayobe/kolla.yml`` to set the above
tag as the value of the ``kolla_openstack_release`` variable.

Resources
=========

* Kayobe documentation: https://docs.openstack.org/kayobe/yoga/
* Kayobe source: https://opendev.org/openstack/kayobe
* Kayobe bugs: https://storyboard.openstack.org/#!/project/openstack/kayobe-config
* IRC: #openstack-kolla
