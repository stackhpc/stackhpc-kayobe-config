#!/bin/bash
set -eux 

source ~/venvs/kayobe/bin/activate
cd ~/src/kayobe-config
source kayobe-env --environment $1
source <(kayobe complete)
export KAYOBE_VAULT_PASSWORD=$(< ~/vault.secret)
export KAYOBE_ENVIRONMENT=$1