=========================
OpenStack Reconfiguration
=========================

Disabling a Service
===================

Ansible is oriented towards adding or reconfiguring services, but removing a
service is handled less well, because of Ansible's imperative style.

To remove a service, it is disabled in Kayobe's Kolla config, which prevents
other services from communicating with it. For example, to disable
``cinder-backup``, edit ``${KAYOBE_CONFIG_PATH}/kolla.yml``:

.. code-block:: diff

   -enable_cinder_backup: true
   +enable_cinder_backup: false

Then, reconfigure Cinder services with Kayobe:

.. code-block:: console

   kayobe# kayobe overcloud service reconfigure --kolla-tags cinder

However, the service itself, no longer in Ansible's manifest of managed state,
must be manually stopped and prevented from restarting.

On each controller:

.. code-block:: console

   kayobe# docker rm -f cinder_backup

Some services may store data in a dedicated Docker volume, which can be removed
with ``docker volume rm``.

Installing TLS Certificates
===========================

To configure TLS for the first time, we write the contents of a PEM
file to the ``secrets.yml`` file as ``secrets_kolla_external_tls_cert``.
Use a command of this form:

.. code-block:: console

   kayobe# ansible-vault edit ${KAYOBE_CONFIG_PATH}/secrets.yml --vault-password-file=<Vault password file path>

Concatenate the contents of the certificate and key files to create
``secrets_kolla_external_tls_cert``.  The certificates should be installed in
this order:

* TLS certificate for the public endpoint FQDN
* Any intermediate certificates
* The TLS certificate private key

In ``${KAYOBE_CONFIG_PATH}/kolla.yml``, set the following:

.. code-block:: yaml

   kolla_enable_tls_external: True
   kolla_external_tls_cert: "{{ secrets_kolla_external_tls_cert }}"

To apply TLS configuration, we need to reconfigure all services, as endpoint URLs need to
be updated in Keystone:

.. code-block:: console

   kayobe# kayobe overcloud service reconfigure

Alternative Configuration
-------------------------

As an alternative to writing the certificates as a variable to
``secrets.yml``, it is also possible to write the same data to a file,
``etc/kayobe/kolla/certificates/haproxy.pem``.  The file should be
vault-encrypted in the same manner as secrets.yml.  In this instance,
variable ``kolla_external_tls_cert`` does not need to be defined.

See `Kolla-Ansible TLS guide
<https://docs.openstack.org/kolla-ansible/latest/admin/tls.html>`__ for
further details.

Updating TLS Certificates
-------------------------

Check the expiry date on an installed TLS certificate from a host that can
reach the OpenStack APIs:

.. code-block:: console

   openstack# openssl s_client -connect <Public endpoint FQDN>:443 2> /dev/null | openssl x509 -noout -dates

*NOTE*: Prometheus Blackbox monitoring can check certificates automatically
and alert when expiry is approaching.

To update an existing certificate, for example when it has reached expiration,
change the value of ``secrets_kolla_external_tls_cert``, in the same order as
above.  Run the following command:

.. code-block:: console

   kayobe# kayobe overcloud service reconfigure --kolla-tags haproxy

.. _taking-a-hypervisor-out-of-service:

Taking a Hypervisor out of Service
==================================

To take a hypervisor out of Nova scheduling:

.. code-block:: console

   admin# openstack compute service set --disable \
          <Hypervisor name> nova-compute

Running instances on the hypervisor will not be affected, but new instances
will not be deployed on it.

A reason for disabling a hypervisor can be documented with the
``--disable-reason`` flag:

.. code-block:: console

   admin# openstack compute service set --disable \
          --disable-reason "Broken drive" <Hypervisor name> nova-compute

Details about all hypervisors and the reasons they are disabled can be
displayed with:

.. code-block:: console

   admin# openstack compute service list --long

And then to enable a hypervisor again:

.. code-block:: console

   admin# openstack compute service set --enable \
          <Hypervisor name> nova-compute
