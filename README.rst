=============================
StackHPC Kayobe Configuration
=============================

This repository provides a base Kayobe configuration for the Wallaby release
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

New deployments
---------------

If starting a new deployment, clone this repository as the starting point for
your configuration.

.. code-block:: console

   git clone https://github.com/stackhpc/stackhpc-kayobe-config -b stackhpc/wallaby

Existing deployments
--------------------

If migrating an existing deployment to StackHPC Kayobe configuration, you will
need to merge the changes in this repository into your repository.

.. code-block:: console

   git remote add stackhpc https://github.com/stackhpc/stackhpc-kayobe-config
   git fetch stackhpc
   git merge stackhpc/stackhpc/wallaby

Configuration
=============

The URL and credentials of the local Pulp server should be configured in
``etc/kayobe/pulp.yml``, using Ansible Vault to encrypt the password:

.. code-block:: yaml

   pulp_url: <url>
   pulp_username: admin
   pulp_password: <password>

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

The following custom playbooks are provided in ``etc/kayobe/ansible/``:

* ``pulp-repo-sync.yml``: Synchronise package repositories in local Pulp with
  Ark.
* ``pulp-repo-publish.yml``: Publish synced package repositories under the
  ``development`` distribution.
* ``pulp-repo-promote.yml``: Promote the ``development`` distribution content
  to the ``production`` distribution.
* ``pulp-container-sync.yml``: Synchronise container repositories in local Pulp
  with Ark.
* ``pulp-container-publish.yml``: Publish synced container repositories.

See the Kayobe `custom playbook documentation
<https://docs.openstack.org/kayobe/wallaby/custom-ansible-playbooks.html>`__
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
* ``pulp-repo-promote.yml``: Promote packages in the ``development``
  distribution to the ``production`` distribution in the local Pulp. This will
  make all packages currently available to cloud nodes using the
  ``development`` distribution also available to cloud nodes using the
  ``production`` distribution. Typically this would be done only once the new
  packages have been validated in a development or staging environment.

Working with pulp
=================

The `pulp_cli tool
<https://docs.pulpproject.org/pulp_cli/>`__ can be used to administer your local
pulp installastion. Please follow the upstream documentation for installation
instructions.

pulp_cli tricks
---------------

Saving credentials
~~~~~~~~~~~~~~~~~~

This is useful to avoid the need to always supply your credentials when running commands
from the command line:

.. code-block:: console

    (venv-pulp) [stack@seed ~]$ pulp config create --username admin --base-url http://<pulp server>:8080 --password <password>


Troubleshoting
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

The issue is that pulp will attempt to create a push repository on demand. This conflicts
with the on_demand repository under the stackhpc namespace. You can resolve this conflict
by deleting the push repository using pulp_cli:

.. code-block:: console

    (venv-pulp) [stack@seed ~]$ pulp --base-url http://<pulp server>:8080--username admin --password <password> container distribution destroy --name stackhpc/centos-source-prometheus-jiralert
    Started background task /pulp/api/v3/tasks/1f0a474a-b7c0-44b4-9ef4-ed633077f4d8/
    .Done.


Resources
=========

* Kayobe documentation: https://docs.openstack.org/kayobe/wallaby/
* Kayobe source: https://opendev.org/openstack/kayobe
* Kayobe bugs: https://storyboard.openstack.org/#!/project/openstack/kayobe-config
* IRC: #openstack-kolla
