=====
CI/CD
=====

Concepts
========

The CI/CD system developed for managing Kayobe based OpenStack clouds is composed of four main components; workflows, runners, OpenBao and kayobe automation.

Firstly, the workflows are files which describe a series of tasks to be performed in relation to the deployed cloud.
These workflows are executed on request, on schedule or in response to an event such as a pull request being opened.

The workflows are designed to carry out various day-to-day activites such as; running Tempest tests, configuring running services or displaying the change to configuration files if a pull request is merged.
Secondly, in order for the workflows to run against a cloud we would need private runners present within the cloud positioned in such a way they can reach the internal network and public API.
Deployment of private runners is supported by all major providers with the use of community developed Ansible roles.

Thirdly, OpenBao is used to store secrets on the same virtual machine the runners are hosted within.
This provides a secure way of storing secrets and variables which can be accessed by the runners when executing workflows and ensures that secrets never have to leave the cloud.

Finally, due to the requirement that we support various different platforms tooling in the form of `Kayobe automation <https://github.com/stackhpc/kayobe-automation/>`__ was developed.
This tooling is not tied to any single CI/CD platform as all tasks are a series of shell script and Ansible playbooks which are designed to run in a purpose build kayobe container.

This is complemented by the use of an Ansible collection known as `stackhpc.kayobe_workflows <https://github.com/stackhpc/ansible-collection-kayobe-workflows/>`__ which aims to provide users with a quick and easy way of customising all workflows to fit within a customer's cloud.

Currently we support the creation and deployment of workflows for GitHub with Gitlab support being actively worked upon.

Kayobe Automation
-----------------

`Kayobe automation <https://github.com/stackhpc/kayobe-automation/>`__ is a collection of scripts and tools that automate kayobe operations.
It is deployed and controlled by CI/CD platforms such as GitHub actions and GitLab pipelines.
Kayobe automation provides users with an easy process to perform tasks such as: overcloud service deploy, config-diff, tempest testing, and many more.
With it being integrated into platforms such as GitHub or GitLab it builds a close relationship between the contents of the deployments kayobe configuration and what is currently deployed.
This is because operations such as opening a pull request will trigger a config diff to be generated providing insight on what impact it might have on services or a tempest test that could be scheduled to run daily providing knowledge of faults earlier than before.

Workflows
---------

Kayobe automation has been designed to be independent of any CI/CD platform with all tasks running inside of a purpose built Kayobe container.
However, platform specific workflows need to be deployed to bridge the gap between the contents of Kayobe Automation and these CI/CD platforms.
Workflows are templated for each Kayobe configuration repository, ensuring appropriate workflow input parameters are defined, and any necessary customisations can be applied.
The templating of workflows is offered through the `stackhpc.kayobe_workflows <https://github.com/stackhpc/ansible-collection-kayobe-workflows/>`__ collection which currently supports GitHub workflows.

Runners
-------

Runners are purpose built services tied to a particular service vendor such as GitHub Actions or GitLab CI.
These services will listen for jobs which have been tagged appropriately and dispatched to these specific runners.
The runners will need to be deployed using existing roles and playbooks whereby the binary/package is downloaded and registered using a special token.
In some deployments runner hosts can be shared between environments however this is not always true and dedicated hosts will need to be used for each environment you intend to deploy kayobe automation within.

OpenBao
-------

OpenBao is recommended when deploying kayobe automation to achieve a simple and secure way of storing secrets.
OpenBao can easily be configured to hold the secrets for all environments and only permit access to the runners which require them utilising different authorisation mechanisms such as GitLab's JWT (JSON Web Token).

GitHub Actions
=================

To enable CI/CD where GitHub Actions is used please follow the steps described below starting with the deployment of the runners.

Runner Deployment
-----------------

1. Identify a suitable host for hosting the runners.
    GitHub runners need to be deployed on a host which has not had Docker deployed using kolla.
    This is because GitHub runners cannot provide `network options when running in a container <https://docs.github.com/en/actions/using-workflows/workflow-syntax-for-github-actions#jobsjob_idcontaineroptions>`__.

    Ideally an Infra VM could be used here or failing that the control host.
    Wherever it is deployed the host will need access to the :code:`admin_network`, :code:`public_network` and the :code:`pulp registry` on the seed.

2. Edit the environment's :code:`$KAYOBE_CONFIG_PATH/environments/$KAYOBE_ENVIRONMENT/inventory/groups` to add the predefined :code:`github-runners` group to :code:`infra-vms`

.. code-block:: ini

    [infra-vms:children]
    github-runners

3. Edit the environment's :code:`$KAYOBE_CONFIG_PATH/environments/$KAYOBE_ENVIRONMENT/inventory/hosts` to define the host(s) that will host the runners.

.. code-block:: ini

    [github-runners]
    prod-runner-01

4. Provide all the relevant Kayobe :code:`group_vars` for :code:`github-runners` under :code:`$KAYOBE_CONFIG_PATH/environments/$KAYOBE_ENVIRONMENT/inventory/group_vars/github-runners`
    * `infra-vms` ensuring all required `infra_vm_extra_network_interfaces` are defined
    * `network-interfaces`
    * `python-interpreter.yml` ensuring that `ansible_python_interpreter: /usr/bin/python3` has been set

5. Edit the ``$KAYOBE_CONFIG_PATH/inventory/group_vars/github-runners/runners.yml`` file which will contain the variables required to deploy a series of runners.
   Below is a core set of variables that will require consideration and modification for successful deployment of the runners.
   The number of runners deployed can be configured by removing and extending the dict :code:`github-runners`.
   As for how many runners present three is suitable number as this would prevent situations where long running jobs could halt progress other tasks whilst waiting for a free runner.
   You might want to increase the number of runners if usage demands it or new workflows make use of multiple parallel jobs.

   Note :code:`github_registry` and the elements of the dict control the registry settings for pulling and pushing container images used by the workflows.
   In the example below the registry settings have been adapted to demonstrate what a shared registry between environments might look like.
   This values maybe suitable for your deployment providing all environments can reach the same registry.
   If the all of the environments use their own registry and nothing is shared between them then :code:`github_registry` can omitted from the file and the template will expect environment specific secrets and variables to be added to the repository settings.
   This is discussed further in the next section.

.. code-block:: yaml

    ---
    runner_user: VM_USER_NAME_HERE
    github_account: ORG_NAME_HERE
    github_repo: KAYOBE_CONFIG_REPO_NAME_HERE
    access_token: "{{ secrets_github_access_token }}"

    default_runner_labels:
      - kayobe
      - openstack
      - "{{ kayobe_environment | default(omit) }}"

    github_registry:
      url: pulp.example.com
      username: admin
      password: ${{ secrets.REGISTRY_PASSWORD }}
      share: true

    github_runners:
      runner_01: {}
      runner_02: {}
      runner_03: {}

6. Obtain a personal access token that would enable the registration of GitHub runners against the `github_account` and `github_repo` defined above.
    This token ideally should be `fine-grained personal access token <https://docs.github.com/en/authentication/keeping-your-account-and-data-secure/managing-your-personal-access-tokens#creating-a-fine-grained-personal-access-token>`__ which may require the organisation to enable such tokens beforehand.
    Steps can be found `here <https://docs.github.com/en/organizations/managing-programmatic-access-to-your-organization/setting-a-personal-access-token-policy-for-your-organization>`__.
    The repository permissions for a fine-grained personal access token should be; :code:`Actions: R/W, Administration: R/W, Metadata: R`
    Once the key has been obtained, add it to :code:`secrets.yml` under :code:`secrets_github_access_token`

7. If the host is an actual Infra VM then please refer to upstream :kayobe-doc:`Infrastructure VMs <configuration/reference/infra-vms.html>` documentation for additional configuration and steps.

8. Run :code:`kayobe playbook run $KAYOBE_CONFIG_PATH/ansible/deployment/deploy-github-runner.yml`

9. Check runners have registered properly by visiting the repository's :code:`Action` tab -> :code:`Runners` -> :code:`Self-hosted runners`

10. Repeat the above steps for each environment you intend to deploy runners within.
    You can share the fine-grained access token between environments.

Workflow Deployment
-------------------

1. Edit :code:`$KAYOBE_CONFIG_PATH/inventory/group_vars/github-writer/writer.yml` in the base configuration making the appropriate changes to your deployments specific needs. See documentation for `stackhpc.kayobe_workflows.github <https://github.com/stackhpc/ansible-collection-kayobe-workflows/tree/main/roles/github>`__.

2. Run :code:`kayobe playbook run $KAYOBE_CONFIG_PATH/ansible/deployment/write-github-workflows.yml`

3. Add all required secrets and variables to repository either via the GitHub UI or GitHub CLI (may require repository owner)

+----------------------------------------------------------------------------------+
|                                      Secrets                                     |
+===================================+==============================================+
|         Single Environment        |             Multiple Environments            |
+-----------------------------------+----------------------------------------------+
| KAYOBE_AUTOMATION_SSH_PRIVATE_KEY | <ENV_NAME>_KAYOBE_AUTOMATION_SSH_PRIVATE_KEY |
+-----------------------------------+----------------------------------------------+
|       KAYOBE_VAULT_PASSWORD       |  <ENV_NAME>_KAYOBE_VAULT_PASSWORD            |
+-----------------------------------+----------------------------------------------+
|         REGISTRY_PASSWORD         |         <ENV_NAME>_REGISTRY_PASSWORD         |
+-----------------------------------+----------------------------------------------+
|           TEMPEST_OPENRC          |     <ENV_NAME>_TEMPEST_OPENRC                |
+-----------------------------------+----------------------------------------------+

    +-------------------------------------------------------+
    |                   VARIABLES                           |
    +====================+==================================+
    | Single Environment |  Multiple Environments           |
    +--------------------+----------------------------------+
    |    REGISTRY_URL    | <ENV_NAME>_REGISTRY_URL          |
    +--------------------+----------------------------------+
    |  REGISTRY_USERNAME |    <ENV_NAME>_REGISTRY_USERNAME  |
    +--------------------+----------------------------------+

Note the above tables shows the secrets and variables one may need to add to GitHub for a successful deployment.
When adding secrets and variables make sure to adhere to the naming standards and ensure the :code:`<ENV_NAME>` is replaced with all supported kayobe environments in uppercase.

4. Commit and push all newly generated workflows found under :code:`.github/workflows`

Final Steps
-----------

Some final steps include the following: running config-diff will require that :code:`.automation.conf/config.sh` contains a list :code:`KAYOBE_CONFIG_VAULTED_FILES_PATHS_EXTRA` of all vaulted files contained within the config.
All such files can be found with :code:`grep -r "$ANSIBLE_VAULT;1.1;AES256" .` though make sure NOT to include `kolla/passwords.yml` and `secrets.yml`
Also make sure tempest has been configured appropriately in :code:`.automation.conf/config.sh` to meet the limitations of a given deployment such as not using a too high of :code:`TEMPEST_CONCURRENCY` value and that overrides and load/skips lists are correct.
Finally, once all the workflows and configuration has been pushed and reviewed you can build a kayobe image using the `Build Kayobe Docker Image` workflow. Once it is successfully built and pushed to a container registry, other workflows can be used.

Sometimes the kayobe docker image must be rebuilt the reasons for this include but are not limited to the following;

    * Change :code:`$KAYOBE_CONFIG_PATH/ansible/requirements.yml`
    * Change to requirements.txt
    * Update Kayobe
    * Update kolla-ansible
    * UID/GID collision when deploying workflows to a new environment
    * Prior to deployment of new a OpenStack release

GitLab Pipelines
================

To enable CI/CD where GitLab Pipelines is used please follow the steps described below starting with the deployment of the runners.

Runner Deployment
-----------------

1. Identify a suitable host for hosting the runners.
    Ideally an infra-vm would be deployed to allow for easily compartmentalising the runners from the rest of the environment.
    8 VCPUs and 16GB of RAM is recommended for the guest machine however this may need to be adjusted for larger deployments.
    Whether the host is in an infra-vm or not it will need access to the :code:`admin_network` or :code:`provision_oc_network`, :code:`public_network` and the :code:`pulp registry` on the seed.
    The steps will assume that an infra-vm will be used for the purpose of hosting the runners.

2. Edit the environment's :code:`${KAYOBE_CONFIG_PATH}/environments/${KAYOBE_ENVIRONMENT}/inventory/hosts` to define the host(s) that will host the runners.

.. code-block:: ini

    [gitlab-runners]
    gitlab-runner-01

4. Provide all the relevant Kayobe :code:`group_vars` for :code:`gitlab-runners` under :code:`${KAYOBE_CONFIG_PATH}/environments/${KAYOBE_ENVIRONMENT}/inventory/group_vars/gitlab-runners`
    * `infra-vms` ensuring all required `infra_vm_extra_network_interfaces` are defined
    * `network-interfaces`
    * `allocated IPs`

5. Edit the ``${KAYOBE_CONFIG_PATH}/inventory/group_vars/gitlab-runners/runners.yml`` file which will contain the variables required to deploy a series of runners.
   Below is an example of how GitLab runners can be configured for deployment.
   In this example we have two runners, one for production and one for staging and will both be deployed on the same host.
   This might not be possible for all deployments as multiple environments may require different runners as no single runner can serve all environments.
   Note a GitLab runner can run multiple jobs concurrently so deploying a single runner per environment is recommended.

.. code-block:: yaml

    ---
    gitlab_runner_coordinator_url: "https://gitlab.example.com"
    gitlab_runner_runners:
      - name: "Kayobe Automation Runner [Production] #1"
          executor: docker
          docker_image: 'alpine'
          token: "{{ secrets_gitlab_production_runner_token }}"
          env_vars:
            - "GIT_CONFIG_COUNT=1"
            - "GIT_CONFIG_KEY_0=safe.directory"
            - "GIT_CONFIG_VALUE_0=*"
          tags:
            - kayobe
            - openstack
            - production
          docker_volumes:
            - "/var/run/docker.sock:/var/run/docker.sock"
            - "/opt/.docker/config.json:/root/.docker/config.json:ro"
            - "/cache"
          extra_configs:
          runners.docker:
            network_mode: host
      - name: "Kayobe Automation Runner [Staging] #1"
          executor: docker
          docker_image: 'alpine'
          token: "{{ secrets_gitlab_staging_runner_token }}"
          env_vars:
            - "GIT_CONFIG_COUNT=1"
            - "GIT_CONFIG_KEY_0=safe.directory"
            - "GIT_CONFIG_VALUE_0=*"
          tags:
            - kayobe
            - openstack
            - staging
          docker_volumes:
            - "/var/run/docker.sock:/var/run/docker.sock"
            - "/opt/.docker/config.json:/root/.docker/config.json:ro"
            - "/cache"
          extra_configs:
          runners.docker:
            network_mode: host

6. Obtain a runner token for each runner that is required for deployment.
    This token can be obtained by visiting the GitLab project -> Settings -> CI/CD -> Runners -> New project runner -> Complete the form including any tags used by the runners such as kayobe, openstack and environment_name.
    Once the token has been obtained, add it to :code:`secrets.yml` under :code:`secrets_gitlab_production_runner_token` and :code:`secrets_gitlab_staging_runner_token`

7. Deploy the infra-vm

.. code-block:: bash

    kayobe infra vm provision --limit gitlab-runner-01

8. Perform a host configure against the infra-vm

.. code-block:: bash

    kayobe infra vm host configure --limit gitlab-runner-01

9. Run :code:`kayobe playbook run ${KAYOBE_CONFIG_PATH}/ansible/deployment/deploy-gitlab-runner.yml`

10. Check runners have registered properly by visiting the repository's :code:`CI/CD` tab -> :code:`Runners`

11. The contents of :code:`/opt/.docker/config.json` on the runner should be added to GitLab CI/CD settings as a sercret variable if GitLab version permits otherwise variable is fine.
    This is required to allow the runners to pull images from the registry.
    Visit the GitLab project -> Settings -> CI/CD -> Variables -> Add a new variable with the key :code:`DOCKER_AUTH_CONFIG` and the value of the contents of :code:`/opt/.docker/config.json`

OpenBao Deployment
------------------

OpenBao must be installed on the same host as the runners.
If you have multiple environments that each have the own runners then OpenBao must be installed on each host.
However, if you have a single host that is shared between environments then OpenBao only needs to be installed once and can be achieved by running the following playbook.

.. code-block:: bash

    kayobe playbook run ${KAYOBE_CONFIG_PATH}/ansible/deployment/deploy-openbao-kayobe-automation.yml

.. note::

    If you are sharing OpenBao between environments then you will need to rerun the playbook under each environment to ensure that the correct secrets are available to the runners.
    You may use :code:`--tags add_secrets` to skip the deployment within other environments.
    For this to work you will need to copy :code:`vault/kayobe-automation-keys.json` from the first environment to the other environments in addition to copying the host definition of the gitlab runner add network IP.

Once the above playbook has been applied you need to grab the root token from :code:`vault/kayobe-automation-keys.json` as you will need this to enable JWT support.
This would also be an opportune time to encrypt the :code:`vault/kayobe-automation-keys.json` to protect the contents.

.. code-block:: bash

    ansible-vault encrypt vault/kayobe-automation-keys.json --vault-password-file ~/.vault.password

In order to enable JWT support the following steps must be carried out within the openbao container on the runner host.

1. SSH into the runner host

2. Run :code:`sudo docker exec -it bao sh`

3. Run :code:`export BAO_ADDR=http://127.0.0.1:8200`

4. Run :code:`bao login` and use root token

5. Run the following to enable and configure JWT support

.. note::

    The following steps are an example and should be adapted to suit your deployment.
    For example project_id within the gitlab role will need ID of the project that the runners are registered against.
    This can acquired by visiting the project -> Settings -> General -> General project settings -> Project ID.

.. code-block:: bash

    bao auth enable jwt
    bao policy write kayobe-automation - <<EOF
    path "kayobe-automation/*" {
      capabilities = [ "read" ]
    }
    EOF
    bao write auth/jwt/role/gitlab - <<EOF
    {
      "role_type": "jwt",
      "token_explicit_max_ttl": 60,
      "user_claim": "user_email",
      "bound_audiences": "http://127.0.0.1:8200",
      "bound_claims": {
        "project_id": "ADD_PROJECT_ID_HERE"
      },
      "policies": ["kayobe-automation"]
    }
    EOF
    bao write auth/jwt/config \
      jwks_url="https://gitlab.example.com/oauth/discovery/keys" \
      bound_issuer="https://gitlab.example.com"

GitLab Pipelines
----------------

1. Edit :code:`${KAYOBE_CONFIG_PATH}/inventory/group_vars/gitlab-writer/writer.yml` or environment equivalent the appropriate changes to your deployments specific needs.
See documentation for `stackhpc.kayobe_workflows.gitlab <https://github.com/stackhpc/ansible-collection-kayobe-workflows/tree/main/roles/gitlab>`__.
Following the instructions in the documentation will allow you to customise the workflows to fit within your deployment.
If using multiple environments ensure that :code:`gitlab_kayobe_environments` is updated to reflect all environments present in the deployment.
Also consider the impact runbooks might have as the runbooks are designed with a particular cloud in mind and may not be suitable for all deployments such as hyperconverged deployments with Ceph on hypervisors.

2. Run :code:`kayobe playbook run ${KAYOBE_CONFIG_PATH}/ansible/deployment/write-gitlab-pipelines.yml`

3. Commit and push all newly generated pipelines found under root of the repository.

Things to consider
==================

- Adjust General Pipeline settings by visiting the project -> Settings -> CI/CD -> General pipelines
  - Disable :code:`Public Pipelines`
  - Disable :code:`Auto-cancel redundant pipelines`
  - Disable :code:`Prevent outdated deployment jobs`
  - Increase :code:`Timeout` to :code:`12h`

- Disable Auto DevOps in the GitLab project settings by visiting the project -> Settings -> CI/CD -> Auto DevOps -> Disable Auto DevOps

Sometimes the kayobe docker image must be rebuilt. The reasons for this include but are not limited to the following;

    * Change :code:`$KAYOBE_CONFIG_PATH/ansible/requirements.yml`
    * Change to requirements.txt
    * Update Kayobe
    * Update kolla-ansible
    * Prior to deployment of new a OpenStack release
