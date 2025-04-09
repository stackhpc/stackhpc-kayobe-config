# Pulp Auth Proxy

There is currently no practical, secure way to provide credentials for
accessing Ark's authenticated package repositories from within a Kolla build.
Docker provides [build
secrets](https://docs.docker.com/build/building/secrets/), but these must be
explicitly requested for each RUN statement, making them challenging to use in
Kolla.

This role deploys an Nginx container that runs as a reverse proxy, injecting an
HTTP basic authentication header into requests.

Because this proxy bypasses Pulp's authentication, it must not be exposed to
any untrusted environment.

## Role variables

* `pulp_auth_proxy_url`: URL of the Pulp server to proxy requests to.
* `pulp_auth_proxy_username`: Username of the Pulp server to proxy requests to.
* `pulp_auth_proxy_password`: Password of the Pulp server to proxy requests to.
* `pulp_auth_proxy_conf_path`: Path to a directory in which to write Nginx
  configuration.
* `pulp_auth_proxy_listen_ip`: IP address on the Docker host on which to
  listen. Default is `127.0.0.1`.
* `pulp_auth_proxy_listen_port`: Port on the Docker host on which to listen.
  Default is 80.
