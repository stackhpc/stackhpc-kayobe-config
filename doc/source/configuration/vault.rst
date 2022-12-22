================================
Hashicorp Vault for internal PKI
================================

This document describes how to deploy Hashicorp Vault for
internal PKI purposes using the
`StackHPC Hashicorp collection <https://galaxy.ansible.com/stackhpc/hashicorp>`_

Background
==========

Prerequisites
=============

Before beginning the deployment of vault for openstack internal TLS and backend TLS  you should ensure that you have the following.

  * StackHPC Hashicorp collection
  * Seed Node or a host to run the vault container on
  * Sensible name for the RootCA and Intermediate CA

Deployment
==========

Install the Ansible hashivault modules
--------------------------------------

1. Add the following to kayobe-config/requirements.txt

.. code-block::

   git+https://github.com/stackhpc/ansible-modules-hashivault@stackhpc

2. Install the Python package (with the Kayobe virtualenv activated)

.. code-block::

   pip install -r requirements.txt

Clone the StackHPC Hashicorp Vault collection
---------------------------------------------

1. Add the following into the kayobe-config/etc/kayobe/ansible/requirements.yml

.. code-block::

   collections:
   - name: stackhpc.hashicorp

2. Perform a control host upgrade to pull down the collection

.. code-block::

   kayobe control host upgrade

Setup Vault on the seed node
----------------------------

1. Run vault-deploy-seed.yml custom playbook

.. code-block::

   kayobe playbook run ansible/vault-deploy-seed.yml

To be continued 
