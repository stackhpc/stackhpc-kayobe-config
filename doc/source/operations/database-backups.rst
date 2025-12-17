================
Database Backups
================

An OpenStack deployment includes MariaDB to be used as a database by the
OpenStack services. Kayobe has `built-in support
<https://docs.openstack.org/kayobe/latest/administration/overcloud.html#performing-database-backups>`__
for backing up this database, but these backups are just stored on one of the
OpenStack controller hosts.

We have a playbook ``tools/upload-database-backup-s3.yml`` which can be used to
upload these backups to an S3 object store. To use this, you will need:

* The endpoint of the S3 object store.

* EC2 access and secret keys to authenticate to the S3 object store.

* The name of a pre-existing bucket in the S3 object store.

These should be set as follows:

.. code-block:: yaml
   :caption: ``$KAYOBE_CONFIG_PATH/inventory/group_vars/all/mariadb-backup``

   s3_mariadb_backup_url: "<s3-endpoint>"
   s3_mariadb_backup_bucket: "<s3-bucket-name>"

.. code-block:: yaml
   :caption: ``$KAYOBE_CONFIG_PATH/environments/$KAYOBE_ENVIRONMENT/secrets.yml``

   secrets_s3_mariadb_backup_access_key: "<s3-access-key>"
   secrets_s3_mariadb_backup_secret_key: "<s3-secret-access-key"

You may also want to hook this to run after ``kayobe overcloud database
backup``:

.. code-block:: bash

   mkdir -p $KAYOBE_CONFIG_PATH/hooks/overcloud-database-backup/post.d/
   ln -s ../../../ansible/upload-database-backup-s3.yml $KAYOBE_CONFIG_PATH/hooks/overcloud-database-backup/post.d/10-upload-database-backup-s3.yml
