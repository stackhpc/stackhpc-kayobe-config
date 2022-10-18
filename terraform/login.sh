#!/bin/bash

# Usage:
# export GITLAB_TOKEN=<personal access token>
# export GITLAB_USER=<gitlab username>
# cd aio
# ../login.sh <state name>

set -eux
state_file=${KAYOBE_AUTOMATION_TERRAFORM_STATE_NAME:-$1}

GITLAB_USER="${GITLAB_USER:-will70}"
# Scientific openstack
GITLAB_PROJECT="${GITLAB_PROJECT:-25160749}"

terraform init \
    -backend-config="address=https://gitlab.com/api/v4/projects/$GITLAB_PROJECT/terraform/state/$state_file" \
    -backend-config="lock_address=https://gitlab.com/api/v4/projects/$GITLAB_PROJECT/terraform/state/$state_file/lock" \
    -backend-config="unlock_address=https://gitlab.com/api/v4/projects/$GITLAB_PROJECT/terraform/state/$state_file/lock" \
    -backend-config="username=$GITLAB_USER" \
    -backend-config="password=$GITLAB_TOKEN" \
    -backend-config="lock_method=POST" \
    -backend-config="unlock_method=DELETE" \
    -backend-config="retry_wait_min=5" \
    -reconfigure
