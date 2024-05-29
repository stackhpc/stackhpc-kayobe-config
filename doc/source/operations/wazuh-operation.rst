=======================
Wazuh Security Platform
=======================

`Wazuh <https://wazuh.com>`_ is a security monitoring platform.
It monitors for:

* Security-related system events.
* Known vulnerabilities (CVEs) in versions of installed software.
* Misconfigurations in system security.

One method for deploying and maintaining Wazuh is the `official
Ansible playbooks <https://github.com/wazuh/wazuh-ansible>`_.  These
can be integrated into ``kayobe-config`` as a custom playbook.

Configuring Wazuh Manager
=========================

Wazuh Manager is configured by editing the ``wazuh-manager.yml``
groups vars file found at
``etc/kayobe/inventory/group_vars/wazuh-manager/``.  This file
controls various aspects of Wazuh Manager configuration.
Most notably:

*domain_name*:
    The domain used by Search Guard CE when generating certificates.

*wazuh_manager_ip*:
    The IP address that the Wazuh Manager shall reside on for communicating with the agents.

*wazuh_manager_connection*:
    Used to define port and protocol for the manager to be listening on.

*wazuh_manager_authd*:
    Connection settings for the daemon responsible for registering new agents.

Running ``kayobe playbook run
$KAYOBE_CONFIG_PATH/ansible/wazuh-manager.yml`` will deploy these
changes.

Secrets
-------

Wazuh requires that secrets or passwords are set for itself and the services with which it communiticates.
The playbook ``etc/kayobe/ansible/wazuh-secrets.yml`` automates the creation of these secrets, which should then be encrypted with Ansible Vault.

To update the secrets you can execute the following two commands

.. code-block:: shell

    kayobe# kayobe playbook run $KAYOBE_CONFIG_PATH/ansible/wazuh-secrets.yml \
        -e wazuh_user_pass=$(uuidgen) \
        -e wazuh_admin_pass=$(uuidgen)
    kayobe# ansible-vault encrypt --vault-password-file <Vault password file path> \
        $KAYOBE_CONFIG_PATH/inventory/group_vars/wazuh-manager/wazuh-secrets.yml

Once generated, run ``kayobe playbook run $KAYOBE_CONFIG_PATH/ansible/wazuh-manager.yml`` which copies the secrets into place.

.. note:: Use ``ansible-vault`` to view the secrets:

  ``ansible-vault view --vault-password-file ~/vault.password $KAYOBE_CONFIG_PATH/inventory/group_vars/wazuh-manager/wazuh-secrets.yml``

Adding a New Agent
------------------
The Wazuh Agent is deployed to all hosts in the ``wazuh-agent``
inventory group, comprising the ``seed`` group
plus the ``overcloud`` group (containing all hosts in the
OpenStack control plane).

.. code-block:: ini

    [wazuh-agent:children]
    seed
    overcloud

The following playbook deploys the Wazuh Agent to all hosts in the
``wazuh-agent`` group:

.. code-block:: shell

  kayobe playbook run $KAYOBE_CONFIG_PATH/ansible/wazuh-agent.yml

The hosts running Wazuh Agent should automatically be registered
and visible within the Wazuh Manager dashboard.

.. note:: It is good practice to use a `Kayobe deploy hook
  <https://docs.openstack.org/kayobe/wallaby/custom-ansible-playbooks.html#hooks>`_
  to automate deployment and configuration of the Wazuh Agent
  following a run of ``kayobe overcloud host configure``.
