===============
Hotfix Playbook
===============

Using the Container Hotfix Playbook
===================================

The StackHPC Kayobe configuration contains a playbook called
``hotfix-containers.yml`` which can be used to execute commands on, and copy
files into, a given set of containers.

This playbook will first copy across any hotfix files, and then run the
hotfix command. If either of these are not specified, the corresponding step
will be skipped.

This playbook is designed for use in high-severity hotfixes ONLY and should not
be used for regular operations.

The playbook can be invoked with:

.. code-block:: console

  kayobe playbook run ${KAYOBE_CONFIG_PATH}/ansible/hotfix-containers.yml

Playbook variables:
-------------------

* ``container_hotfix_command``: A command to run on each of the target
  containers. Default is an empty string.

* ``container_hotfix_files``: A list of files to copy into each target
  container. Consists of a list of dicts with keys ``src`` and ``dest``
  (required), and ``mode`` (optional - default 400). Default is an empty list.

* ``container_hotfix_container_regex``: Regex to match container names against.
  Must match the entire name e.g. "nova" or "nova*" will result in only
  matching a single container called "nova". To properly match every container
  starting with "nova", the regex must be "nova.*" Default is an empty string.

* ``container_hotfix_restart_containers``: Whether to restart containers after
  applying the hotfix. Default is False.

* ``container_hotfix_become``: Create files and exec as root in the target
  containers. Default is False.


It is strongly recommended that you write your container_hotfix_* variables
to a file, then add them as an extra var. e.g:

.. code-block:: console

  kayobe playbook run ${KAYOBE_CONFIG_PATH}/ansible/hotfix-containers.yml -e "@~/vars.yml"


Example Variables file
----------------------

.. code-block:: yaml

    ---
    container_hotfix_command: "/tmp/quick-fix.sh"
    container_hotfix_files:
      - src: "~/quick-fix.sh"
        dest: "/tmp/quick-fix.sh"
        mode: "700"
      - src: "/home/stackhpc/new_nova_conf.conf"
        dest: "/etc/nova/nova.conf"
    container_hotfix_container_regex: "nova.*"
    container_hotfix_restart_containers: True
    container_hotfix_become: True
