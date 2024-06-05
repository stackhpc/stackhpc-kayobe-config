================================
Hashicorp Vault for internal PKI
================================

This document describes how to deploy Hashicorp Vault for
internal PKI purposes using the
`StackHPC Hashicorp collection <https://galaxy.ansible.com/stackhpc/hashicorp>`_

Vault may be used as a Certificate Authority to generate certificates for:

* OpenStack internal API
* OpenStack backend APIs
* RabbitMQ

TLS support is described in the :kolla-ansible-doc:`Kolla Ansible documentation
<admin/tls.html>` and the :kayobe-doc:`Kayobe documentation
<configuration/reference/kolla-ansible.html#tls-encryption-of-apis>`.

Vault may also be used as the secret store for Barbican.

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
  intermediate CA from the seed Vault to issue application-specific
  certificates. The ``vault-deploy-overcloud.yml`` playbook is used
  for its setup. It ensures that all controller nodes trust the
  intermediate CA from the root Vault.

The dual Vault setup enhances security by protecting the root CA's key. The more
exposed overcloud vault only possesses the intermediate key, ensuring that
the root key remains secure even if the overcloud Vault instance is compromised.

Prerequisites
=============

Before beginning the deployment of vault for openstack internal TLS and backend TLS  you should ensure that you have the following.

  * Seed Node or a host to run the vault container on
  * Overcloud controller hosts to install second vault on
  * Ansible Galaxy dependencies installed: ``kayobe control host bootstrap``
  * Python dependencies installed: ``pip install -r kayobe-config/requirements.txt``

By default, Consul and Vault images are not synced from Docker Hub to the local
Pulp. To sync these images, set ``stackhpc_sync_hashicorp_images`` to ``true``.
The Vault deployment configuration will be automatically updated to pull images
from Pulp.

Deployment
==========

Setup Vault on the seed node
----------------------------

1. Run vault-deploy-seed.yml custom playbook

   .. code-block::

      kayobe playbook run $KAYOBE_CONFIG_PATH/ansible/vault-deploy-seed.yml

2. Encrypt generated certs/keys with ansible-vault (use proper location of vault password file)

   .. code-block::

      ansible-vault encrypt --vault-password-file ~/vault.pass $KAYOBE_CONFIG_PATH/vault/OS-TLS-INT.pem
      ansible-vault encrypt --vault-password-file ~/vault.pass $KAYOBE_CONFIG_PATH/vault/seed-vault-keys.json
      ansible-vault encrypt --vault-password-file ~/vault.pass $KAYOBE_CONFIG_PATH/vault/overcloud.key

   Or if environments are being used

   .. code-block::

      ansible-vault encrypt --vault-password-file ~/vault.pass $KAYOBE_CONFIG_PATH/environments/$KAYOBE_ENVIRONMENT/vault/OS-TLS-INT.pem
      ansible-vault encrypt --vault-password-file ~/vault.pass $KAYOBE_CONFIG_PATH/environments/$KAYOBE_ENVIRONMENT/vault/seed-vault-keys.json
      ansible-vault encrypt --vault-password-file ~/vault.pass $KAYOBE_CONFIG_PATH/environments/$KAYOBE_ENVIRONMENT/vault/overcloud.key

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

      kayobe overcloud service deploy --skip-tags os_capacity -kt haproxy

Setup Vault HA on the overcloud hosts
-------------------------------------

1. Run vault-deploy-overcloud.yml custom playbook

   .. code-block::

      kayobe playbook run $KAYOBE_CONFIG_PATH/ansible/vault-deploy-overcloud.yml

2. Encrypt overcloud vault keys (use proper location of vault password file)

   .. code-block::

      ansible-vault encrypt --vault-password-file ~/vault.pass $KAYOBE_CONFIG_PATH/vault/overcloud-vault-keys.json

   Or if environments are being used

   .. code-block::

      ansible-vault encrypt --vault-password-file ~/vault.pass $KAYOBE_CONFIG_PATH/environments/$KAYOBE_ENVIRONMENT/vault/overcloud-vault-keys.json

Certificates generation
=======================

Create the external TLS certificates (testing only)
---------------------------------------------------

Typically external API TLS certificates should be generated by a organisation's trusted internal or third-party CA.
For test and development purposes it is possible to use Vault as a CA for the external API.

1. Run the playbook

   .. code-block::

      kayobe playbook run $KAYOBE_CONFIG_PATH/ansible/vault-generate-test-external-tls.yml

2. Use ansible-vault to encrypt the PEM bundle in $KAYOBE_CONFIG_PATH/kolla/certificates/haproxy.pem. Commit the PEM bundle to the kayobe configuration.

   .. code-block::

      ansible-vault encrypt --vault-password-file ~/vault.pass $KAYOBE_CONFIG_PATH/kolla/certificates/haproxy.pem

   Or if environments are being used

   .. code-block::

      ansible-vault encrypt --vault-password-file ~/vault.pass $KAYOBE_CONFIG_PATH/environments/$KAYOBE_ENVIRONMENT/kolla/certificates/haproxy.pem

Create the internal TLS certificates
------------------------------------

1. Run the playbook

   .. code-block::

      kayobe playbook run $KAYOBE_CONFIG_PATH/ansible/vault-generate-internal-tls.yml

2. Use ansible-vault to encrypt the PEM bundle in $KAYOBE_CONFIG_PATH/kolla/certificates/haproxy-internal.pem. Commit the PEM bundle and root CA to the kayobe configuration.

   .. code-block::

      ansible-vault encrypt --vault-password-file ~/vault.pass $KAYOBE_CONFIG_PATH/kolla/certificates/haproxy-internal.pem

   Or if environments are being used

   .. code-block::

      ansible-vault encrypt --vault-password-file ~/vault.pass $KAYOBE_CONFIG_PATH/environments/$KAYOBE_ENVIRONMENT/kolla/certificates/haproxy-internal.pem

Create the backend TLS and RabbitMQ TLS certificates
----------------------------------------------------

1. Run the playbook

   .. code-block::

      kayobe playbook run $KAYOBE_CONFIG_PATH/ansible/vault-generate-backend-tls.yml

2. Use ansible-vault to encrypt the keys in $KAYOBE_CONFIG_PATH/kolla/certificates/<controller>-key.pem. Commit the certificates and keys to the kayobe configuration.

   .. code-block::

      ansible-vault encrypt --vault-password-file ~/vault.pass $KAYOBE_CONFIG_PATH/kolla/certificates/<controller>-key.pem

   Or if environments are being used

   .. code-block::

      ansible-vault encrypt --vault-password-file ~/vault.pass $KAYOBE_CONFIG_PATH/environments/$KAYOBE_ENVIRONMENT/kolla/certificates/<controller>-key.pem

Certificates deployment
=======================

.. warning::

   The switch from HTTP to HTTPS during the deployment of internal/backend TLS certificates can temporarily disrupt service availability and necessitates a restart of all services. During this transition, endpoints may become unreachable following the HAProxy restart, persisting until the endpoint catalogue and client have been reconfigured to use HTTPS.

Enable the required TLS variables in kayobe and kolla
-----------------------------------------------------

1. If using Vault as a CA for the external API, set the following in kayobe-config/etc/kayobe/kolla.yml or if environments are being used etc/kayobe/environments/$KAYOBE_ENVIRONMENT/kolla.yml

   .. code-block::

      # Whether TLS is enabled for the external API endpoints. Default is 'no'.
      kolla_enable_tls_external: yes

   See :ref:`tempest-cacert` for information on adding CA certificates to the trust store when running Tempest.

2. Set the following in kayobe-config/etc/kayobe/kolla.yml or if environments are being used etc/kayobe/environments/$KAYOBE_ENVIRONMENT/kolla.yml

   .. code-block::

      # Whether TLS is enabled for the internal API endpoints. Default is 'no'.
      kolla_enable_tls_internal: yes

3. Set the following in etc/kayobe/kolla/globals.yml or if environments are being used etc/kayobe/environments/$KAYOBE_ENVIRONMENT/kolla/globals.yml

   .. code-block::

      # Internal TLS configuration
      # Copy the self-signed CA into the kolla containers
      kolla_copy_ca_into_containers: "yes"
      # Use the following trust store within the container
      openstack_cacert: "{{ '/etc/pki/tls/certs/ca-bundle.crt' if os_distribution == 'rocky' else '/etc/ssl/certs/ca-certificates.crt' }}"

      # Backend TLS config
      # Enable backend TLS
      kolla_enable_tls_backend: "yes"

      # If using RabbitMQ TLS:
      rabbitmq_enable_tls: "yes"

4. Deploy OpenStack

   .. warning::

      It is important that you are only using admin endpoints for keystone. If
      any admin endpoints exist for other services, they must be deleted e.g.

      .. code-block::

         openstack endpoint list --interface admin -f value | \
         awk '!/keystone/ {print $1}' | xargs openstack endpoint delete

   .. code-block::

      kayobe overcloud service deploy

   If VM provisioning fails with an error with this format:

   .. code-block::

      Unable to establish connection to http://<kolla internal vip/fqdn>:9696/v2.0/ports/some-sort-of-uuid: Connection aborted

   Restart the nova-compute container on all hypervisors:

   .. code-block::

      kayobe overcloud host command run --command "systemctl restart kolla-nova_compute-container.service" --become --show-output -l compute

Barbican integration
====================

Enable Barbican in kayobe
-------------------------

1. Set the following in kayobe-config/etc/kayobe/kolla.yml or if environments are being used etc/kayobe/environments/$KAYOBE_ENVIRONMENT/kolla.yml

   .. code-block::

      kolla_enable_barbican: yes

Generate secrets_barbican_approle_secret_id
-------------------------------------------

1. Run ``uuidgen`` to generate secret id
2. Insert into secrets.yml or if environments are being used etc/kayobe/environments/$KAYOBE_ENVIRONMENT/secrets.yml

   .. code-block::

      secrets_barbican_approle_secret_id: "YOUR-SECRET-GOES-HERE"

Create required configuration in Vault
--------------------------------------

1. Run vault-deploy-barbican.yml custom playbook

   .. code-block::

      kayobe playbook run $KAYOBE_CONFIG_PATH/ansible/vault-deploy-barbican.yml

Add secrets_barbican_approle_id to secrets
------------------------------------------

1. Note the role id from playbook output and insert into secrets.yml or if environments are being used etc/kayobe/environments/$KAYOBE_ENVIRONMENT/secrets.yml

   .. code-block::

      secrets_barbican_approle_role_id: "YOUR-APPROLE-ID-GOES-HERE"

Configure Barbican
------------------

1. Put required configuration in kayobe-config/etc/kayobe/kolla/config/barbican.conf or if environments are being used etc/kayobe/environments/$KAYOBE_ENVIRONMENT/kolla/config/barbican.conf

   .. code-block::

      [secretstore]
      namespace=barbican.secretstore.plugin
      enable_multiple_secret_stores=false
      enabled_secretstore_plugins=vault_plugin

      [vault_plugin]
      vault_url = https://{{ kolla_internal_vip_address }}:8200
      use_ssl = True
      {% raw %}
      ssl_ca_crt_file = {{ openstack_cacert }}
      {% endraw %}
      approle_role_id = {{ secrets_barbican_approle_role_id }}
      approle_secret_id = {{ secrets_barbican_approle_secret_id }}
      kv_mountpoint = barbican

Deploy Barbican
---------------

   .. code-block::

      kayobe overcloud service deploy -kt barbican
