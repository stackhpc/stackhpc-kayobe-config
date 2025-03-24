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

  kayobe playbook run $KAYOBE_CONFIG_PATH/ansible/octavia-amphora-image-register.yml

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

  kayobe playbook run ${KAYOBE_CONFIG_PATH}/ansible/octavia-amphora-image-build.yml

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

  kayobe playbook run ${KAYOBE_CONFIG_PATH}/ansible/octavia-amphora-image-register.yml -e image_path="<path-to-amphora-image>"


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
