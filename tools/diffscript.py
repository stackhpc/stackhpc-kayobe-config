import subprocess
import os
import yaml

# Function to merge dictionaries of lists
def merge_dols(dol1, dol2):
    keys = set(dol1).union(dol2)
    no = []
    return dict((k, dol1.get(k, no) + dol2.get(k, no)) for k in keys)

entries = []
output = {}
index = 0

path = os.path.dirname(__file__)
#arg = sys.argv[1] if len(sys.argv) > 1 else ''

args = [' --kayobe', ' --kolla', ' --kollaansible', '--StackHPC-kayobe-config']
#args = ['']
# Loop through arguments and run the bash script for each one
for arg in args:
    print(arg)
    # Run shell script to get basic string with all applicable release notes
    results = subprocess.run([path + '/diffscript.sh', arg], stdout=subprocess.PIPE).stdout.decode()
    
    # Split output into list of entries
    for line in results.splitlines():
        print(line)
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

print("========= \nCompiled changes: ")
# Below compiles all changes from the repos into one features list and one fixes list. Was in Alex's script already and looks a bit nicer

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