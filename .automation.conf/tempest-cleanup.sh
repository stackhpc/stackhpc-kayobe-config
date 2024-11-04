#!/bin/bash

# Helper script that will attempt to delete leftover resources from tempest testing.
# Usage: tempest-cleanup.sh [--dry-run]

# NOTE: This script is provided as a convenience and may not cover all
# resources created by tempest. In particular, it does not attempt to delete
# floating IPs and can have issues with ports attached to other resources. Use
# with caution.

DRY_RUN=false

if [[ $1 == "--dry-run" ]]; then
    DRY_RUN=true
    echo "Dry run mode activated. No resources will be deleted."
fi

# Ensure openstack CLI is available
if ! command -v openstack > /dev/null; then
    echo "openstack command not found. Ensure you have sourced a virtual environment with the openstack CLI installed."
    exit 1
elif ! openstack network list > /dev/null; then
    echo "openstack command failed. Ensure you have sourced an openrc file."
    exit 1
fi

# Function to delete ports based on subnet IDs
function delete_ports {
    local subnet_ids=$1
    for subnet_id in $subnet_ids; do
        port_ids=$(openstack port list --fixed-ip subnet=$subnet_id -f value -c ID)
        if [[ -z $port_ids ]]; then
            echo "No ports found for subnet $subnet_id"
            continue
        fi
        for port_id in $port_ids; do
            local port_name=$(openstack port show $port_id -f value -c name)
            local device_owner=$(openstack port show $port_id -f value -c device_owner)
            if [[ $device_owner == "network:router_interface" ]] || [[ $device_owner == "network:ha_router_replicated_interface" ]]; then
                local router_id=$(openstack port show $port_id -f value -c device_id)
                if $DRY_RUN; then
                    echo "Would remove router interface on port $port_id $port_name from router $router_id"
                else
                    echo "Removing router interface on port $port_id $port_name from router $router_id..."
                    openstack router remove port $router_id $port_id || echo "Failed to remove router interface on port $port_id $port_name from router $router_id"
                fi
            fi
            if $DRY_RUN; then
                echo "Would delete port $port_id $port_name"
            else
                echo "Deleting port $port_id $port_name..."
                openstack port delete $port_id || echo "Failed to delete port $port_id $port_name"
            fi
        done
    done
}

# Function to delete resources based on type and name prefix
function delete_resources {
    local resource_type=$1
    local name_prefix=$2
    # If resource type is server, volume, or image, list all
    if [[ $resource_type == "server" ]] || [[ $resource_type == "volume" ]] || [[ $resource_type == "image" ]]; then
        id_name_list=$(openstack $resource_type list --all -f value -c ID -c Name | awk -v prefix="$name_prefix" '$2 ~ "^"prefix {print $1, $2}')
    else
        id_name_list=$(openstack $resource_type list -f value -c ID -c Name | awk -v prefix="$name_prefix" '$2 ~ "^"prefix {print $1, $2}')
    fi
    if [[ -z $id_name_list ]]; then
        echo "No $resource_type resources found with prefix $name_prefix"
        return
    fi
    while IFS= read -r line; do
        local resource_id=$(echo $line | awk '{print $1}')
        local resource_name=$(echo $line | awk '{$1=""; print $0}')
        if $DRY_RUN; then
            echo "Would delete $resource_type $resource_id $resource_name"
        else
            echo "Deleting $resource_type $resource_id $resource_name..."
            openstack $resource_type delete $resource_id || echo "Failed to delete $resource_type $resource_id $resource_name"
        fi
    done <<< "$id_name_list"
}

function cleanup {
    local name_prefix=$1
    echo "Getting network and subnet IDs with $name_prefix prefix (may take a while)"

    # Get subnet IDs associated with tempest networks
    TEMPEST_NETWORK_IDS=$(openstack network list -f value -c ID -c Name | awk -v prefix="$TEMPEST_PREFIX" '$2 ~ "^"prefix {print $1}')
    TEMPEST_SUBNET_IDS=""
    for network_id in $TEMPEST_NETWORK_IDS; do
        TEMPEST_SUBNET_IDS+=" $(openstack subnet list --network $network_id -f value -c ID)"
    done

    # Delete resources in the specified order
    delete_resources server $name_prefix
    delete_ports "$TEMPEST_SUBNET_IDS"
    delete_resources volume $name_prefix
    delete_resources router $name_prefix
    delete_resources network $name_prefix
    delete_resources image $name_prefix
    delete_resources user $name_prefix
    delete_resources project $name_prefix
}

cleanup tempest-
cleanup rally_

echo "Operation completed."
