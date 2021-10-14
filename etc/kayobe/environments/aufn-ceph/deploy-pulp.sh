#!/bin/bash

set -e

# Seed hypervisor provision_oc IP.
pulp_ip=192.168.33.4

if $(which dnf >/dev/null 2>&1); then
    CONTAINER=podman
    if ! type podman > /dev/null 2>&1; then
        sudo dnf -y install podman
    fi
else
    CONTAINER="sudo docker"
    if ! type docker > /dev/null 2>&1; then
	sudo apt update
	sudo apt -y install docker.io
    fi
fi

if $CONTAINER container inspect pulp > /dev/null 2>&1; then
    echo "Pulp already deployed"
    exit
fi

mkdir -p ~/pulp
cd ~/pulp

mkdir -p settings pulp_storage pgsql containers
echo "CONTENT_ORIGIN='http://${pulp_ip}:8080'
ANSIBLE_API_HOSTNAME='http://${pulp_ip}:8080'
ANSIBLE_CONTENT_HOSTNAME='http://${pulp_ip}:8080/pulp/content'
TOKEN_AUTH_DISABLED=True" > settings/settings.py

$CONTAINER run --detach \
               --publish 8080:80 \
               --name pulp \
               --volume "$(pwd)/settings":/etc/pulp:Z \
               --volume "$(pwd)/pulp_storage":/var/lib/pulp:Z \
               --volume "$(pwd)/pgsql":/var/lib/pgsql:Z \
               --volume "$(pwd)/containers":/var/lib/containers:Z \
               --device /dev/fuse \
	       --add-host pulp-server.internal.sms-cloud:10.205.3.187 \
               docker.io/pulp/pulp

until curl --fail http://localhost:8080/pulp/api/v3/status/ > /dev/null 2>&1; do
    sleep 2
done

$CONTAINER exec pulp pulpcore-manager reset-admin-password --password 9e4bfa04-9d9d-493d-9473-ba92e4361dae
echo "Pulp successfully deployed"
