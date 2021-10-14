====================
Kayobe Configuration
====================

This repository provides configuration for the `kayobe
<https://opendev.org/openstack/kayobe>`_ project. It is intended to encourage
version control of site configuration.

Kayobe enables deployment of containerised OpenStack to bare metal.

Containers offer a compelling solution for isolating OpenStack services, but
running the control plane on an orchestrator such as Kubernetes or Docker
Swarm adds significant complexity and operational overheads.

The hosts in an OpenStack control plane must somehow be provisioned, but
deploying a secondary OpenStack cloud to do this seems like overkill.

Kayobe stands on the shoulders of giants:

* OpenStack bifrost discovers and provisions the cloud
* OpenStack kolla builds container images for OpenStack services
* OpenStack kolla-ansible delivers painless deployment and upgrade of
  containerised OpenStack services

To this solid base, kayobe adds:

* Configuration of cloud host OS & flexible networking
* Management of physical network devices
* A friendly openstack-like CLI

All this and more, automated from top to bottom using Ansible.

* Documentation: https://docs.openstack.org/kayobe/latest/
* Source: https://opendev.org/openstack/kayobe
* Bugs: https://storyboard.openstack.org/#!/project/openstack/kayobe-config
* IRC: #openstack-kolla

Configuration Diff
------------------

To test what changes your config change will create on disk, you
can use the following configuration diff tool.

While typically it is executed using gitlab ci, you can do it
manually by first building a docker file for the current kayobe
version::
    cd .automation/docker/kayobe/
    docker build . -t kayobe

Then you can run this, to diff your current code against the target branch,
which in this case is cumulus/train-preprod::
    RUN_LOCAL_DOCKER_IMAGE=kayobe .automation/run-local.sh .automation/pipeline/config-diff.sh cumulus/train-preprod -- --env KAYOBE_VAULT_PASSWORD=$(< ~/.ansible-vault-password)
