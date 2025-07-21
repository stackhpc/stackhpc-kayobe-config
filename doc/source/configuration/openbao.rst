.. _openbao:

========================
OpenBao for internal PKI
========================

This document describes how to deploy OpenBao for
internal PKI purposes using the
`StackHPC Hashicorp collection <https://galaxy.ansible.com/stackhpc/hashicorp>`_

OpenBao may be used as a Certificate Authority to generate certificates for:

* OpenStack internal API
* OpenStack backend APIs
* RabbitMQ

TLS support is described in the :kolla-ansible-doc:`Kolla Ansible documentation
<admin/tls.html>` and the :kayobe-doc:`Kayobe documentation
<configuration/reference/kolla-ansible.html#tls-encryption-of-apis>`.

OpenBao may also be used as the secret store for Barbican.

Background
==========

Our OpenStack environment employs two separate OpenBao instances.
These instances manage the Public Key Infrastructure (PKI) by handling the
creation and issuance of certificates.

- The first OpenBao instance is located on the seed host.
  It handles infrastructure-level certificates, generating the root
  Certificate Authority (CA) and intermediate CA for the second OpenBao.
  The ``openbao-deploy-seed.yml`` playbook sets up this instance.

- The second OpenBao instance is within the OpenStack
  overcloud, located on the controller nodes. This instance uses the
  intermediate CA from the seed OpenBao to issue application-specific
  certificates. The ``vault-openbao-overcloud.yml`` playbook is used
  for its setup. It ensures that all controller nodes trust the
  intermediate CA from the root OpenBao.

The dual OpenBao setup enhances security by protecting the root CA's key. The more
exposed overcloud OpenBao only possesses the intermediate key, ensuring that
the root key remains secure even if the overcloud OpenBao instance is compromised.

Prerequisites
=============

Before beginning the deployment of OpenBao for openstack internal TLS and backend TLS  you should ensure that you have the following.

  * Seed Node or a host to run the vault container on
  * Overcloud controller hosts to install second vault on
  * Ansible Galaxy dependencies installed: ``kayobe control host bootstrap``
  * Python dependencies installed: ``pip install -r kayobe-config/requirements.txt``

By default OpenBao image is not synced from Docker Hub to the local
Pulp. To sync this image, set ``stackhpc_sync_openbao_images`` to ``true``.
The OpenBao deployment configuration will be automatically updated to pull images
from Pulp.

Deployment
==========

Setup OpenBao on the seed node
------------------------------

1. Run openbao-deploy-seed.yml custom playbook

   .. code-block::

      kayobe playbook run $KAYOBE_CONFIG_PATH/ansible/openbao-deploy-seed.yml

2. Encrypt generated certs/keys with ansible-vault (use proper location of vault password file)

   .. code-block::

      ansible-vault encrypt --vault-password-file ~/vault.pass $KAYOBE_CONFIG_PATH/openbao/OS-TLS-INT.pem
      ansible-vault encrypt --vault-password-file ~/vault.pass $KAYOBE_CONFIG_PATH/openbao/seed-openbao-keys.json
      ansible-vault encrypt --vault-password-file ~/vault.pass $KAYOBE_CONFIG_PATH/openbao/overcloud.key

   Or if environments are being used

   .. code-block::

      ansible-vault encrypt --vault-password-file ~/vault.pass $KAYOBE_CONFIG_PATH/environments/$KAYOBE_ENVIRONMENT/openbao/OS-TLS-INT.pem
      ansible-vault encrypt --vault-password-file ~/vault.pass $KAYOBE_CONFIG_PATH/environments/$KAYOBE_ENVIRONMENT/openbao/seed-openbao-keys.json
      ansible-vault encrypt --vault-password-file ~/vault.pass $KAYOBE_CONFIG_PATH/environments/$KAYOBE_ENVIRONMENT/openbao/overcloud.key

Setup OpenBao HA on the overcloud hosts
---------------------------------------

1. Run openbao-deploy-overcloud.yml custom playbook

   .. code-block::

      kayobe playbook run $KAYOBE_CONFIG_PATH/ansible/openbao-deploy-overcloud.yml

2. Encrypt overcloud openbao keys (use proper location of vault password file)

   .. code-block::

      ansible-vault encrypt --vault-password-file ~/vault.pass $KAYOBE_CONFIG_PATH/openbao/overcloud-openbao-keys.json

   Or if environments are being used

   .. code-block::

      ansible-vault encrypt --vault-password-file ~/vault.pass $KAYOBE_CONFIG_PATH/environments/$KAYOBE_ENVIRONMENT/openbao/overcloud-openbao-keys.json

Rotating OpenBao certificate on the overcloud hosts
---------------------------------------------------

The certificate for the overcloud OpenBao has an expiration of one or two years after the certificate was generated.
The expiration date of a certificate can be determined with ``openssl x509 -enddate -noout -in overcloud.crt``
This will be problematic if anything needs to interact with the OpenBao API such as issuing new certificates or Barbican integration.

1. Delete the old certificate:

   .. code-block::

      rm $KAYOBE_CONFIG_PATH/openbao/overcloud.crt

   Or if environments are being used

   .. code-block::

      rm $KAYOBE_CONFIG_PATH/environments/$KAYOBE_ENVIRONMENT/openbao/overcloud.crt

2. Generate a new certificate (and key):

   .. code-block::

      kayobe playbook run $KAYOBE_CONFIG_PATH/ansible/openbao-deploy-seed.yml

3. Encrypt generated key with ansible-vault (use proper location of vault password file)

   .. code-block::

      ansible-vault encrypt --vault-password-file ~/vault.pass $KAYOBE_CONFIG_PATH/openbao/overcloud.key

   Or if environments are being used

   .. code-block::

      ansible-vault encrypt --vault-password-file ~/vault.pass $KAYOBE_CONFIG_PATH/environments/$KAYOBE_ENVIRONMENT/openbao/overcloud.key

4. Copy the new certificate to the overcloud hosts. Note, if the old
   certificate has expired this will fail on the unseal step.

   .. code-block::

      kayobe playbook run $KAYOBE_CONFIG_PATH/ansible/openbao-deploy-overcloud.yml

5. Restart the containers to use the new certificate:

   .. code-block::

      kayobe overcloud host command run --command "docker restart openbao" -l controllers

6. If sealed, unseal OpenBao:

   .. code-block::

      kayobe playbook run $KAYOBE_CONFIG_PATH/ansible/openbao-unseal-overcloud.yml

Certificates generation
=======================

.. note::

   Generating certificates will fail if the OpenBao on the overcloud is sealed. This will happen whenever the openbao containers are restarted. To unseal the
   overcloud OpenBao, run:

   .. code-block::

      kayobe playbook run $KAYOBE_CONFIG_PATH/ansible/openbao-unseal-overcloud.yml

Create the external TLS certificates (testing only)
---------------------------------------------------

This method should only be used for testing. For external TLS on production systems,
See `Installing External TLS Certificates <installing-external-tls-certificates>`__.

Typically external API TLS certificates should be generated by a organisation's trusted internal or third-party CA.
For test and development purposes it is possible to use OpenBao as a CA for the external API.

1. Run the playbook

   .. code-block::

      kayobe playbook run $KAYOBE_CONFIG_PATH/ansible/openbao-generate-test-external-tls.yml

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

      kayobe playbook run $KAYOBE_CONFIG_PATH/ansible/openbao-generate-internal-tls.yml

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

      kayobe playbook run $KAYOBE_CONFIG_PATH/ansible/openbao-generate-backend-tls.yml

2. Use ansible-vault to encrypt the keys in $KAYOBE_CONFIG_PATH/kolla/certificates/<controller>-key.pem. Commit the certificates and keys to the kayobe configuration.

   .. code-block::

      ansible-vault encrypt --vault-password-file ~/vault.pass $KAYOBE_CONFIG_PATH/kolla/certificates/<controller>-key.pem

   Or if environments are being used

   .. code-block::

      ansible-vault encrypt --vault-password-file ~/vault.pass $KAYOBE_CONFIG_PATH/environments/$KAYOBE_ENVIRONMENT/kolla/certificates/<controller>-key.pem

.. _openbao-haproxy:

HAProxy integration
===================

It is possible to expose the overcloud OpenBao service via the Kolla Ansible HAProxy load balancer.
This provides a single highly available API endpoint, as well as monitoring of the OpenBao backends when combined with Prometheus.
HAProxy integration is no longer required for generating OpenStack control plane certificates, making it possible to deploy OpenBao and generate certificates before any containers have been deployed by Kolla Ansible.

1. Create the HAProxy config to reverse proxy the OpenBao HA container

   Set the openbao_front to the external VIP address or internal VIP address depending on the installation. Set the openbao_back to the IPs of the control nodes.

   Set the following in etc/kayobe/kolla/config/haproxy/services.d/openbao.cfg or if environments are being used etc/kayobe/environments/$KAYOBE_ENVIRONMENT/kolla/config/haproxy/services.d/openbao.cfg

   .. code-block::

      # Delete "verify none" if not using self-signed/unknown issuer
      {% raw %}
      frontend openbao_front
         mode tcp
         option tcplog
         bind {{ kolla_internal_vip_address }}:8200
         default_backend openbao_back

      backend openbao_back
         mode tcp
         option httpchk GET /v1/sys/health
         # https://openbao.org/api-docs/system/health/
         # 200: initialized, unsealed, and active
         # 429: standby
         http-check expect rstatus (200|429)

      {% for host in groups['control'] %}
      {% set host_name = hostvars[host].ansible_facts.hostname %}
      {% set host_ip = 'api' | kolla_address(host) %}
         server {{ host_name }} {{ host_ip }}:8200 check check-ssl verify none inter 2000 rise 2 fall 5
      {% endfor %}
      {% endraw %}

2. If HAProxy has not yet been deployed, continue to :ref:`certificates deployment <openbao-certificates>`.
   If HAProxy has been deployed, it may be redeployed with the new OpenBao service configuration:

   .. code-block::

      kayobe overcloud service deploy -kt haproxy

.. _openbao-certificates:

Certificates deployment
=======================

.. warning::

   The switch from HTTP to HTTPS during the deployment of internal/backend TLS certificates can temporarily disrupt service availability and necessitates a restart of all services. During this transition, endpoints may become unreachable following the HAProxy restart, persisting until the endpoint catalogue and client have been reconfigured to use HTTPS.

Enable the required TLS variables in kayobe and kolla
-----------------------------------------------------

1. If using OpenBao as a CA for the external API, set the following in kayobe-config/etc/kayobe/kolla.yml or if environments are being used etc/kayobe/environments/$KAYOBE_ENVIRONMENT/kolla.yml

   .. code-block::

      # Whether TLS is enabled for the external API endpoints. Default is 'no'.
      kolla_enable_tls_external: yes
      kolla_public_openrc_cacert: "{{ '/etc/pki/tls/certs/ca-bundle.crt' if os_distribution in ['centos', 'rocky'] else '/etc/ssl/certs/ca-certificates.crt' }}"

   See :ref:`tempest-cacert` for information on adding CA certificates to the trust store when running Tempest.

2. Set the following in kayobe-config/etc/kayobe/kolla.yml or if environments are being used etc/kayobe/environments/$KAYOBE_ENVIRONMENT/kolla.yml

   .. code-block::

      # Whether TLS is enabled for the internal API endpoints. Default is 'no'.
      kolla_enable_tls_internal: yes
      kolla_admin_openrc_cacert: "{{ '/etc/pki/tls/certs/ca-bundle.crt' if os_distribution in ['centos', 'rocky'] else '/etc/ssl/certs/ca-certificates.crt' }}"

   See :ref:`os-capacity` for information on adding CA certificates to the trust store when deploying the OpenStack Capacity exporter.

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

Barbican integration depends on :ref:`HAProxy integration <openbao-haproxy>`.

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

Create required configuration in OpenBao
----------------------------------------

1. Run openbao-deploy-barbican.yml custom playbook

   .. code-block::

      kayobe playbook run $KAYOBE_CONFIG_PATH/ansible/openbao-deploy-barbican.yml

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
      vault_url = https://{{ kolla_internal_fqdn }}:8200
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
