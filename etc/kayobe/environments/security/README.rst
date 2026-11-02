Security stack
~~~~~~~~~~~~~~

Mixin environment that applies a security baseline to new and existing
deployments. It bundles several security-related configuration modules into a
single, opinionated environment:

* **Firewall** — firewalld is enabled on all host types (controllers, compute,
  storage, monitoring, infrastructure VMs, seed, and seed hypervisor) using the
  standardised StackHPC firewalld zones and rules. Kolla Ansible is configured
  to open ports in firewalld for services on the public API network. See
  :ref:`firewall` for details.

* **CIS benchmark hardening** — the
  ``stackhpc_enable_cis_benchmark_hardening_hook`` flag is set to ``true``,
  which means the CIS hardening playbooks run automatically as part of
  ``kayobe * host configure``. See :doc:`security-hardening` for details.

* **Walled garden** — a Squid caching proxy is enabled on the seed, and
  overcloud hosts are configured to route HTTP/HTTPS traffic through it. NTP is
  sourced from the seed node. Network connectivity checks are redirected to
  ``localhost`` so they pass in environments without external Internet access.
  See :doc:`walled-garden` for background.

* **Pulp TLS** — TLS is enabled for the local Pulp server. Certificates must be
  provided before deploying Pulp. See `Prerequisites`_ below.

Prerequisites
^^^^^^^^^^^^^

Before activating this environment, ensure the following requirements are met.

Pulp TLS certificates
"""""""""""""""""""""

TLS is enabled for Pulp. Certificates must be generated and configured before
deploying Pulp. See :ref:`openbao-pulp-tls` for the full procedure.

Pulp stack user password
""""""""""""""""""""""""

The ``pulp_stack_password`` variable is mandatory and must be set before
running any Pulp-related playbooks. Define it in a secrets file or via the
environment (never commit it to source control):

.. code-block:: yaml
   :caption: $KAYOBE_CONFIG_PATH/$KAYOBE_ENVIRONMENT/secrets.yml

   pulp_stack_password: <your-password>

Firewall network zones
""""""""""""""""""""""

Every network in ``networks.yml`` must have a zone defined. The standard
approach is to assign the internal network zone to ``trusted`` and every other
zone to the name of the network. See the :ref:`firewall` documentation and
``etc/kayobe/environments/ci-multinode/networks.yml`` for a practical example.

Consuming this environment
^^^^^^^^^^^^^^^^^^^^^^^^^^

Add the ``security`` environment to your ``.kayobe-environment`` file:

.. code-block:: yaml
   :caption: $KAYOBE_CONFIG_PATH/$KAYOBE_ENVIRONMENT/.kayobe-environment

   dependencies:
     - security

Apply host configuration to enable the firewall and CIS hardening across all
host types:

.. code-block:: console

   kayobe seed hypervisor host configure -t network,firewall
   kayobe seed host configure -t network,firewall
   kayobe infra vm host configure -t network,firewall
   kayobe overcloud host configure -t network,firewall

.. note::

   Applying the firewall for the first time carries a risk of locking yourself
   out of hosts. Read the safety guidance in :ref:`firewall` — in particular
   the sections on using the ``firewalld-watchdog.yml`` playbook and applying
   controller changes one at a time — before proceeding.

.. note::

   CIS hardening may require a reboot to take full effect. The CIS roles will
   warn you when this is necessary.

Redeploy Pulp to pick up the TLS and credential changes:

.. code-block:: console

   kayobe seed service deploy -t seed-deploy-containers -kt none
