#!/bin/bash

set -x

sudo dnf install -y python3.12
sudo ln -sf /bin/python3.12 /bin/python3
sudo ln -sf /usr/bin/python3.12 /usr/bin/python3

echo $(python3 --version)

sudo python3 -m ensurepip
