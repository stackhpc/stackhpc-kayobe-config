=======
Octavia
=======

.. _Amphora image:

Updating amphora images
=======================

StackHPC kayobe config contains utility playbooks to update and build the amphora images.

To update the image, first activate an openrc file containing the credentials
for the octavia service account, e.g:

.. code-block:: console

  . $KOLLA_CONFIG_PATH/octavia-openrc.sh

You can then run the playbook to upload the image:

.. code-block:: console

  kayobe playbook run $KAYOBE_CONFIG_PATH/ansible/maintenance/octavia-amphora-image-register.yml

By default, this will download Amphora image corresponds to OpenStack release from
StackHPC Release Train.
Then it will rename the old image by adding a timestamp suffix, before uploading a
new image with the name, ``amphora-x64-haproxy``. Octavia should be configured
to discover the image by tag using the ``amp_image_tag`` config option. The
images are tagged with ``amphora`` to match the kolla-ansible default for
``octavia_amp_image_tag``. This prevents you needing to reconfigure octavia
when building new images.

To rollback an image update, simply delete the newest image. The next newest image with
a tag matching ``amp_image_tag`` will be selected.

Building amphora images locally
===============================

You can also build Amphora images locally.
With your kayobe environment activated, you can build a new amphora image with:

.. code-block:: console

  kayobe playbook run ${KAYOBE_CONFIG_PATH}/ansible/maintenance/octavia-amphora-image-build.yml

The resultant image is based on Ubuntu. By default the image will be built on the
seed, but it is possible to change the group in the ansible inventory using the
``amphora_builder_group`` variable.

To register locally built image, set ``download_amphora_from_ark`` to ``false`` in
``stackhpc.yml``

.. code-block:: yaml
  :caption: ``stackhpc.yml``

  # Whether or not to download Octavia Amphora image from Ark. Default is true.
  download_amphora_from_ark: false

Then copy the image to your first controller host and run the image register playbook.
The path to the image in the controller needs to be set as an extra variable.
The default image path is ``/tmp/amphora-x64-haproxy.qcow2``.

.. code-block:: console

  kayobe playbook run ${KAYOBE_CONFIG_PATH}/ansible/maintenance/octavia-amphora-image-register.yml -e image_path="<path-to-amphora-image>"

Handling TLS certificates
=========================

Octavia uses mutual TLS to secure communication between the amphorae and
Octavia services. It uses a private CA to sign both client and server
certificates. These certificates need to be generated when first deploying
Octavia, and will later need to be rotated (details below). We use the
kolla-ansible built-in support for generating these certificates:

.. code-block:: console

   kayobe kolla ansible run octavia-certificates

This command will output certificates and keys in ``${KOLLA_CONFIG_PATH}/octavia-certificates``

Copy the relevant certificates into your kayobe-config:

.. code-block:: console

   mkdir -p ${KAYOBE_CONFIG_PATH}/environments/$KAYOBE_ENVIRONMENT/kolla/config/octavia
   cd ${KAYOBE_CONFIG_PATH}/environments/$KAYOBE_ENVIRONMENT/kolla/config/octavia
   cp $KOLLA_CONFIG_PATH/octavia-certificates/client_ca/client_ca.cert.pem .
   cp $KOLLA_CONFIG_PATH/octavia-certificates/client_ca/client.cert-and-key.pem .
   cp $KOLLA_CONFIG_PATH/octavia-certificates/server_ca/server_ca.cert.pem .
   cp $KOLLA_CONFIG_PATH/octavia-certificates/server_ca/server_ca.key.pem .

Encrypt any files containing the keys:

.. code-block:: console

   ansible-vault encrypt client.cert-and-key.pem --vault-password-file ~/vault
   ansible-vault encrypt server_ca.key.pem --vault-password-file ~/vault

Checking certificate expiry
~~~~~~~~~~~~~~~~~~~~~~~~~~~

.. code-block:: console

   ansible-vault decrypt client.cert-and-key.pem --vault-password-file ~/vault
   openssl x509 -enddate -noout -in client.cert-and-key.pem

Backing up the octavia-certificates directory
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

In the root of your kayobe-config checkout:

.. code-block:: console

   tools/backup-octavia-certificates.sh

This will output an encrypted backup to ``$KAYOBE_CONFIG_PATH/environments/$KAYOBE_ENVIRONMENT/kolla/certificates/octavia-certificates-backup.tar``
Commit this file to store the backup.

.. _restoring-octavia-certificates-directory:

Restoring octavia-certificates directory when regenerating certificates
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

In the root of your kayobe-config checkout:

.. code-block:: console

   tools/restore-octavia-certificates.sh

This will use the encrypted backup in ``$KAYOBE_CONFIG_PATH/environments/$KAYOBE_ENVIRONMENT/kolla/certificates/octavia-certificates-backup.tar``
to restore ``${KOLLA_CONFIG_PATH}/octavia-certificates``. This will allow you
to reuse the client CA.

Rotating client.cert-and-key.pem
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

This has a lifetime of 1 year.

#. Follow the steps to restore octavia-certificates so you can reuse the client
   CA. See :ref:`restoring-octavia-certificates-directory`.

#. Make sure your config allows you to regenerate a certificate with the same
   common name.

   .. code-block:: console
      :caption: $KOLLA_CONFIG_PATH/octavia-certificates/client_ca/index.txt.attr

      unique_subject = no

#. Remove the old files relating to the client certificate:

   .. code-block:: console

      rm $KOLLA_CONFIG_PATH/octavia-certificates/client_ca/{client.cert-and-key.pem,client.csr.pem,client.cert.pem}

#. Regenerate the certificates

   .. code-block:: console

      kayobe kolla ansible run octavia-certificates

#. Backup your octavia-certificates directory (see previous section).

#. Copy your new certificate to the correct location:

   .. code-block:: console

      cd ${KAYOBE_CONFIG_PATH}/environments/$KAYOBE_ENVIRONMENT/kolla/config/octavia
      cp  $KOLLA_CONFIG_PATH/octavia-certificates/client_ca/client_ca.cert.pem .
      cp  $KOLLA_CONFIG_PATH/octavia-certificates/client_ca/client.cert-and-key.pem .
      ansible-vault encrypt client.cert-and-key.pem --vault-password-file ~/vault

#. Reconfigure Octavia

   .. code-block:: console

      kayobe overcloud service reconfigure -kt octavia

#. Run Tempest with the `octavia` test list to check it is working. See
   :ref:`running_tempest_with_kayobe_automation`.

#. Commit and push any changes.

Rotating the CAs
~~~~~~~~~~~~~~~~

The CAs have a 10 year lifetime. Simply delete the relevant directory under
``$KOLLA_CONFIG_PATH/octavia-certificates/`` and regenerate it with:

   .. code-block:: console

      kayobe kolla ansible run octavia-certificates

Copy the relevant certificates into your kayobe-config.

.. code-block:: console

   cd ${KAYOBE_CONFIG_PATH}/environments/$KAYOBE_ENVIRONMENT/kolla/config/octavia
   cp $KOLLA_CONFIG_PATH/octavia-certificates/client_ca/client_ca.cert.pem .
   cp $KOLLA_CONFIG_PATH/octavia-certificates/client_ca/client.cert-and-key.pem .
   cp $KOLLA_CONFIG_PATH/octavia-certificates/server_ca/server_ca.cert.pem .
   cp $KOLLA_CONFIG_PATH/octavia-certificates/server_ca/server_ca.key.pem .

Encrypt any files containing the keys.

.. code-block:: console

   ansible-vault encrypt client.cert-and-key.pem --vault-password-file ~/vault
   ansible-vault encrypt server_ca.key.pem --vault-password-file ~/vault

Follow any instructions in the `upstream docs <https://docs.openstack.org/octavia/latest/admin/guides/operator-maintenance.html>`_.

Manually deleting broken load balancers
=======================================

Sometimes, a load balancer will get stuck in a broken state of ``PENDING_CREATE`` or ``PENDING_UPDATE``.
When in this state, the load balancer cannot be deleted; you will see the error ``Invalid state PENDING_CREATE of loadbalancer resource``.
To delete a load balancer in this state, you will need to manually update its provisioning status in the database.

Find the database password:

.. code-block:: console

  ansible-vault view --vault-password-file <path-to-vault-pw> $KOLLA_CONFIG_PATH/passwords.yml

  # Search for database_password with:
  /^database

Access the database from a controller:

.. code-block:: console

  docker exec -it mariadb bash
  mysql -u root -p  octavia
  # Enter the database password when prompted.

List the load balancers to find the ID of the broken one(s):

.. code-block:: console

  SELECT * FROM load_balancer;

Set the provisioning status to ERROR for any broken load balancer:

.. code-block:: console

  UPDATE load_balancer SET provisioning_status='ERROR' WHERE id='<id>';

Delete the load balancer from the OpenStack CLI, cascading if any stray
Amphorae are hanging around:

.. code-block:: console

  openstack loadbalancer delete <id> --cascade


Sometimes, Amphora may also fail to delete if they are stuck in state
``BOOTING``. These can be resolved entirely from the OpenStack CLI:

.. code-block:: console

  openstack loadbalancer amphora configure <amphora-id>
  openstack loadbalancer amphora delete <amphora-id>
