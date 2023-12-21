=====
CI/CD
=====

Concepts
========

The CI/CD system developed for managing Kayobe based OpenStack clouds is composed of three main components; workflows, runners and kayobe automation.
Firstly, the workflows are files which describe a series of tasks to be performed in relation to the deployed cloud.
These workflows are executed on request, on schedule or in response to an event such as a pull request being opened.
The workflows are designed to carry out various day-to-day activites such as; running Tempest tests, configuring running services or displaying the change to configuration files if a pull request is merged.
Secondly, in order for the workflows to run against a cloud we would need private runners present within the cloud positioned in such a way they can reach the internal network and public API.
Deployment of private runners is supported by all major providers with the use of community developed Ansible roles.
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

2. Edit the environment's :code:`${KAYOBE_CONFIG_PATH}/environments/${KAYOBE_ENVIRONMENT}/inventory/groups` to add the predefined :code:`github-runners` group to :code:`infra-vms`

.. code-block:: ini

    [infra-vms:children]
    github-runners

3. Edit the environment's :code:`${KAYOBE_CONFIG_PATH}/environments/${KAYOBE_ENVIRONMENT}/inventory/hosts` to define the host(s) that will host the runners.

.. code-block:: ini

    [github-runners]
    prod-runner-01

4. Provide all the relevant Kayobe :code:`group_vars` for :code:`github-runners` under :code:`${KAYOBE_CONFIG_PATH}/environments/${KAYOBE_ENVIRONMENT}/inventory/group_vars/github-runners`
    * `infra-vms` ensuring all required `infra_vm_extra_network_interfaces` are defined
    * `network-interfaces`
    * `python-interpreter.yml` ensuring that `ansible_python_interpreter: /usr/bin/python3` has been set

5. Edit the ``${KAYOBE_CONFIG_PATH}/inventory/group_vars/github-runners/runners.yml`` file which will contain the variables required to deploy a series of runners.
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

7. If the host is an actual Infra VM then please refer to upstream `Infrastructure VMs <https://docs.openstack.org/kayobe/latest/configuration/reference/infra-vms.html>`__ documentation for additional configuration and steps.

8. Run :code:`kayobe playbook run ${KAYOBE_CONFIG_PATH}/ansible/deploy-github-runner.yml`

9. Check runners have registered properly by visiting the repository's :code:`Action` tab -> :code:`Runners` -> :code:`Self-hosted runners`

10. Repeat the above steps for each environment you intend to deploy runners within.
    You can share the fine-grained access token between environments.

Workflow Deployment
-------------------

1. Edit :code:`${KAYOBE_CONFIG_PATH}/inventory/group_vars/github-writer/writer.yml` in the base configuration making the appropriate changes to your deployments specific needs. See documentation for `stackhpc.kayobe_workflows.github <https://github.com/stackhpc/ansible-collection-kayobe-workflows/tree/main/roles/github>`__.

2. Run :code:`kayobe playbook run ${KAYOBE_CONFIG_PATH}/ansible/write-github-workflows.yml`

3. Add all required secrets and variables to repository either via the GitHub UI or GitHub CLI (may require repository owner)

+----------------------------------------------------------------------------------+
|                                      Secrets                                     |
+===================================+==============================================+
|         Single Environment        |             Multiple Environments            |
+-----------------------------------+----------------------------------------------+
| KAYOBE_AUTOMATION_SSH_PRIVATE_KEY | <ENV_NAME>_KAYOBE_AUTOMATION_SSH_PRIVATE_KEY |
+-----------------------------------+----------------------------------------------+
|       KAYOBE_VAULT_PASSWORD       |  <ENV_NAME>_KAYOBE_VAULT_PASSWORD |
+-----------------------------------+----------------------------------------------+
|         REGISTRY_PASSWORD         |         <ENV_NAME>_REGISTRY_PASSWORD         |
+-----------------------------------+----------------------------------------------+
|           TEMPEST_OPENRC          |     <ENV_NAME>_TEMPEST_OPENRC     |
+-----------------------------------+----------------------------------------------+

    +----------------------------------------------+
    |                   VARIABLES                  |
    +====================+=========================+
    | Single Environment |  Multiple Environments  |
    +--------------------+-------------------------+
    |    REGISTRY_URL    | <ENV_NAME>_REGISTRY_URL |
    +--------------------+-------------------------+
    |  REGISTRY_USERNAME |    <ENV_NAME>_REGISTRY_USERNAME  |
    +--------------------+-------------------------+

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
