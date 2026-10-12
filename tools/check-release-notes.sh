#!/usr/bin/env bash
# Ensures all release notes have a .yaml extension

set -eo pipefail

invalid=$(ls releasenotes/notes | grep -v '\.yaml$' || true)

if [[ -n "$invalid" ]]; then
    echo "ERROR: Release notes must have a .yaml extension, otherwise reno ignores them:"
    echo "$invalid"
    exit 1
fi
