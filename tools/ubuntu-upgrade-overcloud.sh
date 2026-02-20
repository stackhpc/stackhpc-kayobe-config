#!/usr/bin/env bash

set -e

if [[ -z "$1" ]]; then
    echo "Usage: overcloud-ubuntu-upgrade.sh <overcloud-hostname>"
    exit 2
fi

if [[ -z "$KAYOBE_PATH" ]]; then
    echo "Environment variable \$KAYOBE_PATH is not defined"
    exit 2
fi

if [[ -z "$KAYOBE_CONFIG_PATH" ]]; then
    echo "Environment variable \$KAYOBE_CONFIG_PATH is not defined"
    exit 2
fi

if [[ -z "$ANSIBLE_ROLES_PATH" ]]; then
    set -x
    export ANSIBLE_ROLES_PATH="$KAYOBE_PATH/ansible/roles"
    set +x
else
    set -x
    export ANSIBLE_ROLES_PATH="$ANSIBLE_ROLES_PATH:$KAYOBE_PATH/ansible/roles"
    set +x
fi

set -x

kayobe playbook run "$KAYOBE_CONFIG_PATH/ansible/ubuntu-upgrade.yml" \
    -e os_release=noble --limit "$1"

kayobe playbook run "$KAYOBE_CONFIG_PATH/ansible/ovn-fix-chassis-priorities.yml"

kayobe overcloud host configure --limit "$1" -e os_release=noble

