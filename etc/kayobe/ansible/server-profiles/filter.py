#!/bin/env python

import json
import argparse
import fileinput
import re
import sys

def filter_attr(component, regexps):
    if not regexps:
        return component
    if "Attributes" not in component:
        # no attributes to filter
        return component
    attrs = component["Attributes"]
    component["Attributes"] = [x for x in attrs if re.match("|".join(regexps), x["Name"])]
    return component

if __name__ == "__main__":

    parser = argparse.ArgumentParser(description='Filter system configuration')
    parser.add_argument('--attr-filter', metavar='', nargs='*', action="append",
                        help='Filter attributes', default=[])
    parser.add_argument('--component-filter', metavar='', nargs='*', action="append",
                    help='Filter components', default=[])
    parser.add_argument('--input', metavar='', nargs='?', help='input file', default=[])

    args = parser.parse_args()
    # flatten
    component_filters = sum(args.component_filter, [])

    if len(component_filters) != len(args.attr_filter):
        print("Missing attr-filter for a component", sys.stderr)
        sys.exit(1)

    buffer = []
    for line in fileinput.input(args.input):
        buffer.append(line)

    content = json.loads("\n".join(buffer))
    components = content["SystemConfiguration"]["Components"]

    filtered = []
    for component in components:
        for i, regex in enumerate(component_filters):
            if re.match(regex, component["FQDD"]):
                filtered.append(filter_attr(component, args.attr_filter[i]))
    # [filter_attr(x, args.attr_filter[i]) for i, x in enumerate(components) if not component_filters or re.match("|".join(component_filters), x["FQDD"])]
    # filter_attr returns none on no attributes
    content["SystemConfiguration"]["Components"] = [x for x in filtered if x]

    print(json.dumps(content))

