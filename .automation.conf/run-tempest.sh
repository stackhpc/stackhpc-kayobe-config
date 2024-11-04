#!/bin/bash

# Script based on Tempest section of Kayobe multinode deployment script
# plus https://wiki.stackhpc.com/doc/using-kayobe-automation-to-run-tempest-7yAEJw2eHb

set -euo pipefail

KAYOBE_CONFIG_BASE_PATH=$KAYOBE_CONFIG_PATH/../../

# Set Tempest env vars if not already set
set +x
: "${KAYOBE_AUTOMATION_SSH_PRIVATE_KEY:=$(cat ~/.ssh/id_rsa)}"
: "${TEMPEST_OPENRC:=$(cat $KAYOBE_CONFIG_PATH/../kolla/public-openrc.sh)}"
set -x

# Ensure timestamped output dir exists
OUTPUT_DIR=$KAYOBE_CONFIG_BASE_PATH/tempest-artifacts/$KAYOBE_ENVIRONMENT/$(date +%Y-%m-%d--T%H-%M-%S)
echo Creating output directory: $OUTPUT_DIR
mkdir -p $OUTPUT_DIR


# Set base image for Kayobe container. Use Rocky 9 for zed+ CentOS otherwise
if grep -Eq "(202|zed)" $KAYOBE_CONFIG_BASE_PATH/.gitreview; then
    export BASE_IMAGE=rockylinux:9
else
    export BASE_IMAGE=quay.io/centos/centos:stream8
fi

# Ensure the Kayobe image exists
IMAGE_TAG="kayobe"
if [[ "$(sudo docker image ls)" == *$IMAGE_TAG* ]]; then
    echo "Image already exists skipping docker build"
else
    sudo DOCKER_BUILDKIT=1 docker build \
        --network host \
        --build-arg BASE_IMAGE=$BASE_IMAGE \
        --build-arg HTTP_PROXY=$http_proxy \
        --build-arg HTTPS_PROXY=$https_proxy \
        --build-arg NO_PROXY=$no_proxy \
        --file $KAYOBE_CONFIG_BASE_PATH/.automation/docker/kayobe/Dockerfile \
        --tag $IMAGE_TAG:latest $KAYOBE_CONFIG_BASE_PATH
fi

# Run Tempest
sudo -E docker run --rm \
    --name kayobe_automation \
    --network host \
    -v $KAYOBE_CONFIG_BASE_PATH:/stack/kayobe-automation-env/src/kayobe-config \
    -v $OUTPUT_DIR:/stack/tempest-artifacts \
    -e KAYOBE_ENVIRONMENT -e KAYOBE_VAULT_PASSWORD -e KAYOBE_AUTOMATION_SSH_PRIVATE_KEY \
    -e TEMPEST_OPENRC \
    $IMAGE_TAG:latest \
    /stack/kayobe-automation-env/src/kayobe-config/.automation/pipeline/tempest.sh \
    -e ansible_user=stack -e rally_no_sensitive_log=false

# Fix output dir ownership
sudo chown -R stack:stack $OUTPUT_DIR

# Uncomment to copy failures into a load list for easy retry
# cp $OUTPUT_DIR/failed-tests $KAYOBE_CONFIG_BASE_PATH/.automation.conf/tempest/load-lists/$KAYOBE_ENVIRONMENT-failed-tests
