#! /usr/bin/bash

# This script is intended to be run in CI to test upgrades.
# It executes any preparation steps that must be perfomed before upgrading
# OpenStack services.

# NOTE(upgrade): This script is unique to each release. It may not be required
# for some releases.

set -ex

function prechecks() {
    if [[ ! $KAYOBE_CONFIG_PATH ]]; then
        echo "Environment variable \$KAYOBE_CONFIG_PATH is not defined"
        echo "Ensure your environment is set up to run kayobe commands"
        exit 2
    fi

    echo "Installing dependencies..."
    if type dnf > /dev/null 2>&1; then
        sudo dnf -y install jq
    else
        sudo apt update
        sudo apt -y install jq
    fi

}

function valkey_migration() {

    enable_redis=$(kayobe configuration dump --var-name kolla_enable_redis -l localhost | jq .localhost)
    if [[ $enable_redis == "true" || $enable_redis == "yes" ]]; then
        kayobe kolla ansible run migrate-valkey -ke enable_redis=false -ke enable_valkey=true
    fi

}

prechecks
valkey_migration
