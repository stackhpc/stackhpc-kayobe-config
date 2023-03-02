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


Manually provisioned VM
-----------------------

In case where you can't use infra-vms to deploy your wazuh-manager.


VM sizing
~~~~~~~~~

.. code-block:: console

  ---
  # Memory in MB.
  memory_mb: 16384


  # Number of vCPUs.
  vcpus: 8


  # Capacity of the infra VM data volume.
  capacity: "200G"


.. note::

    NOTE: 
    Logs will be stored in /var/ossec/ so it's a good idea to make it an LVM filesystem to make it futureproof.


Network Setup
~~~~~~~~~~~~~

Your wazuh-manager VM needs to have network connection with servers which will have the wazuh-agent installed, preferably it should be in the `provision_oc_net`.

Add to ``etc/kayobe/network-allocation.yml``:

.. code-block:: console
provision_oc_net_ips:
  <wazuh.vm.hostname>: <wazuh.vm.ip>


Required ports
~~~~~~~~~~~~~~

Several services are used for the communication of Wazuh components. Below is the list of default ports used by these services.

+-----------------+-----------+----------------+------------------------------------------------+
|  Component      | Port      | Protocol       | Purpose                                        |
+=================+===========+================+================================================+
|                 | 1514      | TCP (default)  | Agent connection service                       |
+                 +-----------+----------------+------------------------------------------------+
|                 | 1514      | UDP (optional) | Agent connection service (disabled by default) |
+                 +-----------+----------------+------------------------------------------------+
| Wazuh server    | 1515      | TCP            | Agent enrollment service                       |
+                 +-----------+----------------+------------------------------------------------+
|                 | 1516      | TCP            | Wazuh cluster daemon                           |
+                 +-----------+----------------+------------------------------------------------+
|                 | 514       | UDP (default)  | Wazuh Syslog collector (disabled by default)   |
+                 +-----------+----------------+------------------------------------------------+
|                 | 514       | TCP (optional) | Wazuh Syslog collector (disabled by default)   |
+                 +-----------+----------------+------------------------------------------------+
|                 | 55000     | TCP            | Wazuh server RESTful API                       |
+-----------------+-----------+----------------+------------------------------------------------+
|                 | 9200      | TCP            | Wazuh indexer RESTful API                      |
+ Wazuh indexer   +-----------+----------------+------------------------------------------------+
|                 | 9300-9400 | TCP            | Wazuh indexer cluster communication            |
+-----------------+-----------+----------------+------------------------------------------------+
| Wazuh dashboard | 443       | TCP            | Wazuh web user interface                       |
+-----------------+-----------+----------------+------------------------------------------------+


Make sure group mappings for wazuh-master are added to the inventory ``etc/kayobe/inventory/groups``:

.. code-block:: console

  # Infra VM groups.
...
  [wazuh:children]
  wazuh-master


  [wazuh-master]
  # Empty group to provide declaration of wazuh-master group.

...

Add hosts group mappings to the inventory ``etc/kayobe/inventory/hosts``:

.. code-block:: console

[wazuh-master]
<wazuh.vm.name>


Deploying Wazuh Manager services
================================

Setup
================================

To install specific version modify wazuh-ansible entry in ``etc/kayobe/ansible/requirements.yml``:

.. code-block:: console

  roles:
    - name: wazuh-ansible
      src: https://github.com/wazuh/wazuh-ansible.git
      version: <version_number>


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

You might wish to add the following to .gitignore in kayobe-config:

.. code-block:: console

  # Wazuh
  etc/kayobe/ansible/roles/wazuh-ansible/
  etc/kayobe/ansible/vars/certificates/*
  etc/kayobe/ansible/vars/certificates/custom_certificates/*
  

Edit the playbook and variables to your needs: 

# Wazuh manager configuration

Wazuh manager playbook is located in ``etc/kayobe/ansible/wazuh-manager.yml``.
Running this playbook will:

* generate certificates for wazuh-master
* setup and deploy filebeat on wazuh-master vm
* setup and deploy wazuh-indexer on wazuh-master vm
* setup and deploy wazuh-manager on wazuh-master vm
* setup and deploy wazuh-dashboard on wazuh-master vm
* copy certificates over to wazuh-master vm

Wazuh manager variables file is located in ``etc/kayobe/inventory/group_vars/wazuh/wazuh-master/wazuh-manager``.

You may need to modify some of the variables, including:

* domain_name
* wazuh_manager_ip
* private_ip

Secrets
=======

Wazuh secrets playbook is located in ``etc/kayobe/ansible/wazuh-secrets.yml``.
Running this playbook will generate and put pertinent security items into secrets 
vault file which will be placed in ``inventory/group_vars/wazuh/wazuh-master/wazuh-secrets``.

Wazuh secrets template is located in ``etc/kayobe/ansible/templates/wazuh-secrets.yml.j2``.
It will be used by wazuh secrets playbook to generate wazuh secrets vault file.


.. code-block:: console

  kayobe playbook run $KAYOBE_CONFIG_PATH/ansible/wazuh-secrets.yml -e wazuh_user_pass=$(uuidgen) -e wazuh_admin_pass=$(uuidgen)
  ansible-vault encrypt --vault-password-file ~/vault.pass $KAYOBE_CONFIG_PATH/inventory/group_vars/wazuh/wazuh-master/wazuh-secrets


==============
TLS (optional)
==============

You can generate your own TLS certificates, otherwise skip this section.
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

If you are using the wazuh generated certificates, 
this will result in the creation of some certificates and keys (in case of custom certs adjust path to it). 
Encrypt the keys (and remember to commit to git):


``ansible-vault encrypt --vault-password-file ~/vault.pass $KAYOBE_CONFIG_PATH/ansible/vars/certificates/certs/*.key``

Verification
==============

The Wazuh portal should be accessible on port 443 of the Wazuh
master’s IPs (using HTTPS, with the root CA cert in ``etc/kayobe/ansible/vars/certificates/root-ca.pem``).
The first login should be as the admin user, 
with the opendistro_admin_password password in ``etc/kayobe/inventory/group_vars/wazuh/wazuh-master/wazuh-secrets``. 
This will create the necessary indices.

Troubleshooting

Logs are in ``/var/log/wazuh-indexer/wazuh.log``. There are also logs in the journal.

============
Wazuh agents
============

Make sure group mappings for wazuh-agent are added to the inventory ``etc/kayobe/inventory/groups``:

.. code-block:: console

  [wazuh-agent:children]
  seed
  overcloud


  [wazuh:children]
  wazuh-agent

Wazuh agent playbook is located in ``etc/kayobe/ansible/wazuh-agent.yml``.

Wazuh agent variables file is located in ``etc/kayobe/inventory/group_vars/wazuh/wazuh-agent/wazuh-agent``.

You may need to modify some variables, including:

* wazuh_manager_address

Deploy the Wazuh agents:

``kayobe playbook run $KAYOBE_CONFIG_PATH/ansible/wazuh-agent.yml``

Verification
=============

The Wazuh agents should register with the Wazuh master. This can be verified via the agents page in Wazuh Portal.
Check CIS benchmark output in agent section.

