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
    # Ensure RabbitMQ is upgraded to 4.1
    if kayobe overcloud host command run -l controllers -b --command "docker exec rabbitmq rabbitmqctl --version | grep -F 3.13." --show-output; then
        kayobe kolla ansible run "rabbitmq-upgrade 4.1" --kolla-skip-tags rabbitmq-version-check
    fi
}

function rabbit_migration() {
    if kayobe overcloud host command run -l controllers -b --command "docker exec rabbitmq rabbitmqctl list_queues durable | grep false"; then
        # Set feature flaga, execute RabbitMQ queue migration script, unset feature flags (to avoid git conflicts)
        KOLLA_GLOBALS_PATH=$KAYOBE_CONFIG_PATH/kolla/globals.yml
        if [[ $KAYOBE_ENVIRONMENT ]]; then
            KOLLA_GLOBALS_PATH=$KAYOBE_CONFIG_PATH/environments/$KAYOBE_ENVIRONMENT/kolla/globals.yml
        fi
        sed -i -e '$aom_enable_queue_manager: True' \
               -e '$aom_enable_rabbitmq_quorum_queues: True' \
               -e '$aom_enable_rabbitmq_transient_quorum_queue: True' \
               -e '$aom_enable_rabbitmq_stream_fanout: True' \
            $KOLLA_GLOBALS_PATH

        $KAYOBE_CONFIG_PATH/../../tools/rabbitmq-queue-migration.sh

        sed -i -e '/om_enable_queue_manager: True/d' \
               -e '/om_enable_rabbitmq_quorum_queues: True/d' \
               -e '/om_enable_rabbitmq_transient_quorum_queue: True/d' \
               -e '/om_enable_rabbitmq_stream_fanout: True/d' \
            $KOLLA_GLOBALS_PATH

    fi
}

prechecks
rabbit_migration
rabbit_upgrade
