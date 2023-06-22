=======
Octavia
=======

Building and rotating amphora images
====================================

StackHPC kayobe config contains utility playbooks to build and rotate the amphora images.
With your kayobe environment activated, you can build a new amphora image with:

.. code-block:: console

  kayobe playbook run ${KAYOBE_CONFIG_PATH}/ansible/octavia-amphora-image-build.yml

The resultant image is based on Ubuntu. By default the image will be built on the
seed, but it is possible to change the group in the ansible inventory using the
``amphora_builder_group`` variable.

To rotate the image, first activate an openrc file containing the credentials
for the octavia service account, e.g:

.. code-block:: console

  . $KOLLA_CONFIG_PATH/octavia-openrc.sh

You can then run the playbook to upload the image:

.. code-block:: console

  kayobe playbook run ${KAYOBE_CONFIG_PATH}/ansible/octavia-amphora-image-register.yml

This will rename the old image by adding a timestamp suffix, before uploading a
new image with the name, ``amphora-x64-haproxy``. Octavia should be configured
to discover the image by tag using the ``amp_image_tag`` config option. The
images are tagged with ``amphora`` to match the kolla-ansible default for
``octavia_amp_image_tag``. This prevents you needing to reconfigure octavia
when building new images.

To rollback an image update, simply delete the old image. The next newest image with
a tag matching ``amp_image_tag`` will be selected.
