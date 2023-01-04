=====
Wazuh
=====

Wazuh Manager
============= 

Provisioning an infra VM for Wazuh Manager.

From Xena, Kayobe supports `provisioning infra VMs <https://docs.openstack.org/kayobe/latest/deployment.html#infrastructure-vms>`__ . The StackHPC fork of Kayobe has backported this to Wallaby. 
The following configuration may be used as a guide. Config for infra VMs is documented `here <https://docs.openstack.org/kayobe/latest/configuration/reference/infra-vms.html>`__ .


Set the python interpreter in 
``etc/kayobe/inventory/group_vars/infra-vms/ansible-python-interpreter``:


.. code-block:: console

  ---
  # Use a virtual environment for remote operations.
  ansible_python_interpreter: "{{ virtualenv_path }}/kayobe/bin/python"


Define VM sizing in ``etc/kayobe/inventory/group_vars/wazuh-master/infra-vms``:

.. code-block:: console

  ---
  # Memory in MB.
  infra_vm_memory_mb: 16384


  # Number of vCPUs.
  infra_vm_vcpus: 8


  # Capacity of the infra VM data volume.
  infra_vm_data_capacity: "200G"

Optional: define LVM volumes ``etc/kayobe/inventory/group_vars/wazuh-master/lvm``:

.. code-block:: console

  # List of infra VM volume groups. See mrlesmithjr.manage-lvm role for
  # format.
  infra_vm_lvm_groups:
    - vgname: "data"
      disks:
        - "/dev/vdb"
      create: true
      lvnames:
        - lvname: "data"
          size: "100%VG"
          filesystem: "ext4"
          mount: true
          mntp: “/var/lib/elasticsearch”
          create: true


Define network interfaces ``etc/kayobe/inventory/group_vars/wazuh-master/network-interfaces``: 

(The following is an example - the names will depend on your particular network configuration.)

.. code-block:: console

  ---
  # Overcloud provisioning network IP information.
  provision_oc_net_interface: "ens3"


The Wazuh master may need to be exposed externally, in which case it may require another interface. 
This can be done as follows in ``etc/kayobe/inventory/group_vars/wazuh-master/network-interfaces`` , 
with the network defined in network.yml as usual.

.. code-block:: console

  infra_vm_extra_network_interfaces:
    - "extra_net"

  # External network connectivity on ens2
  extra_net_interface: "ens2"


Add group mappings to the inventory ``etc/kayobe/inventory/groups``:
####################################################################

.. code-block:: console
  # Infra VM groups.


  [hypervisors:children]
  # Group that contains all hypervisors used for infra VMs
  seed-hypervisor


  [infra-vms:children]
  wazuh-master


  [wazuh:children]
  wazuh-master


  [wazuh-master]
  # Empty group to provide declaration of wazuh-master group.


Add the wazuh master VM to the inventory ``etc/kayobe/inventory/hosts``:

.. code-block:: console

  [wazuh-master]
  os-wazuh


Follow the Kayobe instructions to `provision the VM <https://docs.openstack.org/kayobe/latest/deployment.html#infrastructure-vms>`__ and configure the host.


Deploying Wazuh Manager services
================================

Setup
================================

Add to ``etc/kayobe/ansible/requirements.yml``:

.. code-block:: console

  roles:
    - name: wazuh-ansible
      src: https://github.com/wazuh/wazuh-ansible.git
      version: version: v4.3.10


.. note::

    NOTE: 
    If using Ubuntu, the v4.1.5 version does not support OpenDistro. It requires a minimum of v4.2.0. 
    We have tested v4.2.3, with a couple of small fixes which have not yet been released. 
    It appears that the next release will include them.

.. code-block:: console

  roles:
    - name: wazuh-ansible
      src: https://github.com/stackhpc/wazuh-ansible.git
      version: v4.2.3-opendistro-ubuntu

Install the role:

``kayobe control host bootstrap``

Setup Kayobe symlinks for custom playbooks if not done already:

.. code-block:: console

  pushd etc/kayobe/ansible/
  ln -s ../../../../kayobe/ansible/filter_plugins/ filter_plugins
  ln -s ../../../../kayobe/ansible/group_vars/ group_vars
  ln -s ../../../../kayobe/ansible/test_plugins/ test_plugins
  popd

You might wish to add the following to .gitignore in kayobe-config:

.. code-block:: console

  # Wazuh
  etc/kayobe/ansible/roles/wazuh-ansible/
  etc/kayobe/ansible/vars/certificates/deps
  etc/kayobe/ansible/vars/certificates/search-guard-tlstool-1.8.zip
  etc/kayobe/ansible/vars/certificates/tools/sgtls*


Acquire the playbook:

.. code-block:: console

  pushd etc/kayobe/ansible/
  curl -O https://raw.githubusercontent.com/stackhpc/kayobe-ops/master/wazuh-manager.yml
  popd


Edit the playbook to your needs.

``vi wazuh-manager.yml``


Acquire the group variables files:

.. code-block:: console

  mkdir -p etc/kayobe/inventory/group_vars/wazuh-master/
  pushd etc/kayobe/inventory/group_vars/wazuh-master/
  curl -O https://raw.githubusercontent.com/stackhpc/kayobe-ops/master/vars/wazuh-manager.yml
  popd


Configuration
============= 

You may need to modify some of the variables, including:

* domain_name
* wazuh_manager_ip
* private_ip

Secrets
===========================

Add the following playbook to ``etc/kayobe/ansible/wazuh-secrets.yml``:

.. code-block:: console

  ---
  - hosts: localhost
    gather_facts: false
    vars:
      wazuh_secrets_path: "{{ kayobe_env_config_path }}/inventory/group_vars/wazuh/wazuh-secrets.yml"
    tasks:
      - name: install passlib[bcrypt]
        pip:
          name: passlib[bcrypt]
          virtualenv: "{{ ansible_playbook_python | dirname | dirname }}"


      - name: Include existing secrets if they exist
        include_vars: "{{ wazuh_secrets_path }}"
        ignore_errors: true


      - name: Ensure secrets directory exists
        file:
          path: "{{ wazuh_secrets_path | dirname }}"
          state: directory


      - name: Template new secrets
        template:
          src: wazuh-secrets.yml.j2
          dest: "{{ wazuh_secrets_path }}"


Create a ``etc/kayobe/ansible/templates/`` directory if it does not exist.

Add the following template to ``etc/kayobe/ansible/templates/wazuh-secrets.yml.j2``:

.. code-block:: console

  ---
  {% set wazuh_admin_pass = secrets_wazuh.wazuh_admin_pass | default(lookup('password', '/dev/null'), true) -%}
  {%- set wazuh_user_pass = secrets_wazuh.wazuh_user_pass | default(lookup('password', '/dev/null'), true) -%}


  # Secrets used by Wazuh managers and agents
  # Store these securely and use lookups here
  secrets_wazuh:
    # Wazuh agent authd pass
    authd_pass: "{{ secrets_wazuh.authd_pass | default(lookup('password', '/dev/null'), true) }}"
    # Strengthen default wazuh api user pass
    wazuh_api_users:
      - username: "wazuh"
        password: "{{ secrets_wazuh.wazuh_api_users[0].password | default(lookup('password', '/dev/null length=30' ), true) }}"
    # Elasticsearch 'admin' user pass
    opendistro_admin_password: "{{ secrets_wazuh.opendistro_admin_password | default(lookup('password', '/dev/null'), true) }}"
    # Elasticsearch 'kibanaserver' user pass
    opendistro_kibana_password: "{{ secrets_wazuh.opendistro_kibana_password | default(lookup('password', '/dev/null'), true) }}"
    # Wazuh/Kibana 'wazuh_admin' custom user pass
    wazuh_admin_pass: "{{ wazuh_admin_pass }}"
    # Wazuh/Kibana 'wazuh_admin' custom user pass has
    # bcrypt ($2y) hash
    wazuh_admin_hash: "{{ secrets_wazuh.wazuh_admin_hash | default(wazuh_admin_pass | password_hash('bcrypt'), true) }}"
    # Wazuh/Kibana 'wazuh_user' custom user pass
    # bcrypt ($2y) hash
    wazuh_user_pass: "{{ wazuh_user_pass }}"
    wazuh_user_hash: "{{ secrets_wazuh.wazuh_user_hash | default(wazuh_user_pass | password_hash('bcrypt'), true) }}"


Generate and encrypt Wazuh secrets:

.. code-block:: console

  kayobe playbook run $KAYOBE_CONFIG_PATH/ansible/wazuh-secrets.yml -e wazuh_user_pass=$(uuidgen) -e wazuh_admin_pass=$(uuidgen)
  ansible-vault encrypt --vault-password-file ~/vault.pass $KAYOBE_CONFIG_PATH/inventory/group_vars/wazuh-master/wazuh-secrets.yml


====
TLS
====

By default, Wazuh Ansible uses `wazuh-cert-tool.sh <https://documentation.wazuh.com/current/user-manual/certificates.html>`__
 to automatically
generate certificates for wazuh-indexer (previously Elasticsearch and opendistro)
and wazuh-dashbooard (previously Kibana) using a local CA. 
If the certificates directory ``etc/kayobe/ansible/vars/certificates``
does not exist, it will generate the following certificates in ``etc/kayobe/ansible/vars/certificates/certs/``
(here os-wazuh is set as ``elasticsearch_node_name`` and ``kibana_node_name``:


* Admin certificate for opendistro security
   * admin.key,  admin.pem
* Node certificate
   * os-wazuh.key,  os-wazuh.pem
* HTTP certificate for Kibana (port 5601) & Elasticsearch (port 9200)
   * os-wazuh_http.key, os-wazuh_http.pem
* Root CA certificate
   * root-ca.key  root-ca.pem



It is also possible to use externally generated certificates for wazuh-dashboard. root-ca.pem should contain the CA chain.
Those certificates can be uploaded to ``etc/kayobe/ansible/vars/custom_certificates``, 
and will replace certificates generated by wazuh. 
Certificates should have the same name scheme as those generated by wazuh (typicaly <node-name>.pem)
The key for the external certificate should be in PKCS#8 format 
(in its header it may have BEGIN PRIVATE KEY instead of BEGIN RSA PRIVATE KEY or BEGIN OPENSSH PRIVATE KEY).

Example OpenSSL rune to convert to PKCS#8:

``openssl pkcs8 -topk8 -nocrypt -in wazuh.key -out wazuh.key.pkcs8``

TODO: document how to use a local certificate. Do we need to override all certificates?

=======
Deploy
=======

Deploy Wazuh manager:

``kayobe playbook run $KAYOBE_CONFIG_PATH/ansible/wazuh-manager.yml``

If you are using the Search Guard generated certificates, 
this will result in the creation of some certificates and keys. Encrypt the keys (and remember to commit to git):


``ansible-vault encrypt --vault-password-file ~/vault.pass $KAYOBE_CONFIG_PATH/ansible/vars/certificates/certs/*.key``

Verification
==============

The Kibana portal should be accessible on port 5601 of the Wazuh
 master’s IPs (using HTTPS, with the root CA cert in ``etc/kayobe/ansible/vars/certificates/root-ca.pem``).
The first login should be as the admin (not wazuh_admin) user, 
with the opendistro_admin_password password in ``etc/kayobe/inventory/group_vars/wazuh-master/wazuh-secrets.yml``. 
This will create the necessary indices.
Log in as the wazuh_admin user, with the wazuh_admin_pass password in ``etc/kayobe/inventory/group_vars/wazuh-master/wazuh-secrets.yml``.

Troubleshooting

Logs are in ``/var/log/elasticsearch/wazuh.log``. There are also logs in the journal.

============
Wazuh agents
============

Add a playbook to deploy wazuh agent in ``etc/kayobe/ansible/wazuh-agent.yml``:

.. code-block:: console
  
  ---
  - name: Deploy Wazuh agent
    hosts: wazuh-agent
    become: yes
    tasks:
      - import_role:
          name: "wazuh-ansible/wazuh-ansible/roles/wazuh/ansible-wazuh-agent"


Add a wazuh-agent group to the inventory in ``etc/kayobe/inventory/groups``:

.. code-block:: console

  [wazuh-agent:children]
  seed
  overcloud


  [wazuh:children]
  wazuh-agent


Add some group variables for hosts in the wazuh-agent group in ``etc/kayobe/inventory/group_vars/wazuh-agent/wazuh-agent.yml``:

.. code-block:: console

  ---
  # Wazuh-Agent role configuration
  # Reference: https://documentation.wazuh.com/4.3/deploying-with-ansible/reference.html#wazuh-agent
  # Defaults: https://github.com/wazuh/wazuh-ansible/blob/4.3/roles/wazuh/ansible-wazuh-agent/defaults/main.yml


  # Wazuh-Manager IP address
  # Convenience var not used by wazuh-agent role
  wazuh_manager_address: "{{ admin_oc_net_name | net_ip(groups['wazuh-master'][0]) }}"


  # Wazuh-Manager API config
  wazuh_managers:
    - address: "{{ wazuh_manager_address }}"
      port: 1514
      protocol: tcp
      api_port: 55000


  # Wazuh-Agent authd config
  wazuh_agent_authd:
    registration_address: "{{ wazuh_manager_address }}"
    enable: true
    port: 1515
    ssl_agent_ca: null
    ssl_auto_negotiate: 'no'


  # Wazuh-Agent authd password
  authd_pass: "{{ secrets_wazuh.authd_pass }}"



You may need to modify some variables, including:

* wazuh_manager_address


Deploy the Wazuh agents:

``kayobe playbook run $KAYOBE_CONFIG_PATH/ansible/wazuh-agent.yml``

Verification
=============

The Wazuh agents should register with the Wazuh master. This can be verified via the agents page in kibana.
Download CIS benchmarks.


