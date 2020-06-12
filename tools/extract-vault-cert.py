#!/usr/bin/env python3

import json
import os
import sys

os.umask(0o077)

filename = sys.argv[1]
with open(filename) as f:
    cert_json = f.read()

certs = json.loads(cert_json)
for key in certs:
    if key in ['privateKeyType', 'serialNumber']:
        name = key
    else:
        name = key + '.pem'
    with open(name, 'w') as f:
        f.write(certs[key])
