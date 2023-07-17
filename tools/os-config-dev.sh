#!/bin/bash
set -eux 

source ~/venvs/os-config/bin/activate
cd ~/src/$1-config
export ANSIBLE_VAULT_PASSWORD_FILE=~/vault.secret
source ~/src/kayobe-config/etc/kolla/public-openrc.sh





