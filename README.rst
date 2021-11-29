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
updated and tested before rolling out to production.

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

Resources
=========

* Kayobe documentation: https://docs.openstack.org/kayobe/wallaby/
* Kayobe source: https://opendev.org/openstack/kayobe
* Kayobe bugs: https://storyboard.openstack.org/#!/project/openstack/kayobe-config
* IRC: #openstack-kolla
