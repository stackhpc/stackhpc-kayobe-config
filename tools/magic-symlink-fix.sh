#!/bin/bash

# Script to fix broken symlinks to playbooks by updating their paths.

# Ensure KAYOBE_CONFIG_PATH is defined
if [[ -z "$KAYOBE_CONFIG_PATH" ]]; then
    echo "Error: KAYOBE_CONFIG_PATH is not defined."
    exit 1
fi

pushd "$KAYOBE_CONFIG_PATH/../.." > /dev/null

HELPER_SCRIPT="$KAYOBE_CONFIG_PATH/../../tools/get-new-playbook-path.sh"

# Find all broken symlinks
for symlink in $(find . -xtype l); do

    # Set up vars
    symlink_directory=$(dirname "$symlink")
    target=$(readlink "$symlink")
    playbook_name=$(basename "$target")

    # Get new directory name
    new_directory=$("$HELPER_SCRIPT" "$playbook_name")
    if [[ -z "$new_directory" ]]; then
        echo "Warning: Could not determine new dir for playbook '$playbook_name' - Skipping '$symlink'"
        continue
    fi

    # Construct the new target path & check it actually exists
    new_target=$(dirname "$target")/$new_directory$playbook_name
    if [[ ! -e "$symlink_directory/$new_target" ]]; then
        echo "Warning: New target '$symlink_directory/$new_target' does not exist. Skipping '$symlink'."
        exit 0
        continue
    fi

    # Update the symlink
    ln -sf "$new_target" "$symlink"
    echo "Updated symlink: $symlink -> $new_target"
done

popd > /dev/null
