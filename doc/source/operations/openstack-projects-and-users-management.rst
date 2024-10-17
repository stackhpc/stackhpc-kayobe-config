=======================================
Openstack Projects and Users Management
=======================================

Projects (in OpenStack) can be defined in the ``openstack-config`` repository

To initialise the working environment for ``openstack-config``:

.. code-block:: console

   git clone <openstack-config-repository> ~/src/openstack-config
   python3 -m venv ~/venvs/openstack-config-venv
   source ~/venvs/openstack-config-venv/bin/activate
   cd ~/src/openstack-config
   pip install -U pip
   pip install -r requirements.txt
   ansible-galaxy collection install \
    -p ansible/collections \
    -r requirements.yml

To define a new project, add a new project to
``etc/openstack-config/openstack-config.yml``:

Example invocation:

.. code-block:: console

   source ~/src/kayobe-config/etc/kolla/public-openrc.sh
   source ~/venvs/openstack-config-venv/bin/activate
   cd ~/src/openstack-config
   tools/openstack-config -- --vault-password-file <vault password file path>

Deleting Users and Projects
---------------------------

Ansible is designed for adding configuration that is not present; removing
state is less easy. To remove a project or user, the configuration should be
manually removed.
