#cloud-config
# Don't automatically mount ephemeral disk
mounts:
  - [/dev/vdb, null]
# WORKAROUND: internal DNS missing from SMS lab.
runcmd:
  - 'echo "10.0.0.34 pelican pelican.service.compute.sms-lab.cloud" >> /etc/hosts'
  - 'echo "10.205.3.187 pulp-server pulp-server.internal.sms-cloud" >> /etc/hosts'
# Configure SSH keys here, to avoid creating an ephemeral keypair.
# This means only the instance needs to be cleaned up if the destroy fails.
ssh_authorized_keys:
  - file(var.ssh_public_key)
