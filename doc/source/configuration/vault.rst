================================
Hashicorp Vault for internal PKI
================================

This document describes how to deploy Hashicorp Vault for
internal PKI purposes using the
`StackHPC Hashicorp collection <https://galaxy.ansible.com/stackhpc/hashicorp>`_

Background
==========

Our OpenStack environment employs two separate HashiCorp Vault instances.
These instances manage the Public Key Infrastructure (PKI) by handling the
creation and issuance of certificates.

- The first HashiCorp Vault instance is located on the seed host.
  It handles infrastructure-level certificates, generating the root
  Certificate Authority (CA) and intermediate CA for the second Vault.
  The ``vault-deploy-seed.yml`` playbook sets up this instance.

- The second HashiCorp Vault instance is within the OpenStack
  overcloud, located on the controller nodes. This instance uses the
  intermediate CA from the root Vault to issue application-specific
  certificates. The ``vault-deploy-overcloud.yml`` playbook is used
  for its setup. It ensures that all controller nodes trust the
  intermediate CA from the root Vault.

The dual Vault setup provides an additional layer of security for our PKI management,
as it lessens the risk of a complete system compromise if one Vault instance is breached.

Prerequisites
=============

Before beginning the deployment of vault for openstack internal TLS and backend TLS  you should ensure that you have the following.

  * StackHPC Hashicorp collection
  * Seed Node or a host to run the vault container on

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
       version: 2.2.0

2. Perform a control host upgrade to pull down the collection

.. code-block::

   kayobe control host upgrade

Setup Vault on the seed node
----------------------------

1. Run vault-deploy-seed.yml custom playbook

.. code-block::

   kayobe playbook run ansible/vault-deploy-seed.yml

2. Encrypt generated certs/keys with ansible-vault (use proper location of vault password file)

.. code-block::

   ansible-vault encrypt --vault-password-file ~/vault.pass vault/OS-TLS-INT.pem
   ansible-vault encrypt --vault-password-file ~/vault.pass vault/seed-vault-keys.json
   ansible-vault encrypt --vault-password-file ~/vault.pass vault/overcloud.key

Setup HAProxy config for Vault
------------------------------

1. Create the HAProxy config to reverse proxy the Vault HA container

Set the vault_front to the external VIP address or internal VIP address depending on the installation. Set the vault_back to the IPs of the control nodes.
Set the following in etc/kayobe/kolla/config/haproxy/services.d/vault.cfg or if environments are being used etc/kayobe/environments/$KAYOBE_ENVIRONMENT/kolla/config/haproxy/services.d/vault.cfg

.. code-block::

   # Delete "verify none" if not using self-signed/unknown issuer
   {% raw %}
   frontend vault_front
      mode tcp
      option tcplog
      bind {{ kolla_internal_vip_address }}:8200
      default_backend vault_back

   backend vault_back
      mode tcp
      option httpchk GET /v1/sys/health
      # https://www.vaultproject.io/api-docs/system/health
      # 200: initialized, unsealed, and active
      # 501: not initialised (required for bootstrapping)
      # 503: sealed (required for bootstrapping)
      http-check expect rstatus (200|501|503)

   {% for host in groups['control'] %}
   {% set host_name = hostvars[host].ansible_facts.hostname %}
   {% set host_ip = 'api' | kolla_address(host) %}
      server {{ host_name }} {{ host_ip }}:8200 check check-ssl verify none inter 2000 rise 2 fall 5
   {% endfor %}
   {% endraw %}

2. Deploy HAProxy with the new Vault service configuration:

.. code-block::

   kayobe overcloud service deploy -kt haproxy

Setup Vault HA on the overcloud hosts
-------------------------------------

1. Run vault-deploy-overcloud.yml custom playbook

.. code-block::

   kayobe playbook run ansible/vault-deploy-overcloud.yml

2. Encrypt overcloud vault keys (use proper location of vault password file)

.. code-block::

   ansible-vault encrypt --vault-password-file ~/vault.pass vault/overcloud-vault-keys.json

Create the internal TLS certificates
------------------------------------

1. Run the playbook

.. code-block::

   kayobe playbook run ansible/vault-deploy-internal-tls.yml

2. Use ansible-vault to encrypt the PEM bundle in kayobe-config/etc/kayobe/kolla/certificates/haproxy-internal.pem. Commit the PEM bundle and root CA to the kayobe configuration.

.. code-block::

   ansible-vault encrypt --vault-password-file ~/vault.pass kolla/certificates/haproxy-internal.pem

Create the backend TLS certificates
-----------------------------------

1. Run the playbook

.. code-block::

   kayobe playbook run ansible/vault-deploy-backend-tls.yml

2. Use ansible-vault to encrypt the keys in kayobe-config/etc/kayobe/kolla/certificates/<controller>-key.pem. Commit the certificates and keys to the kayobe configuration.

.. code-block::

   ansible-vault encrypt --vault-password-file ~/vault.pass kolla/certificates/<controller>-key.pem

Enable the required TLS variables in kayobe and kolla
-----------------------------------------------------

1. Set the following in kayobe-config/etc/kayobe/kolla.yml or if environments are being used etc/kayobe/environments/$KAYOBE_ENVIRONMENT/kolla.yml

.. code-block::

   # Whether TLS is enabled for the internal API endpoints. Default is 'no'.
   kolla_enable_tls_internal: yes

2. Set the following in etc/kayobe/kolla/globals.yml or if environments are being used etc/kayobe/environments/$KAYOBE_ENVIRONMENT/kolla/globals.yml

.. code-block::

   # Internal TLS configuration
   # Copy the self-signed CA into the kolla containers
   kolla_copy_ca_into_containers: "yes"
   # Use the following trust store within the container
   openstack_cacert: "{{ '/etc/pki/tls/certs/ca-bundle.crt' if os_distribution in ["centos", "rocky"] else '/etc/ssl/certs/ca-certificates.crt' }}"

   # Backend TLS config
   # Enable backend TLS
   kolla_enable_tls_backend: "yes"

   # If using RabbitMQ TLS:
   rabbitmq_enable_tls: "yes"

3. Deploy backend and internal TLS

.. code-block::

   kayobe overcloud service deploy
