---

# IP that haproxy binds to. The default works for when
# you are using a provider network. It will need to be
# customised if using a floating IP to login.
aio_public_address: "${access_ip_v4}"
aio_public_cidr: "${access_cidr}"
aio_public_gateway: "${access_gw}"
