==============================
Walled Garden deployment guide
==============================

This document describes how to configure Kayobe for a “walled garden”
deployment, where most hosts do not have external network access.

Routing
=======

With the exception of hosts running HAProxy (usually controllers),
overcloud hosts typically do not have external network access.

The hosts running HAProxy typically have a gateway on the public API
network for external network access.

NTP
===

Overcloud hosts initially use the seed’s NTP server.

In ``etc/kayobe/inventory/group_vars/overcloud/time``:

.. code:: yaml

   ---
   # NTP services for overcloud hosts
   # During early initialisation we use the seed Node
   # Following deployment we include the OpenStack VIP

   chrony_ntp_servers:
     - server: "{{ admin_oc_net_name | net_ip(inventory_hostname=groups['seed'][0]) }}"

Proxy
=====

We use a Squid caching proxy to access external web resources.

In ``etc/kayobe/seed.yml``, enable the Squid proxy container on the
seed:

.. code:: yaml

   # Seed container running a Squid caching proxy. This can be used to proxy
   # HTTP(S) requests from control plane hosts.
   seed_squid_container_enabled: true

In some environments we have found that squid’s preference for IPv6 can
cause problems. It can be forced to prefer IPv4, by adding the following
in ``etc/kayobe/containers/squid_proxy/squid.conf``:

.. code::

   dns_v4_first on

In ``etc/kayobe/inventory/group_vars/overcloud/proxy`` (and any other
groups that need to use the proxy), configure overcloud hosts to use the
proxy:

.. code:: yaml

   ---
   # HTTP proxy URL (format: http(s)://[user:password@]proxy_name:port). By
   # default no proxy is used.
   http_proxy: "http://{{ admin_oc_net_name | net_ip(inventory_hostname=groups['seed'][0]) }}:3128"

   # HTTPS proxy URL (format: http(s)://[user:password@]proxy_name:port). By
   # default no proxy is used.
   https_proxy: "{{ http_proxy }}"

   # List of domains, hostnames, IP addresses and networks for which no proxy is
   # used. Defaults to ["127.0.0.1", "localhost", "{{ ('http://' ~
   # docker_registry) | urlsplit('hostname') }}"] if docker_registry is set, or
   # ["127.0.0.1", "localhost"] otherwise. This is configured only if either
   # http_proxy or https_proxy is set.
   no_proxy:
     - "127.0.0.1"
     - "localhost"
     - "{{ ('http://' ~ docker_registry) | urlsplit('hostname') if docker_registry else '' }}"
     - "{{ lookup('vars', admin_oc_net_name ~ '_ips')[groups.seed.0] }}"
     - "{{ lookup('vars', admin_oc_net_name ~ '_ips')[inventory_hostname] }}"
     - "{{ kolla_external_fqdn }}"
     - "{{ kolla_internal_fqdn }}"

   # PyPI proxy URL (format: http(s)://[user:password@]proxy_name:port)
   pip_proxy: "{{ https_proxy }}"

We typically don’t use the proxy for DNF package updates, or for
container image downloads, since the Pulp server is hosted on the seed.
The ``no_proxy`` setting should handle this.

For Ubuntu hosts, where package repos are not hosted in a local Pulp
server, you will also want to proxy APT requests. This can be done by
adding the following in
``etc/kayobe/inventory/group_vars/overcloud/proxy``:

.. code:: yaml

   # Apt proxy URL for HTTP. Default is empty (no proxy).
   apt_proxy_http: "{{ http_proxy }}"

   # Apt proxy URL for HTTPS. Default is {{ apt_proxy_http }}.
   apt_proxy_https: "{{ https_proxy }}"

Typically, container images are pulled from the local Pulp server. If
you need to be able to pull container images from external sources, it
may be necessary to add proxy configuration for Docker. This is Kolla
Ansible configuration, rather than Kayobe, in
``etc/kayobe/kolla/inventory/group_vars/overcloud``:

.. code:: yaml

   ---
   # Use a proxy for external Docker image pulls
   docker_http_proxy: "http://<seed IP>:3128"
   docker_https_proxy: "http://<seed IP>:3128"
   docker_no_proxy:
     - "127.0.0.1"
     - "localhost"
     - "{{ ('http://' ~ docker_registry) | urlsplit('hostname') if docker_registry else '' }}"
