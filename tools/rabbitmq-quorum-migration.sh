#! /usr/bin/bash

set -ex

RABBITMQ_SERVICES_TO_RESTART=barbican,blazar,cinder,cloudkitty,designate,heat,ironic,keystone,magnum,manila,neutron,nova,octavia
RABBITMQ_CONTAINER_NAME=rabbitmq

if [[ ! $KAYOBE_CONFIG_PATH ]]; then
    echo "Environment variable \$KAYOBE_CONFIG_PATH is not defined"
    echo "Ensure your environment is set up to run kayobe commands"
    exit 2
fi

if [[ ! "$1" = "--skip-checks" ]]; then
    # Fail if clocks are not synced
    if ! ( kayobe overcloud host command run -l controllers -b --command "timedatectl status | grep 'synchronized: yes'" ); then
        echo "Failed precheck: Time not synced on controllers"
        echo "Use 'timedatectl status' to check sync state"
        echo "Either wait for sync or use 'chronyc makestep'"
        exit 1
    fi
    kayobe overcloud service configuration generate --node-config-dir /tmp/rabbit-migration --kolla-tags none
    # Fail if HA is set or quorum is not
    if ! ( grep 'om_enable_rabbitmq_quorum_queues: true' $KOLLA_CONFIG_PATH/globals.yml || grep 'om_enable_rabbitmq_high_availability: true' $KOLLA_CONFIG_PATH/globals.yml ); then
        echo "Failed precheck: om_enable_rabbitmq_quorum_queues must be enabled, om_enable_rabbitmq_high_availability must be disabled"
        exit 1
    fi
fi

# Generate new config, stop services using rabbit, and reset rabbit state
kayobe overcloud service configuration generate --node-config-dir /etc/kolla --kolla-skip-tags rabbitmq-ha-precheck
kayobe kolla ansible run "stop --yes-i-really-really-mean-it" -kt $RABBITMQ_SERVICES_TO_RESTART
kayobe kolla ansible run rabbitmq-reset-state

if [[ ! "$1" = "--skip-checks" ]]; then
    # Fail if any queues still exist
    sleep 20
    if ( kayobe overcloud host command run -l controllers -b --command "docker exec $RABBITMQ_CONTAINER_NAME rabbitmqctl list_queues name --silent | grep -v '^$'" ); then
        echo "Failed check: RabbitMQ has not stopped properly, queues still exist"
        exit 1
    fi
    # Fail if any exchanges still exist (excluding those starting with 'amq.')
    if ( kayobe overcloud host command run -l controllers -b --command "docker exec $RABBITMQ_CONTAINER_NAME rabbitmqctl list_exchanges name --silent | grep -v '^$' | grep -v '^amq.'" ); then
        echo "Failed check: RabbitMQ has not stopped properly, exchanges still exist"
        exit 1
    fi
fi

# Redeploy with quorum queues enabled
kayobe kolla ansible run deploy-containers -kt $RABBITMQ_SERVICES_TO_RESTART

if [[ ! "$1" = "--skip-checks" ]]; then
    sleep 20
    # Assert that at least one quorum queue exists on each controller
    if ( kayobe overcloud host command run -l controllers -b --command "docker exec $RABBITMQ_CONTAINER_NAME rabbitmqctl list_queues type | grep quorum" ); then
        echo "Queues migrated successfully" 
    else
        echo "Failed post-check: A controller does not have any quorum queues"
    fi
fi
