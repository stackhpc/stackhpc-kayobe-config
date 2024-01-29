#! /usr/bin/bash

set -e

if [[ ! $1 ]]; then
    echo "Usage: seed-ubuntu-upgrade.sh <seed-hostname>"
    exit 2
fi

if [[ ! $KAYOBE_PATH ]]; then
    echo "Environment variable \$KAYOBE_PATH is not defined"
    exit 2
fi

if [[ ! $KAYOBE_CONFIG_PATH ]]; then
    echo "Environment variable \$KAYOBE_CONFIG_PATH is not defined"
    exit 2
fi

if [[ ! $ANSIBLE_ROLES_PATH ]]; then
    set -x
    export ANSIBLE_ROLES_PATH=$KAYOBE_PATH/ansible/roles
    set +x
else
    set -x
    export ANSIBLE_ROLES_PATH=$ANSIBLE_ROLES_PATH:$KAYOBE_PATH/ansible/roles
    set +x
fi

set -x

kayobe playbook run $KAYOBE_CONFIG_PATH/ansible/ubuntu-upgrade.yml --limit $1

kayobe seed host configure --limit $1
