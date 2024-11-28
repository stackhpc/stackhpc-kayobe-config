================
Pre-commit Hooks
================

StackHPC Kayobe configuration carries support for
`pre-commit hooks <https://pre-commit.com/>`_ which simplify the use of git
hooks enabling the identification and repairing of broken or poor code
before committing.
These hooks are designed to make working within SKC easier and less error prone.

Currently the following hooks are provided:

- ``check-yaml``: perform basic yaml syntax linting
- ``end-of-file-fixer``: identify and automatically fix missing newline
- ``trailing-whitespace``: identify and automatically fix excessive white space
- ``ripsecrets``: identify and prevent secrets from being committed to the branch

.. warning::
   The hook ``ripsecrets`` is capable of preventing the accidental leaking of secrets
   such as those found within `secrets.yml` or `passwords.yml`.
   However if the secret is contained within a file on it's own and lacks a certain level
   of entropy then the secret will not be identified as such as and maybe leaked as a result.

Installation of `pre-commit` hooks is handled via the `install-pre-commit-hooks` playbook
found within the Ansible directory.
Either run the playbook manually or add the playbook as a hook within Kayobe config such as
within `control-host-bootstrap/post.d`.
Once done you should find `pre-commit` is available within the `kayobe` virtualenv.

To run the playbook using the following command

- ``kayobe playbook run ${KAYOBE_CONFIG_PATH}/ansible/install-pre-commit-hooks.yml``

Whereas to run the playbook when control host bootstrap runs ensure it registered as symlink using the following command

- ``mkdir -p ${KAYOBE_CONFIG_PATH}/hooks/control-host-bootstrap/post.d``
- ``ln -s ${KAYOBE_CONFIG_PATH}/ansible/install-pre-commit-hooks.yml ${KAYOBE_CONFIG_PATH}/hooks/control-host-bootstrap/post.d/install-pre-commit-hooks.yml``

All that remains is the installation of the hooks themselves which can be accomplished either by
running `pre-commit run` or using `git commit` when you have changes that need to be committed.
This will trigger a brief installation process of the hooks which may take a few minutes.
This a one time process and will not be required again unless new hooks are added or existing ones are updated.

.. note::
   Currently if you run ``pre-commit run --all-files`` it will make a series of changes to
   release notes that lack new lines as well configuration files that ``check-yaml`` does not
   approve of.
