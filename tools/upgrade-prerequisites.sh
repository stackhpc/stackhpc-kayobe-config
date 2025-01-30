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
}

function rabbit_upgrade() {
    # Ensure RabbitMQ is upgraded to 3.13
    if kayobe overcloud host command run -l controllers -b --command "docker exec rabbitmq rabbitmqctl --version | grep -F 3.11." --show-output; then
        kayobe kolla ansible run "rabbitmq-upgrade 3.12"
    fi
    sleep 200
    if kayobe overcloud host command run -l controllers -b --command "docker exec rabbitmq rabbitmqctl --version | grep -F 3.12." --show-output; then
        kayobe kolla ansible run "rabbitmq-upgrade 3.13"
    fi
}

function rabbit_migration() {
    if ! kayobe overcloud host command run -l controllers -b --command "docker exec rabbitmq rabbitmqctl list_queues type | grep quorum"; then
        # Set quorum flag, execute RabbitMQ queue migration script, unset quorum flag (to avoid git conflicts)
        KOLLA_GLOBALS_PATH=$KAYOBE_CONFIG_PATH/kolla/globals.yml
        if [[ $KAYOBE_ENVIRONMENT ]]; then
            KOLLA_GLOBALS_PATH=$KAYOBE_CONFIG_PATH/environments/$KAYOBE_ENVIRONMENT/kolla/globals.yml
        fi
        sed -i -e 's/om_enable_rabbitmq_high_availability: true/om_enable_rabbitmq_high_availability: false/' \
               -e 's/om_enable_rabbitmq_quorum_queues: false/om_enable_rabbitmq_quorum_queues: true/' \
            $KOLLA_GLOBALS_PATH

        $KAYOBE_CONFIG_PATH/../../tools/rabbitmq-quorum-migration.sh

        sed -i -e 's/om_enable_rabbitmq_high_availability: false/om_enable_rabbitmq_high_availability: true/' \
               -e 's/om_enable_rabbitmq_quorum_queues: true/om_enable_rabbitmq_quorum_queues: false/' \
            $KOLLA_GLOBALS_PATH
    fi
}

prechecks
rabbit_upgrade
rabbit_migration
