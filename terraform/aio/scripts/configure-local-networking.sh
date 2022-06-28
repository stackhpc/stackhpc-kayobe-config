#!/bin/bash

set -e

# WORKAROUND: internal DNS missing from SMS lab.
cat << EOF | sudo tee -a /etc/hosts
10.0.0.34 pelican pelican.service.compute.sms-lab.cloud
10.205.3.187 pulp-server pulp-server.internal.sms-cloud
EOF

# IP of the seed hypervisor on the OpenStack 'public' network created by init-runonce.sh.
public_ip="10.0.2.1"

# IP addresses on the all-in-one Kayobe cloud network.
# These IP addresses map to those statically configured in
# etc/kayobe/network-allocation.yml and etc/kayobe/networks.yml.
controller_vip=192.168.33.2

# Forward the following ports to the controller.
# 80: Horizon
# 6080: VNC console
forwarded_ports="80 6080"

sudo ip l add breth1 type bridge
sudo ip l set breth1 up
sudo ip a add 192.168.33.3/24 dev breth1
sudo ip l add eth1 type dummy
sudo ip l set eth1 up
sudo ip l set eth1 master breth1

iface=$(ip route | awk '$1 == "default" {print $5; exit}')

#sudo iptables -A POSTROUTING -t nat -o $iface -j MASQUERADE
sudo sysctl -w net.ipv4.conf.all.forwarding=1

# Install iptables.
if $(which dnf >/dev/null 2>&1); then
    sudo dnf -y install iptables
fi

# Configure port forwarding from the hypervisor to the Horizon GUI on the
# controller.
sudo iptables -A FORWARD -i $iface -o breth1 -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
sudo iptables -A FORWARD -i breth1 -o $iface -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
for port in $forwarded_ports; do
  # Allow new connections.
  sudo iptables -A FORWARD -i $iface -o breth1 -p tcp --syn --dport $port -m conntrack --ctstate NEW -j ACCEPT
  # Destination NAT.
  sudo iptables -t nat -A PREROUTING -i $iface -p tcp --dport $port -j DNAT --to-destination $controller_vip
done

# Configure an IP on the 'public' network to allow access to/from the cloud.
if ! sudo ip a show dev breth1 | grep $public_ip/24 >/dev/null 2>&1; then
  sudo ip a add $public_ip/24 dev breth1
fi

# This prevents network.service from restarting correctly.
sudo killall dhclient
