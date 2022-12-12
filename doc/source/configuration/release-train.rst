======================
StackHPC Release Train
======================

StackHPC provides packages and container images for OpenStack via `Ark
<https://ark.stackhpc.com>`__.

Deployments should use a local `Pulp <https://pulpproject.org/>`__ repository
server to synchronise content from Ark and serve it locally. Access to the
repositories on Ark is controlled via user accounts issued by StackHPC.

This configuration is a base, and should be merged with any existing Kayobe
configuration. It currently provides the following:

* Configuration to deploy a local Pulp service as a container on the seed
* Pulp repository definitions for CentOS Stream 8
* Playbooks to synchronise a local Pulp service with Ark
* Configuration to use the local Pulp repository mirrors on control plane hosts
* Configuration to use the local Pulp container registry on control plane hosts

This configuration defines two `Pulp distributions
<https://docs.pulpproject.org/pulpcore/workflows/promotion.html>`__ for
packages, ``development`` and ``production``. This allows packages to be
updated and tested in a development or staging environment before rolling them
out to production.

Configuration
=============

Local Pulp server
-----------------

The URL and credentials of the local Pulp server are configured in
``etc/kayobe/pulp.yml`` via ``pulp_url``, ``pulp_username`` and
``pulp_password``. In most cases, the default values should be sufficient.
An admin password must be generated and set as the value of a
``secrets_pulp_password`` variable, typically in an Ansible Vault encrypted
``etc/kayobe/secrets.yml`` file. This password will be automatically set on
Pulp startup.

StackHPC Ark
------------

The Ark pulp credentials issued by StackHPC should be configured in
``etc/kayobe/pulp.yml``, using Ansible Vault to encrypt the password:

.. code-block:: yaml

   stackhpc_release_pulp_username: <username>
   stackhpc_release_pulp_password: <password>


The distribution name for the environment should be configured as either
``development`` or ``production`` via ``stackhpc_repo_distribution`` in
``etc/kayobe/stackhpc.yml``.

Usage
=====

The local Pulp service will be deployed as a :kayobe-doc:`Seed custom container
<configuration/reference/seed-custom-containers.html>`
on next ``kayobe seed service deploy`` or ``kayobe seed service upgrade``.

The following custom playbooks are provided in ``etc/kayobe/ansible/``:

See the Kayobe :kayobe-doc:`custom playbook documentation
<custom-ansible-playbooks.html>` for information on how to run them.

* ``pulp-repo-sync.yml``: Pull packages from Ark to the local Pulp. This will
  create a new repository version (snapshot) for each repository in the local
  Pulp server when new packages are available. The new packages will not be
  available to cloud nodes until they have been published.
* ``pulp-repo-publish.yml``: Publish synchronised packages to the
  ``development`` distribution in the local Pulp. This will make synchronised
  packages available to cloud nodes using the ``development`` distribution
  (typically a development or staging environment). The new packages will not
  be available to cloud nodes using the ``production`` distribution until they
  have been promoted.
* ``pulp-repo-promote-production.yml``: Promote packages in the ``development``
  distribution to the ``production`` distribution in the local Pulp. This will
  make all packages currently available to cloud nodes using the
  ``development`` distribution also available to cloud nodes using the
  ``production`` distribution. Typically this would be done only once the new
  packages have been validated in a development or staging environment.
* ``pulp-container-sync.yml``: Pull container images from Ark to the local
  Pulp. This will create a new repository version (snapshot) for each
  repository in the local Pulp server when new image tags are available. The
  new image tags will not be available to cloud nodes until they have been
  published.
* ``pulp-container-publish.yml``: Publish synchronised container images in the
  local Pulp. This will make synchonised container images available to cloud
  nodes.

Working with pulp
=================

The `pulp CLI
<https://docs.pulpproject.org/pulp_cli/>`__  tool can be used to administer your local
pulp installation. Please follow the upstream documentation for installation
instructions.

pulp CLI tricks
---------------

Saving credentials
~~~~~~~~~~~~~~~~~~

This is useful to avoid the need to always supply your credentials when running commands
from the command line:

.. code-block:: console

    (venv-pulp) [stack@seed ~]$ pulp config create --username admin --base-url http://<pulp server>:8080 --password <password>


Troubleshooting
---------------

HTTP Error 400: Bad Request {"name":["This field must be unique."]}
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

If you have previously tried to push an image to pulp e.g for local testing, you may
see this message when you later try to run ``pulp-container-sync.yml``:

.. code-block:: console

    TASK [stackhpc.pulp.pulp_repository : Setup container repositories] *****************************
    failed: [localhost] (item=stackhpc/centos-source-prometheus-jiralert) => changed=false
    ansible_loop_var: item
    item:
      name: stackhpc/centos-source-prometheus-jiralert
      policy: on_demand
      remote_password: password
      remote_username: username
      state: present
      url: https://ark.stackhpc.com
    msg: 'HTTP Error 400: Bad Request b''{"name":["This field must be unique."]}'''

The issue is that pushing an image automatically creates a `container-push repository
<https://docs.pulpproject.org/pulp_container/restapi.html#tag/Repositories:-Container-Push>`__
which conflicts with the creation of a regular container repository of the same
name. You can resolve this conflict by deleting the distribution associated 
with the push repository using the pulp CLI:

.. code-block:: console

    (venv-pulp) [stack@seed ~]$ pulp --base-url http://<pulp server>:8080--username admin --password <password> container distribution destroy --name stackhpc/centos-source-prometheus-jiralert
    Started background task /pulp/api/v3/tasks/1f0a474a-b7c0-44b4-9ef4-ed633077f4d8/
    .Done.

HTTP Error 404: Not Found 
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

If your login credentials are incorrect, or lack the required permissions, 
you will see a 404 error during ``pulp-repo-sync.yml``:

.. code-block:: console

    TASK [stackhpc.pulp.pulp_repository : Sync RPM remotes into repositories] ****************************************************************************************************************************************
    An exception occurred during task execution. To see the full traceback, use -vvv. The error was: Exception: Task failed to complete. (failed; 404, message='Not Found', url=URL('https://ark.stackhpc.com/pulp/content/centos/8-stream/BaseOS/x86_64/os/20211122T102435'))
    failed: [localhost] (item=centos-stream-8-baseos-development) => changed=false 
      ansible_loop_var: item
      item:
        name: centos-stream-8-baseos-development
        policy: on_demand
        proxy_url: __omit_place_holder__d35452c39719f081229941a64fd2cdce1188a287
        remote_password: <password>
        remote_username: <username>
        required: true
        state: present
        sync_policy: mirror_complete
        url: https://ark.stackhpc.com/pulp/content/centos/8-stream/BaseOS/x86_64/os/20211122T102435
      msg: Task failed to complete. (failed; 404, message='Not Found', url=URL('https://ark.stackhpc.com/pulp/content/centos/8-stream/BaseOS/x86_64/os/20211122T102435')) '''

The issue can be rectified by updating the ``stackhpc_release_pulp_username``
and ``stackhpc_release_pulp_password`` variables
