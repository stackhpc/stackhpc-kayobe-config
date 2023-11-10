=====
CI/CD
=====

What is Kayobe Automation
=========================

`Kayobe automation <https://github.com/stackhpc/kayobe-automation/>`__ is a collection of scripts and tools that automate kayobe operations.
It is deployed and controlled by CI/CD platforms such as GitHub actions and GitLab pipelines.
Kayobe automation provides users with an easy process to perform tasks such as: overcloud service deploy, config-diff, tempest testing, and many more.
With it being integrated into platforms such as GitHub or GitLab it builds a close relationship between the contents of the deployments kayobe configuration and what is currently deployed.
This is because operations such as opening a pull request will trigger a config diff to be generated providing insight on what impact it might have on services or a tempest test that could be scheduled to run daily providing knowledge of faults earlier than before.

Kayobe automation has been designed to be independent of any CI/CD platform with all tasks running inside of a purpose built Kayobe container.
However, platform specific workflows need to be deployed to bridge the gap between the contents of Kayobe Automation and these CI/CD platforms.
Workflows are templated for each Kayobe configuration repository, ensuring appropriate workflow input parameters are defined, and any necessary customisations can be applied.
The templating of workflows is offered through the `stackhpc.kayobe_workflows <https://github.com/stackhpc/ansible-collection-kayobe-workflows/>`__ collection which currently supports GitHub workflows.

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
    runner-01

4. Provide all the relevant Kayobe :code:`group_vars` for :code:`github-runners` under :code:`${KAYOBE_CONFIG_PATH}/environments/${KAYOBE_ENVIRONMENT}/inventory/group_vars/github-runners`
    * `infra-vms` ensuring all required `infra_vm_extra_network_interfaces` are defined
    * `network-interfaces`
    * `python-interpreter.yml` ensuring that `ansible_python_interpreter: /usr/bin/python3` has been set

5. Create `${KAYOBE_CONFIG_PATH}/environments/${KAYOBE_ENVIRONMENT}/inventory/group_vars/github-runners/runner.yml` file which will contain the variables required to deploy a series of runners

.. code-block:: yaml

    ---
    runner_user: VM_USER_NAME_HERE
    github_account: ORG_NAME_HERE
    github_repo: KAYOBE_CONFIG_REPO_NAME_HERE
    access_token: "{{ secrets_github_access_token }}"

    base_runner_dir: /opt/actions-runner

    default_runner_labels:
      - kayobe
      - openstack

    github_runners:
      runner_01: {}
      runner_02: {}
      runner_03: {}

    docker_users:
      - "{{ runner_user }}"

    pip_install_packages:
      - name: docker

If using multiple environments add an extra label to :code:`default_runner_labels` to distinguish these runners from runners belonging to other environments.
Also feel free to change the number of runners and their names.

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

1. Edit `${KAYOBE_CONFIG_PATH}/inventory/group_vars/github-writer/writer.yml` in the base configuration making the appropriate changes to your deployments specific needs. See documentation for `stackhpc.kayobe_workflows.github <https://github.com/stackhpc/ansible-collection-kayobe-workflows/tree/main/roles/github>`__.

2. Run :code:`kayobe playbook run ${KAYOBE_CONFIG_PATH}/ansible/write-workflows.yml`

3. Add all required secrets to repository either via the GitHub UI or GitHub CLI (may require repository owner)
    * KAYOBE_AUTOMATION_SSH_PRIVATE_KEY: private key used by Ansible to authenticate with machines.
    * KAYOBE_VAULT_PASSWORD: password used by the config to encrypt Ansible Vault secrets.
    * REGISTRY_PASSWORD: password used to login to the docker registry such as Pulp.
    * TEMPEST_OPENRC: contents of :code:`kolla/public-openrc.sh`

Note if you are using multiple environments and not sharing secrets between environments then each of these must have the environment name prefix for each environment, for example:
    * PRODUCTION_KAYOBE_AUTOMATION_SSH_PRIVATE_KEY
    * PRODUCTION_KAYOBE_VAULT_PASSWORD
    * PRODUCTION_REGISTRY_PASSWORD
    * PRODUCTION_TEMPEST_OPENRC
    * STAGING_KAYOBE_AUTOMATION_SSH_PRIVATE_KEY
    * STAGING_KAYOBE_VAULT_PASSWORD
    * STAGING_REGISTRY_PASSWORD
    * STAGING_TEMPEST_OPENRC

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
