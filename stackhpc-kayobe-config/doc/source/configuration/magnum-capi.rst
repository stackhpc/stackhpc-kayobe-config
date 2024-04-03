=========================
Magnum Cluster API Driver
=========================

A new driver for Magnum has been written which is an alternative to Heat (as Heat gets phased out due to maintenance burden) and instead uses the Kubernetes `Cluster API project <https://cluster-api.sigs.k8s.io>`_ to manage the OpenStack infrastructure required by Magnum clusters. The idea behind the Cluster API (CAPI) project is that infrastructure is managed using Kubernetes-style declarative APIs, which in practice means a set of Custom Resource Definitions (CRDs) and Kubernetes `operators <https://kubernetes.io/docs/concepts/extend-kubernetes/operator/>`_ to translate instances of those custom Kubernetes resources into the required OpenStack API resources. These same operators also handle resource reconciliation (i.e. when the Kubernetes custom resource is modified, the operator will make the required OpenStack API calls to reflect those changes).

The new CAPI driver and the old Heat driver are compatible and can both be active on the same deployment, and the decision of which driver is used for a given template depends on certain parameters inferred from the Magnum cluster template. For the new driver, these parameters are ``{'server_type': 'vm', 'os': 'ubuntu', 'coe': kubernetes'}``. Drivers can be enabled and disabled using the ``disabled_drivers`` parameter in the ``[drivers]`` section of ``magnum.conf``.

Deployment Prerequisites
========================

The Cluster API architecture relies on a CAPI management cluster in order to run the aforementioned Kubernetes operators which interact directly with the OpenStack APIs. The two requirements for this management cluster are:

1. It must be capable of reaching the public OpenStack APIs.

2. It must be reachable from the control plane nodes (either controllers or dedicated network hosts) on which the Magnum containers are running (so that the Magnum can reach the IP listed in the management cluster's ``kubeconfig`` file).

For testing purposes, a simple `k3s <https://k3s.io>`_ cluster would suffice. For production deployments, the recommended solution is to instead set up a separate HA management cluster in an isolated OpenStack project by leveraging the CAPI management cluster configuration used in `Azimuth <https://github.com/stackhpc/azimuth>`_. This approach will provide a resilient HA management cluster with a standard set of component versions that are regularly tested in Azimuth CI.
The general process for setting up this CAPI management cluster using Azimuth tooling is described here, but the `Azimuth operator documentation <https://stackhpc.github.io/azimuth-config/#deploying-azimuth>`_ should be consulted for additional information if required.

The diagram below shows the general architecture of the CAPI management cluster provisioned using Azimuth tooling. It consists of a Seed VM (a terraform-provisioned OpenStack VM) running a small k3s cluster (which itself is actually a CAPI management cluster but only for the purpose of managing the HA cluster) as well as a HA management cluster made up of (by default) 3 control plane VMs and 3 worker VMs. This HA cluster runs the various Kubernetes components responsible for managing Magnum tenant clusters.

.. image:: /_static/images/capi-architecture-diagram.png
   :width: 100%

The setup and configuration of a CAPI management cluster using Azimuth tooling follow a pattern that should be familiar to Kayobe operators. There is an 'upstream' `azimuth-config <https://github.com/stackhpc/azimuth-config>`_ repository which contains recommended defaults for various configuration options (equivalent to stackhpc-kayobe-config), and then each client site will maintain an independent copy of this repository which will contain site-specific configuration. Together, these upstream and site-specific configuration repositories can set or override Ansible variables for the `azimuth-ops <https://github.com/stackhpc/ansible-collection-azimuth-ops>`_ Ansible collection, which contains the playbooks required to deploy or update a CAPI management cluster (or a full Azimuth deployment).

In order to deploy a CAPI management cluster for use with Magnum, first create a copy of the upstream Azimuth config repository in the client's GitHub/GitLab. To do so, follow the instructions found in the `initial repository setup <https://stackhpc.github.io/azimuth-config/repository/#initial-repository-setup>`_ section of the Azimuth operator docs. The site-specific repository should then be encrypted following `these instructions <https://stackhpc.github.io/azimuth-config/repository/secrets/>`_ to avoid leaking any secrets (such as cloud credentials) that will be added to the configuration later on.

Next, rather than copying the ``example`` environment as recommended in the Azimuth docs, instead copy the ``capi-mgmt-example`` environment and give it a suitable site-specific name:

.. code-block:: bash

    cp -r ./environments/capi-mgmt-example ./environments/<site-specific-name>

By default, both the seed VM name and the CAPI cluster VM names will be derived by prefixing the environment name with `capi-mgmt-` so naming the environment after the cloud (e.g. `sms-lab-prod`) is recommended.

Having created this concrete environment to hold site-specific configuration, next open ``environments/<site-specific-name>/inventory/group-vars/all/variables.yml`` and, at a minimum, set the following options to the desired values for the target cloud:

.. code-block:: yaml

    infra_external_network_id: <cloud-external-network-id>
    infra_flavor_id: <seed-vm-flavor>
    capi_cluster_control_plane_flavor: <ha-cluster-control-plane-vm-flavor>
    capi_cluster_worker_flavor: <ha-cluster-worker-vm-flavor>

The comments surrounding each option in the ``variables.yml`` provide some tips on choosing sensible values (e.g. resource requirements for each flavor). In most cases, other configuration options can be left blank since they will fall back to the upstream defaults; however, if the default configuration is not suitable, the roles in `ansible-collection-azimuth-ops <https://github.com/stackhpc/ansible-collection-azimuth-ops>`_ contain a range of config variables which can be overridden in ``variables.yml`` as required. In particular, the `infra role variables <https://github.com/stackhpc/ansible-collection-azimuth-ops/blob/main/roles/infra/defaults/main.yml>`_ are mostly relevant to the seed VM configuration, and the `capi_cluster role variables <https://github.com/stackhpc/ansible-collection-azimuth-ops/blob/main/roles/capi_cluster/defaults/main.yml>`_ are relevant for HA cluster config.

.. note::

    One important distinction between azimuth-config and stackhpc-kayobe-config is that the environments in azimuth-config are `layered`. This can be seen in the ``ansible.cfg`` file for each environment, which will contain a line of the form ``inventory = <list-of-environments>`` showing the inheritance chain for variables defined in each environment. See `these docs <https://stackhpc.github.io/azimuth-config/environments/>`_ for more details.

In addition to setting the required infrastructure variables, Terraform must also be configured to use a remote state store (either GitLab or S3) for the seed VM state. To do so, follow the instructions found `here <https://stackhpc.github.io/azimuth-config/repository/opentofu/>`_.

The HA cluster also contains a deployment of `kube-prometheus-stack <https://github.com/prometheus-community/helm-charts/tree/main/charts/kube-prometheus-stack>`_ for monitoring and alerting. To send the cluster alerts to Slack, the ``alertmanager_config_slack_webhook_url`` variable should be set in ``environments/<site-specific-name>/inventory/group-vars/all/secrets.yml``. If the repository was encrypted correctly above, this file will automatically be encrypted before a git push. Run ``git-crypt status -e`` to verify that this file is included in the encrypted list before git-committing the webhook URL.

The final step before beginning deployment of the CAPI management cluster is to provide some cloud credentials. It is recommended that the CAPI management cluster is deployed in an isolated OpenStack project. After creating the target project (preferably using `openstack-config <https://github.com/stackhpc/openstack-config>`_), generate an application credential for the project using the Identity tab in Horizon and then download the corresponding ``clouds.yaml`` file and place it in ``environments/<site-specific-name>/clouds.yaml``.

To deploy the CAPI management cluster using this site-specific environment, run

.. code-block:: bash

    # Activate the environment
    ./bin/activate <site-specific-name>

    # Install or update the local Ansible Python venv
    ./bin/ensure-venv

    # Install or update Ansible dependencies
    ansible-galaxy install -f -r ./requirements.yml

    # Run the provision playbook from the azimuth-ops collection
    # NOTE: THIS COMMAND RUNS A DIFFERENT PLAYBOOK FROM
    # THE STANDARD AZIMUTH DEPLOYMENT INSTRUCTIONS
    ansible-playbook stackhpc.azimuth_ops.provision_capi_mgmt

The general running order of the provisioning playbook is the following:

- Ensure Terraform is installed locally

- Use Terraform to provision the seed VM (and create any required internal networks, volumes etc.)

- Install k3s on the seed (with all k3s data stored on the attached Cinder volume)

- Install the required components on the k3s cluster to provision the HA cluster

- Provision the HA cluster

- Install the required components on the HA cluster to manage Magnum user clusters

Once the seed VM has been provisioned, it can be accessed via SSH by running ``./bin/seed-ssh`` from the root of the azimuth-config repository. Within the seed VM, the k3s cluster and the HA cluster can both be accessed using the pre-installed ``kubectl`` and ``helm`` command line tools. Both of these tools will target the k3s cluster by default; however, the ``kubeconfig`` file for the HA cluster can be found in the seed's home directory (named e.g. ``kubeconfig-capi-mgmt-<site-specific-name>.yaml``).

.. note::

    The provision playbook is responsible for copying the HA ``kubeconfig`` to this location *after* the HA cluster is up and running. If you need to access the HA cluster while it is still deploying, the ``kubeconfig`` file can be found stored as a Kubernetes secret on the k3s cluster.

It is possible to reconfigure or upgrade the management cluster after initial deployment by simply re-running the ``provision_capi_mgmt`` playbook. However, it's preferable that most Day 2 ops (i.e. reconfigures and upgrades) be done via a CD Pipeline. See `these Azimuth docs <https://stackhpc.github.io/azimuth-config/deployment/automation/>`_ for more information.

Kayobe Config
==============

To configure the Magnum service with the Cluster API driver enabled, first ensure that your kayobe-config branch is up to date with |current_release_git_branch_name|.

Next, copy the CAPI management cluster's kubeconfig file into your stackhpc-kayobe-config environment (e.g. ``<your-skc-environment>/kolla/config/magnum/kubeconfig``). This file must be Ansible vault encrypted.

The following config should also be set in your stackhpc-kayobe-config environment:

.. code-block:: yaml
    :caption: kolla/globals.yml

    magnum_capi_helm_driver_enabled: true

To apply the configuration, run ``kayobe overcloud service reconfigure -kt magnum``.

Magnum Cluster Templates
========================

The clusters deployed by the Cluster API driver make use of the Ubuntu Kubernetes images built in the `azimuth-images <https://github.com/stackhpc/azimuth-images>`_ repository and then use `capi-helm-charts <https://github.com/stackhpc/capi-helm-charts>`_ to provide the Helm charts which define the clusters based on these images. Between them, these two repositories have CI jobs that regularly build and test images and Helm charts for the latest Kubernetes versions. It is therefore important to update the cluster templates on each cloud regularly to make use of these new releases.

Magnum templates should be defined within an existing client-specific `openstack-config <https://github.com/stackhpc/openstack-config>`_ repository. See the openstack-config `README <https://github.com/stackhpc/openstack-config?tab=readme-ov-file#magnum-cluster-templates>`_ for more details.
