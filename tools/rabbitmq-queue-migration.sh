#! /usr/bin/bash

set -ex

RED='\033[0;31m'
GREEN='\033[0;32m'

RABBITMQ_SERVICES_TO_RESTART=barbican,blazar,cinder,cloudkitty,designate,heat,ironic,keystone,magnum,manila,neutron,nova,octavia
RABBITMQ_CONTAINER_NAME=rabbitmq

if [[ ! $KAYOBE_CONFIG_PATH ]]; then
    echo -e "${RED}Environment variable \$KAYOBE_CONFIG_PATH is not defined"
    echo -e "${RED}Ensure your environment is set up to run kayobe commands"
    exit 2
fi

if [[ ! "$1" = "--skip-checks" ]]; then
    # Fail if clocks are not synced
    if ! ( kayobe overcloud host command run -l controllers -b --command "timedatectl status | grep 'synchronized: yes'" ); then
        echo -e "${RED}Failed precheck: Time not synced on controllers"
        echo -e "${RED}Use 'timedatectl status' to check sync state"
        echo -e "${RED}Either wait for sync or use 'chronyc makestep'"
        exit 1
    fi
    kayobe overcloud service configuration generate --node-config-dir /tmp/rabbit-migration --kolla-tags none
    # Fail if any new feature flags are not set
    if ! ( grep 'om_enable_queue_manager: true' $KOLLA_CONFIG_PATH/globals.yml && \
           grep 'om_enable_rabbitmq_quorum_queues: true' $KOLLA_CONFIG_PATH/globals.yml && \
           grep 'om_enable_rabbitmq_transient_quorum_queue: true' $KOLLA_CONFIG_PATH/globals.yml && \
           grep 'om_enable_rabbitmq_stream_fanout: true' $KOLLA_CONFIG_PATH/globals.yml ); then
              echo -e "${RED}Failed precheck: The following must be enabled: om_enable_queue_manager, om_enable_rabbitmq_quorum_queues, om_enable_rabbitmq_transient_quorum_queue, om_enable_rabbitmq_stream_fanout"
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
    # Note(mattcrees): We turn the text grey here so the failed Ansible calls don't freak anyone out
    CURRENTTERM=${TERM}
    export TERM=xterm-mono
    if ( kayobe overcloud host command run -l controllers -b --command "docker exec $RABBITMQ_CONTAINER_NAME rabbitmqctl list_queues name --silent | grep -v '^$'" ); then
        export TERM=${CURRENTTERM}
        echo -e "${RED}Failed check: RabbitMQ has not stopped properly, queues still exist"
        exit 1
    fi
    # Fail if any exchanges still exist (excluding those starting with 'amq.')
    if ( kayobe overcloud host command run -l controllers -b --command "docker exec $RABBITMQ_CONTAINER_NAME rabbitmqctl list_exchanges name --silent | grep -v '^$' | grep -v '^amq.'" ); then
        export TERM=${CURRENTTERM}
        echo -e "${RED}Failed check: RabbitMQ has not stopped properly, exchanges still exist"
        exit 1
    fi
    export TERM=${CURRENTTERM}
fi

# Redeploy with all durable-type queues enabled
kayobe kolla ansible run deploy-containers -kt $RABBITMQ_SERVICES_TO_RESTART

if [[ ! "$1" = "--skip-checks" ]]; then
    sleep 60
    # Assert that all queues are durable
    if ! ( kayobe overcloud host command run -l controllers -b --command "docker exec $RABBITMQ_CONTAINER_NAME rabbitmqctl list_queues durable --silent | grep false" > /dev/null 2>&1 ); then
        echo -e "${GREEN}Queues migrated successfully"
    else
        echo -e "${RED}Failed post-check: A controller has non-durable queues"
    fi
fi
