#!/usr/bin/env python3

import argparse
import subprocess
from shlex import split as sh
import sys
import json
from urllib.parse import urlsplit, ParseResult

def run(cmd):
  print(f"Running cmd: {cmd}", file=sys.stderr)
  stdout = subprocess.check_output(sh(cmd))
  return json.loads(stdout)

def page(href):
   page = run(f"pulp show --href '{href}'")
   next = page["next"]
   results = page["results"]
   while next != None:
     parsed = urlsplit(page["next"])
     href = parsed._replace(scheme="")._replace(netloc="").geturl()
     page = run(f"pulp show --href '{href}'")
     next = page["next"]
     results.extend(page["results"])
   return results

if __name__ == "__main__":

  parser = argparse.ArgumentParser(description='Package versions')
  parser.add_argument('base_path', metavar='path', type=str,
			    help='Base path of distribution')
  args = parser.parse_args()
  base_path = args.base_path
  distributions = run(f"pulp rpm distribution list --base-path '{ args.base_path }'")
  if not distributions:
     raise ValueError("No distribution found")
  if len(distributions) > 1:
     raise ValueError("Found more than on distribution")
  distribution = distributions[0]
  publication_href = distribution['publication']
  publication = run(f"pulp rpm publication show --href '{ publication_href }'")
  if not publication:
    raise ValueError("publication not found")
  repository_version = publication["repository_version"]
  packages = page(f"pulp/api/v3/content/rpm/packages/?repository_version={repository_version}&fields=name,version,release,arch&limit=1000")
  packages = sorted(packages, key=lambda xs: xs['name']) 
  print(json.dumps(packages, indent=2))

