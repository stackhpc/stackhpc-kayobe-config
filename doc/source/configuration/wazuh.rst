=====
Wazuh
=====

Wazuh Manager
=============

Provision using infra-vms
-------------------------

Provisioning an infra VM for Wazuh Manager.

From Xena, Kayobe supports :kayobe-doc:`provisioning infra VMs <deployment.html#infrastructure-vms>`. The StackHPC fork of Kayobe has backported this to Wallaby.
The following configuration may be used as a guide. Config for infra VMs is documented :kayobe-doc:`here <configuration/reference/infra-vms>`.


Set the python interpreter in
``etc/kayobe/inventory/group_vars/infra-vms/ansible-python-interpreter``:


.. code-block:: console

  ---
  # Use a virtual environment for remote operations.
  ansible_python_interpreter: "{{ virtualenv_path }}/kayobe/bin/python"


Define VM sizing in ``etc/kayobe/inventory/group_vars/wazuh-manager/infra-vms``:

.. code-block:: console

  ---
  # Memory in MB.
  infra_vm_memory_mb: 16384


  # Number of vCPUs.
  infra_vm_vcpus: 8


  # Capacity of the infra VM data volume.
  infra_vm_data_capacity: "200G"


Optional: define LVM volumes ``etc/kayobe/inventory/group_vars/wazuh-manager/lvm``:

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


Define network interfaces ``etc/kayobe/inventory/group_vars/wazuh-manager/network-interfaces``:

(The following is an example - the names will depend on your particular network configuration.)

.. code-block:: console

  ---
  # Overcloud provisioning network IP information.
  provision_oc_net_interface: "ens3"


The Wazuh manager may need to be exposed externally, in which case it may require another interface.
This can be done as follows in ``etc/kayobe/inventory/group_vars/wazuh-manager/network-interfaces`` ,
with the network defined in network.yml as usual.

.. code-block:: console

  infra_vm_extra_network_interfaces:
    - "extra_net"

  # External network connectivity on ens2
  extra_net_interface: "ens2"


Follow the Kayobe instructions to :kayobe-doc:`provision the VM <deployment.html#infrastructure-vms>` and configure the host.


Network Setup
-------------

Your wazuh-manager VM needs to have network connection with servers which will have the wazuh-agent installed, preferably it should be in the `provision_oc_net`.


Required ports
--------------

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


Manually provisioned VM
-----------------------

In case where you can’t use infra-vms to deploy your wazuh-manager VM but you want to configure
host using kayobe, there are some tips (note that depending on your setup this don’t have to always apply):

* Depending on preferences host have to be part of some group in inventory. ``infra-vms`` group still seems as best choice
  You can use ``kayobe infra vm host configure`` to configure host in this case.
  Bellow tips are based on assumption that infra-vm will be used.
* user ``stack`` with password less sudo and accessible with ssh keys needs to be present on host.
  It can be achieved in many different ways, depending on your setup.
* lvm configuration should be placed in ``host_vars/<host_name>``
* wazuh-manager host have to be part of ``infra-vms`` group (directly or as child)
* network used on host needs to be defined in ``networks.yml`` and
  if you have pre-alocated IP, it should be added to ``network-allocation.yml``.
  For example, if using host with IP 10.10.224.5 in network 10.10.224.0/24 one have to add:


``networks.yml``:

.. code-block:: console

    undercloud_admin_net_cidr: 10.10.224.0/24
    undercloud_admin_net_allocation_pool_start: 10.10.224.3
    undercloud_admin_net_allocation_pool_end: 10.10.224.200
    undercloud_admin_net_gateway: 10.10.224.254


``network-allocation.yml``:

.. code-block:: console

    undercloud_admin_net_ips:
      nesmetprd01: 10.10.224.5

Note that in this example network name is ``undercloud`` to demonstrate that this network isn't "standard" kayobe network.


Deploying Wazuh Manager services
================================

Setup
-----

To install specific version modify wazuh-ansible entry in ``etc/kayobe/ansible/requirements.yml``:

.. code-block:: console

  roles:
    - name: wazuh-ansible
      src: https://github.com/stackhpc/wazuh-ansible
      version: stackhpc

Version above was tested and verified, but there is no reason to use not different one.

Install the role:

``kayobe control host bootstrap``


Edit the playbook and variables to your needs:

Wazuh manager configuration
---------------------------

Wazuh manager playbook is located in ``etc/kayobe/ansible/wazuh-manager.yml``.
Running this playbook will:

* generate certificates for wazuh-manager
* setup and deploy filebeat on wazuh-manager vm
* setup and deploy wazuh-indexer on wazuh-manager vm
* setup and deploy wazuh-manager on wazuh-manager vm
* setup and deploy wazuh-dashboard on wazuh-manager vm
* copy certificates over to wazuh-manager vm

Wazuh manager variables file is located in ``etc/kayobe/inventory/group_vars/wazuh-manager/wazuh-manager``.

You may need to modify some of the variables, including:

* wazuh_manager_ip


.. note::

    NOTE:
    If you are using multiple environments, and you need to customise Wazuh in each environement, create override files in an appropriate directory,
    for example `etc/kayobe/environments/production/inventory/group_vars/`
    Files which values can be overridden (in context of Wazuh):
    - etc/kayobe/inventory/group_vars/wazuh/wazuh-manager/wazuh-manager
    - etc/kayobe/wazuh-manager.yml
    - etc/kayobe/inventory/group_vars/wazuh/wazuh-agent/wazuh-agent

Secrets
-------

Wazuh secrets playbook is located in ``etc/kayobe/ansible/wazuh-secrets.yml``.
Running this playbook will generate and put pertinent security items into secrets
vault file which will be placed in ``$KAYOBE_CONFIG_PATH/wazuh-secrets.yml``.
If using environments it ends up in ``$KAYOBE_CONFIG_PATH/environments/<env_name>/wazuh-secrets.yml``
Remember to encrypt!

Wazuh secrets template is located in ``etc/kayobe/ansible/templates/wazuh-secrets.yml.j2``.
It will be used by wazuh secrets playbook to generate wazuh secrets vault file.


.. code-block:: console

  kayobe playbook run $KAYOBE_CONFIG_PATH/ansible/wazuh-secrets.yml
  ansible-vault encrypt --vault-password-file ~/vault.pass $KAYOBE_CONFIG_PATH/inventory/group_vars/wazuh/wazuh-manager/wazuh-secrets


TLS (optional)
--------------

You can generate your own TLS certificates, otherwise skip this section.
By default, Wazuh Ansible uses `wazuh-cert-tool.sh <https://documentation.wazuh.com/current/user-manual/certificates.html>`__
to automatically
generate certificates for wazuh-indexer (previously Elasticsearch and opendistro)
and wazuh-dashbooard (previously Kibana) using a local CA.
If the certificates directory ``etc/kayobe/ansible/wazuh/certificates``
does not exist, it will generate the following certificates in ``etc/kayobe/ansible/wazuh/certificates/certs/``
(here os-wazuh is set as ``elasticsearch_node_name`` and ``kibana_node_name``:


* Admin certificate for opendistro security
   * admin-key.pem,  admin.pem
* Node certificate
   * os-wazuh-key.pem,  os-wazuh.pem
* HTTP certificate for wazuh-dashboard (port 5601) & wazuh-indexer (port 9200)
   * os-wazuh_http.key, os-wazuh_http.pem
* Root CA certificate
   * root-ca.key  root-ca.pem



It is also possible to use externally generated certificates for wazuh-dashboard. root-ca.pem should contain the CA chain.
Those certificates can be uploaded to ``etc/kayobe/ansible/wazuh/custom_certificates``,
and will replace certificates generated by wazuh.
Certificates should have the same name scheme as those generated by wazuh (typicaly <node-name>.pem)
The key for the external certificate should be in PKCS#8 format
(in its header it may have BEGIN PRIVATE KEY instead of BEGIN RSA PRIVATE KEY or BEGIN OPENSSH PRIVATE KEY).

Example OpenSSL rune to convert to PKCS#8:

``openssl pkcs8 -topk8 -nocrypt -in wazuh.key -out wazuh.key.pkcs8``

TODO: document how to use a local certificate. Do we need to override all certificates?

Deploy
------

Deploy Wazuh manager:

``kayobe playbook run $KAYOBE_CONFIG_PATH/ansible/wazuh-manager.yml``

If you are using the wazuh generated certificates,
this will result in the creation of some certificates and keys (in case of custom certs adjust path to it).
Encrypt the keys (and remember to commit to git):


``ansible-vault encrypt --vault-password-file ~/vault.pass $KAYOBE_CONFIG_PATH/ansible/wazuh/certificates/certs/*.key``

Verification
==============

The Wazuh portal should be accessible on port 443 of the Wazuh
manager’s IPs (using HTTPS, with the root CA cert in ``etc/kayobe/ansible/wazuh/certificates/wazuh-certificates/root-ca.pem``).
The first login should be as the admin user,
with the opendistro_admin_password password in ``$KAYOBE_CONFIG_PATH/wazuh-secrets.yml``.
This will create the necessary indices.

Troubleshooting

Logs are in ``/var/log/wazuh-indexer/wazuh.log``. There are also logs in the journal.

============
Wazuh agents
============


Wazuh agent playbook is located in ``etc/kayobe/ansible/wazuh-agent.yml``.

Wazuh agent variables file is located in ``etc/kayobe/inventory/group_vars/wazuh-agent/wazuh-agent``.

You may need to modify some variables, including:

* wazuh_manager_address

Deploy the Wazuh agents:

``kayobe playbook run $KAYOBE_CONFIG_PATH/ansible/wazuh-agent.yml``

Verification
=============

The Wazuh agents should register with the Wazuh manager. This can be verified via the agents page in Wazuh Portal.
Check CIS benchmark output in agent section.

Additional resources:
=====================

For times when you need to upgrade wazuh with elasticsearch to version with opensearch or you just need to deinstall all wazuh components:
Wazuh purge script: https://github.com/stackhpc/wazuh-server-purge
