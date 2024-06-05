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

To run DRM in a container, first start a container, that has a Docker volume to
host all the firmware files:

.. code-block:: bash

   docker volume create dell_firmware
   docker run --detach -v dell_firmware:/dell_firmware --name dell-drm --network host --restart always rockylinux:9.3 sleep infinity

Copy in, and then run the installer:

.. code-block:: bash

   curl -O https://dl.dell.com/FOLDER11468378M/1/DRMInstaller_3.4.5.938.bin -H 'User-Agent: Mozilla/5.0 (X11; Linux x86_64; rv:109.0) Gecko/20100101 Firefox/110.0'
   docker cp DRMInstaller_3.4.5.938.bin dell-drm:/root
   docker exec -it dell-drm bash
   cd /root
   chmod +x DRMInstaller_3.4.5.938.bin
   ./DRMInstaller_3.4.5.938.bin

Now you can run DRM, and download a new repo (customise the argument to
``--inputplatformlist`` depending on the targeted hardware):

.. code-block:: bash

   /opt/dell/dellrepositorymanager/DRM_Service.sh &
   drm --create -r=idrac_repo --inputplatformlist=R640,R6525
   drm --deployment-type=share --location=/dell_firmware -r=idrac_repo

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

   docker build --network host -t httpd:local .

Generate a self-signed cert:

.. code-block:: bash

   openssl req -x509 -nodes -days 365 -newkey rsa:2048 -keyout apache.key -out apache.crt

Run the container:

.. code-block:: bash

   docker run -d --name dell-drm-web --network host -v dell_firmware:/usr/local/apache2/htdocs/ -v $PWD/apache.crt:/usr/local/apache2/conf/server.crt -v $PWD/apache.key:/usr/local/apache2/conf/server.key docker.io/library/httpd:local

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
   [root@seed /]# drm --update -r=idrac_repo
   # check that it has iterated to a new version
   [root@seed /]# drm -li=rep

   Listing Repositories...


   Name               Latest version   Size      Last modified date
   ----               --------------   ----      -------------
   idrac_repo         1.01             4.82 GB   1/9/24 2:22 P.M

   # share the new version
   [root@seed /]# drm --deployment-type=share --location=/dell_firmware -r=idrac_repo:1.01
   [root@seed /]# ls -ltra /dell_firmware | tail -1
   -rw-r--r--   1 root root 7103842 Jan  9 14:24 idrac_repo_Catalog.xml

Then update the ``dell_drm_repo`` variable in ``drac-firmware-update.yml`` if
required.

Manually adding and update file
===============================

Clone an update package the windows format (the iDRAC knows how to process these):

.. code-block:: bash

   curl 'https://dl.dell.com/FOLDER09614074M/2/Network_Firmware_77R8T_WN64_22.36.10.10.EXE?uid=39eab3c7-5ad6-4bfc-be6e-b9d09374accd&fn=Network_Firmware_77R8T_WN64_22.36.10.10.EXE' -H 'User-Agent: Mozilla/5.0 (X11; Linux x86_64; rv:109.0) Gecko/20100101 Firefox/110.0' -O Network_Firmware_77R8T_WN64_22.36.10.10.EXE

Import it into your repo:

.. code-block:: bash

   drm --import --repository=idrac_repo:1.00 --source=/root --update-package="*.EXE"

Export the repository:

.. code-block:: bash

   drm --deployment-type=share --location=/dell_firmware -r=idrac_repo:1.02

Updating firmware versions on a Dell node
=========================================

The updated firmware versions can be applied to a Dell node using the
``drac-firmware-update.yml`` playbook.

The following command will show the list of firmware updates to be applied:

.. code-block:: bash

   kayobe playbook run $KAYOBE_CONFIG_PATH/ansible/drac-firmware-update.yml --limit <host>

The following command will apply firmware updates:

.. code-block:: bash

   kayobe playbook run $KAYOBE_CONFIG_PATH/ansible/drac-firmware-update.yml --limit <host> -e dell_drm_apply_update=true

.. note::

   The playbook will likely fail with an error if the iDRAC firmware is being
   updated, since this involves rebooting the iDRAC. Wait for the iDRAC to be
   up and run the playbook again to ensure all firmwares have been updated
   correctly.
