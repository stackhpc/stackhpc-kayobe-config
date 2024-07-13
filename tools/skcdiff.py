import subprocess
import os
import yaml
import sys

# Function to merge dictionaries of lists
def merge_dols(dol1, dol2):
  keys = set(dol1).union(dol2)
  no = []
  return dict((k, dol1.get(k, no) + dol2.get(k, no)) for k in keys)

entries = []
output = {}
index = 0

path = os.path.dirname(__file__)
arg = sys.argv[1] if len(sys.argv) > 1 else ''

# Run shell script to get basic string with all applicable release notes
results = subprocess.run([path + '/skc-diff.sh', arg], stdout=subprocess.PIPE).stdout.decode()

# Split output into list of entries
for line in results.splitlines():
    if len(line) > 0 :
        # If the first char isn't whitespace, start a new entry, else append to
        # the old entry
        if line[0] != " ":
            entries.append(line)
        else:
            entries[-1] = entries[-1] + '\n' + (line)


# Merge entries of the same type
for entry in entries:
    parsedEntry = yaml.safe_load(entry)
    output = merge_dols(output, parsedEntry)

# Pretty print output
if len(output) == 0:
    print("No changes!")
else:
    for key in output:
        print("=" * (len(key) + 1))
        print(key + ':')
        print("=" * (len(key) + 1))
        for item in output[key]:
            print(item)
            print()
        print()
