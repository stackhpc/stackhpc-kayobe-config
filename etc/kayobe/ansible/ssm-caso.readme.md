# Purpose

This playbook builds and deploys an SSM container, currently configured to run an
SSM sender process for sending cASO usage logs to APEL via AMS. The cASO container
deployed by Kolla has a shared volume also mounted by the SSM container.

# Usage

`kayobe playbook run $PWD/ansible/ssm-caso.yml --limit monitoring`
