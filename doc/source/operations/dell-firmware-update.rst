===============================
Dell Firmware Update Automation
===============================

Overview
========

Custom playbooks are available to automate firmware updates on Dell hardware.

We make use of `Dell Repository Manager (DRM)
<https://www.dell.com/support/kbdoc/en-uk/000177083/support-for-dell-emc-repository-manager-drm>`__.

Prerequisites
=============

DRM needs to listen on port 443 and needs access to the out-of-band management
network. Choose a host where it won't conflict with another service.

Use the provided Dockerfile to build a container image that runs Dell Repository Manager.

.. code-block:: bash

   cd tools/dell/drm
   docker build --network host --tag drm:3.5.0.76 .

To run DRM in a container, first start a container, that has a Docker volume to
host all the firmware files:

.. code-block:: bash

   docker volume create dell_firmware
   docker run --detach --name dell-drm --network host --restart always --volume dell_firmware:/dell_firmware drm:3.5.0.76

Now download a new repo (customise the argument to ``--inputplatformlist``
depending on the targeted hardware) and share it:

.. code-block:: bash

   drm --create --inputplatformlist=R640,R6525 --repository=idrac_repo
   drm --deployment-type=share --location=/dell_firmware --repository=idrac_repo

Note: sometimes the create call had to be run multiple times before it worked,
with errors relating to ``Unknown platform: R6525``. Restarting the service
might be required.

Now we have the all the files in the Docker volume, we can start Apache to
expose the repo. Use this Dockerfile to support TLS:

.. code-block:: dockerfile

   FROM httpd:2.4

   RUN sed -i \
       -e 's/^#\(Include .*httpd-ssl.conf\)/\1/' \
       -e 's/^#\(LoadModule .*mod_ssl.so\)/\1/' \
       -e 's/^#\(LoadModule .*mod_socache_shmcb.so\)/\1/' \
       -e 's/Listen 80/#Listen 80/' \
       conf/httpd.conf

Build a Docker image:

.. code-block:: bash

   cd tools/dell/drm-web
   docker build --network host --tag httpd:local .

Generate a self-signed cert:

.. code-block:: bash

   openssl req -x509 -nodes -days 365 -newkey rsa:2048 -keyout apache.key -out apache.crt

Run the container:

.. code-block:: bash

   docker run --detach --name dell-drm-web --network host --volume dell_firmware:/usr/local/apache2/htdocs/ --volume $PWD/apache.crt:/usr/local/apache2/conf/server.crt --volume $PWD/apache.key:/usr/local/apache2/conf/server.key httpd:local

.. note::

   At this point the repository may contain only old version of the firmwares.
   Run an update once to make sure the latest files are available (see next
   section).

Updating the Repo
=================

At a later date we will want to re-baseline to a new version. The repo
can be updated:

.. code-block:: bash

   docker exec -it dell-drm bash
   [root@seed /]# drm --update --repository=idrac_repo
   # check that it has iterated to a new version
   [root@seed /]# drm -li=rep

   Listing Repositories...


   Name               Latest version   Size      Last modified date
   ----               --------------   ----      -------------
   idrac_repo         1.01             4.82 GB   1/9/24 2:22 P.M

   # share the new version
   [root@seed /]# drm --deployment-type=share --location=/dell_firmware --repository=idrac_repo:1.01
   [root@seed /]# ls -ltra /dell_firmware | tail -1
   -rw-r--r--   1 root root 7103842 Jan  9 14:24 idrac_repo_Catalog.xml

Then update the ``dell_drm_repo`` variable in ``drac-firmware-update.yml`` if
required.

Manually adding an update file
==============================

It is possible to add specific update packages to the repository, without doing
a full sync. This can be useful for operators who want to change only specific
firmwares.

Clone an update package in the Windows format (the iDRAC knows how to process
these):

.. code-block:: bash

   curl 'https://dl.dell.com/FOLDER09614074M/2/Network_Firmware_77R8T_WN64_22.36.10.10.EXE?uid=39eab3c7-5ad6-4bfc-be6e-b9d09374accd&fn=Network_Firmware_77R8T_WN64_22.36.10.10.EXE' -H 'User-Agent: Mozilla/5.0 (X11; Linux x86_64; rv:109.0) Gecko/20100101 Firefox/110.0' -O Network_Firmware_77R8T_WN64_22.36.10.10.EXE

Import it into your repo:

.. code-block:: bash

   drm --import --repository=idrac_repo:1.00 --source=/root --update-package="*.EXE"

Export the repository:

.. code-block:: bash

   drm --deployment-type=share --location=/dell_firmware --repository=idrac_repo:1.02

Updating firmware versions on a Dell node
=========================================

The updated firmware versions can be applied to a Dell node using the
``maintenance/drac-firmware-update.yml`` playbook.

The following command will show the list of firmware updates to be applied:

.. code-block:: bash

   kayobe playbook run $KAYOBE_CONFIG_PATH/ansible/maintenance/drac-firmware-update.yml --limit <host>

The following command will apply firmware updates:

.. code-block:: bash

   kayobe playbook run $KAYOBE_CONFIG_PATH/ansible/maintenance/drac-firmware-update.yml --limit <host> -e dell_drm_apply_update=true

.. note::

   The playbook will likely fail with an error if the iDRAC firmware is being
   updated, since this involves rebooting the iDRAC. Wait for the iDRAC to be
   up and run the playbook again to ensure all firmwares have been updated
   correctly.

There is also a ``maintenance/drac-firmware-inventory.yml`` playbook to collect
an inventory of all the firmware versions currently in use.
