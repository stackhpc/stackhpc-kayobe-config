=============================
StackHPC Kayobe Configuration
=============================

This repository provides a base Kayobe configuration for the Victoria release
of StackHPC OpenStack.

StackHPC release train
======================

StackHPC provides packages and container images for OpenStack via `Ark
<https://ark.stackhpc.com>`__. For the Victoria release, only packages are
currently provided.

Deployments should use a local `Pulp <https://pulpproject.org/>`__ repository
server to synchronise content from Ark and serve it locally. Access to the
repositories on Ark is controlled via X.509 certificates issued by StackHPC.

This configuration is a base, and should be merged with any existing Kayobe
configuration. It currently provides the following:

* Configuration to deploy a local Pulp service as a container on the seed
* Pulp repository definitions for CentOS Stream 8
* Playbooks to synchronise a local Pulp service with Ark
* Configuration to use the local Pulp repository mirrors on control plane hosts

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

This configuration should be consumed using the `StackHPC Kayobe fork
<https://github.com/stackhpc/kayobe/tree/stackhpc/wallaby>`__, which includes
backported support for Ansible collections.

New deployments
---------------

If starting a new deployment, clone this repository as the starting point for
your configuration.

.. code-block:: console

   git clone https://github.com/stackhpc/stackhpc-kayobe-config -b stackhpc/victoria

Existing deployments
--------------------

If migrating an existing deployment to StackHPC Kayobe configuration, you will
need to merge the changes in this repository into your repository.

.. code-block:: console

   git remote add stackhpc https://github.com/stackhpc/stackhpc-kayobe-config
   git fetch stackhpc
   git merge stackhpc/stackhpc/victoria

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
<https://docs.openstack.org/kayobe/wallaby/configuration/reference/seed-custom-containers.html>`__
on next ``kayobe seed service deploy`` or ``kayobe seed service upgrade``.

The following custom playbooks are provided in ``etc/kayobe/ansible/``:

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
* ``pulp-repo-promote-production.yml``: Promote packages in the ``development``
  distribution to the ``production`` distribution in the local Pulp. This will
  make all packages currently available to cloud nodes using the
  ``development`` distribution also available to cloud nodes using the
  ``production`` distribution. Typically this would be done only once the new
  packages have been validated in a development or staging environment.

Resources
=========

* Kayobe documentation: https://docs.openstack.org/kayobe/victoria/
* Kayobe source: https://opendev.org/openstack/kayobe
* Kayobe bugs: https://storyboard.openstack.org/#!/project/openstack/kayobe-config
* IRC: #openstack-kolla
