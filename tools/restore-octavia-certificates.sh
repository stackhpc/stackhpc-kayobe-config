#!/bin/bash

set -eu

if [ -z ${KAYOBE_CONFIG_PATH:+x} ]; then
    1>&2 echo 'Please source kayobe-env'
    exit 1
fi

if [ -z ${KAYOBE_VAULT_PASSWORD:+x} ]; then
    1>&2 echo 'Please set Kayobe vault password'
    exit 1
fi

if [ -d $KOLLA_CONFIG_PATH/octavia-certificates ]; then
    1>&2 echo 'Certificates exists. Please remove if you wish to restore.'
    exit -1
fi

cat $KAYOBE_CONFIG_PATH/environments/$KAYOBE_ENVIRONMENT/kolla/certificates/octavia-certificates-backup.tar | ansible-vault decrypt --vault-password-file $KAYOBE_CONFIG_PATH/../../tools/vault-helper.sh 2>/dev/null | tar -xvf - -C $KOLLA_CONFIG_PATH
