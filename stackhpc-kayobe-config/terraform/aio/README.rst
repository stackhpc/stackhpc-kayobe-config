==========================
Terraform All in one (aio)
==========================

This Terraform configuration deploys a single VM on an OpenStack cloud, to be
used as an all-in-one Kayobe test environment.

This configuration is used in the GitHub Actions all-in-one.yml workflow for CI
testing.

Usage
=====

These instructions show how to use this Terraform configuration manually. They
assume you are running an Ubuntu host that will be used to run Terraform. The
machine should have network access to the VM that will be created by this
configuration.

Install Terraform:

.. code-block:: console

   wget -qO - terraform.gpg https://apt.releases.hashicorp.com/gpg | sudo gpg --dearmor -o /usr/share/keyrings/terraform-archive-keyring.gpg
   sudo echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/terraform-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" | sudo tee /etc/apt/sources.list.d/terraform.list
   sudo apt update
   sudo apt install docker.io terraform

Clone and initialise the Kayobe config:

.. code-block:: console

   git clone https://github.com/stackhpc/stackhpc-kayobe-config
   cd stackhpc-kayobe-config
   git submodule init
   git submodule update

Change to the terraform/aio directory:

.. code-block:: console

   cd terraform/aio

Initialise Terraform:

.. code-block:: console

   terraform init

Generate an SSH keypair:

.. code-block:: console

   ssh-keygen -f id_rsa -N ''

Create an OpenStack clouds.yaml file with your credentials to access an
OpenStack cloud. Alternatively, download one from Horizon.

.. code-block:: console

   cat << EOF > clouds.yaml
   ---
   clouds:
     sms-lab:
       auth:
         auth_url: https://api.sms-lab.cloud:5000
         username: <username>
         project_name: <project>
         domain_name: default
       interface: public
   EOF

Export environment variables to use the correct cloud and provide a password:

.. code-block:: console

   export OS_CLOUD=sms-lab
   read -p OS_PASSWORD -s OS_PASSWORD
   export OS_PASSWORD

Generate Terraform variables:

.. code-block:: console

   cat << EOF > terraform.tfvars
   ssh_public_key = "id_rsa.pub"
   aio_vm_name = "kayobe-aio"
   aio_vm_image = "overcloud-rocky-9-zed-20231013T123933"
   aio_vm_flavor = "general.v1.medium"
   aio_vm_network = "stackhpc-ipv4-geneve"
   aio_vm_subnet = "stackhpc-ipv4-geneve-subnet"
   EOF

Generate a plan:

.. code-block:: console

   terraform plan

Apply the changes:

.. code-block:: console

   terraform apply -auto-approve

Write Terraform outputs to a Kayobe config file:

.. code-block:: console

   terraform output -json > ../../etc/kayobe/environments/$KAYOBE_ENVIRONMENT/tf-outputs.yml

Change to the repository root:

.. code-block:: console

   cd ../../

Write Terraform network config:

.. code-block:: console

   cat << EOF > etc/kayobe/environments/$KAYOBE_ENVIRONMENT/tf-networks.yml

   admin_oc_net_name: admin
   admin_cidr: "{{ access_cidr.value }}"
   admin_allocation_pool_start: 0.0.0.0
   admin_allocation_pool_end: 0.0.0.0
   admin_gateway: "{{ access_gw.value }}"
   admin_bootproto: dhcp
   admin_ips:
     controller0: "{{ access_ip_v4.value }}"
   EOF

Write Terraform network interface config:

.. code-block:: console

   cat << EOF > etc/kayobe/environments/$KAYOBE_ENVIRONMENT/inventory/group_vars/controllers/tf-network-interfaces
   admin_interface: "{{ access_interface.value }}"
   EOF

Build a Kayobe image:

.. code-block:: console

   sudo DOCKER_BUILDKIT=1 docker build --file .automation/docker/kayobe/Dockerfile --tag kayobe:latest .

Use the ci-aio environment:

.. code-block:: console

   export KAYOBE_ENVIRONMENT=ci-aio

Set the Kayobe Vault password env var:

.. code-block:: console

   read -p KAYOBE_VAULT_PASSWORD -s KAYOBE_VAULT_PASSWORD
   export KAYOBE_VAULT_PASSWORD

Set the Kayobe SSH private key env var:

.. code-block:: console

   export KAYOBE_AUTOMATION_SSH_PRIVATE_KEY=$(cat terraform/aio/id_rsa)

Host configure:

.. code-block:: console

   sudo -E docker run -it --rm -v $(pwd):/stack/kayobe-automation-env/src/kayobe-config -e KAYOBE_ENVIRONMENT -e KAYOBE_VAULT_PASSWORD -e KAYOBE_AUTOMATION_SSH_PRIVATE_KEY kayobe:latest /stack/kayobe-automation-env/src/kayobe-config/.automation/pipeline/overcloud-host-configure.sh

Service deploy:

.. code-block:: console

   sudo -E docker run -it --rm -v $(pwd):/stack/kayobe-automation-env/src/kayobe-config -e KAYOBE_ENVIRONMENT -e KAYOBE_VAULT_PASSWORD -e KAYOBE_AUTOMATION_SSH_PRIVATE_KEY kayobe:latest /stack/kayobe-automation-env/src/kayobe-config/.automation/pipeline/overcloud-service-deploy.sh

Configure aio resources:

.. code-block:: console

   sudo -E docker run -it --rm -v $(pwd):/stack/kayobe-automation-env/src/kayobe-config -e KAYOBE_ENVIRONMENT -e KAYOBE_VAULT_PASSWORD -e KAYOBE_AUTOMATION_SSH_PRIVATE_KEY kayobe:latest /stack/kayobe-automation-env/src/kayobe-config/.automation/pipeline/playbook-run.sh etc/kayobe/ansible/configure-aio-resources.yml

Run Tempest:

.. code-block:: console

   mkdir -p tempest-artifacts
   sudo -E docker run -it --rm -v $(pwd):/stack/kayobe-automation-env/src/kayobe-config -v $(pwd)/tempest-artifacts:/stack/tempest-artifacts -e KAYOBE_ENVIRONMENT -e KAYOBE_VAULT_PASSWORD -e KAYOBE_AUTOMATION_SSH_PRIVATE_KEY kayobe:latest /stack/kayobe-automation-env/src/kayobe-config/.automation/pipeline/tempest.sh -e ansible_user=stack

Tempest results are in tempest-artifacts.
