#!/usr/bin/env python3

import argparse
import os
import re

import pandas as pd


# Top-level node groups.
# This defines how to map node names to groups, and how they are connected to the network.
NODE_GROUPS = [
    {
        "name": "ceph-mon",
        "regex": "hb-cephmon[0-9]+",
        "networks": {
            "mgmt": "overcloud_idrac",
            "storage": "ceph_mon_template",
            "cluster": "ceph_mon_template",
        },
        "port_channel": True,
    },
    {
        "name": "ceph-osd",
        "regex": "hb-ceph-osd[0-9]+",
        "networks": {
            "mgmt": "overcloud_idrac",
            "storage": "ceph_osd_template",
            "cluster": "ceph_osd_template",
        },
        "port_channel": True,
    },
    {
        "name": "controllers",
        "regex": "hb-openstack-controller[0-9]+",
        "networks": {
            "mgmt": "overcloud_idrac_dedicated",
            "provision": "overcloud_provision_dedicated",
            "storage": "controller_template",
            "cluster": "controller_template",
        },
        "port_channel": True,
    },
    {
        "name": "compute",
        "regex": "hb-hypervisor[0-9]+",
        "networks": {
            "mgmt": "workload_idrac",
            "storage": "hypervisor_storage",
            "cluster": "hypervisor_data",
        },
    },
    {
        "name": "gpu",
        "regex": "hb-gpu[0-9]+",
        "networks": {
            "mgmt": "workload_idrac",
            "storage": "baremetal",
            "cluster": "baremetal",
        },
    },
    {
        "name": "mds",
        "regex": "hb-mds[0-9]+",
        "networks": {
            "mgmt": "lustre_idrac",
            "storage": "mds",
            "cluster": "mds",
        },
    },
    {
        "name": "memory",
        "regex": "hb-memory[0-9]+",
        "networks": {
            "mgmt": "workload_idrac",
            "storage": "baremetal",
            "cluster": "baremetal",
        },
    },
    {
        "name": "node",
        "regex": "hb-node[0-9]+",
        "networks": {
            "mgmt": "workload_idrac",
            "storage": "baremetal",
            "cluster": "baremetal",
        },
    },
    {
        "name": "oss",
        "regex": "hb-oss[0-9]+",
        "networks": {
            "mgmt": "lustre_idrac",
            "storage": "oss",
            "cluster": "oss",
        },
    },
    {
        "name": "proxmox",
        "regex": "hb-proxmox[0-9]+",
        "networks": {
            "mgmt": "proxmox",
            "storage": "proxmox",
            "cluster": "proxmox",
        },
    },
    {
        "name": "robinhood",
        "regex": "hb-robinhood[0-9]+",
        "networks": {
            "mgmt": "lustre_idrac",
            "storage": "robinhood",
            "cluster": "robinhood",
        },
    },
]


def init():
    pd.set_option('display.max_rows', None)
    pd.set_option('display.max_columns', None)
    pd.set_option('display.width', None)
    pd.set_option('display.max_colwidth', None)


def parse():
    parser = argparse.ArgumentParser()
    parser.add_argument("input")
    parser.add_argument("--switch")
    parser.add_argument("--out-path", default="etc/kayobe/environments/habrok/inventory/host_vars")
    return parser.parse_args()


def interface_key(series):
    """Map a series to a set of sort keys.

    "1/26" -> [1, 26]
    "Ethernet 1/2" -> [1, 2]
    """
    def key(interface):
        interface = re.sub("[a-zA-Z ]", "", interface)
        return [int(x) for x in re.split("[\:/]", interface)]

    return series.apply(key)


def get_node_group(nodename):
    for node_group in NODE_GROUPS:
        if re.match(node_group["regex"], nodename):
            return node_group
    else:
        raise Exception(f"Unknown node group for {nodename}")


def get_port_channel_id(row, network):
    interface = row[f"{network}trunk-switchport"]
    # Allow for up to 4 breakout ports
    if_number = interface.split("/")[-1]
    port_number = int(if_number.split(":")[0])
    if ":" in if_number:
        breakout_number = int(if_number.split(":")[1])
    else:
        breakout_number = 0
    return 4 * port_number + breakout_number - 1


def get_port_type(row, network, is_eth=True):
    node_group = get_node_group(row["nodename"])
    port_type = node_group["networks"][network]
    if network in {"storage", "cluster"} and node_group.get("port_channel"):
        channel = get_port_channel_id(row, network)
        # Port channel variables are templates, which we need to format then convert from YAML.
        if is_eth:
            # Port channel member
            return f"lag_member_edge_template | format(channel={channel}, flowcontrol='on') | from_yaml"
        else:
            # Port channel
            return f"{port_type} | format(channel={channel}) | from_yaml"
    return port_type


def is_port_channel(row):
    return get_node_group(row["nodename"]).get("port_channel")


def write_preamble(f):
    f.write("""# This file has been autogenerated by tools/gen-switch-interfaces.py.

switch_interface_config_autogenerated:""")


def write_mgmt_if(f, row):
    port_type = get_port_type(row, "mgmt")
    f.write(
f"""  "Ethernet 1/{row["idrac-switchport"]}":
    description: {row["nodename"]}
    config: "{{{{ switch_interface_config_{port_type} }}}}"
""")


def write_provision_if(f, row):
    port_type = get_port_type(row, "provision")
    f.write(
f"""  "Ethernet 1/{row["management-switchport"]}":
    description: {row["nodename"]}
    config: "{{{{ switch_interface_config_{port_type} }}}}"
""")


def write_storage_if(f, row):
    port_type = get_port_type(row, "storage")
    f.write(
f"""  "{row["storagetrunk-switchport"]}":
    description: {row["nodename"]}
    config: "{{{{ switch_interface_config_{port_type} }}}}"
""")


def write_cluster_if(f, row):
    port_type = get_port_type(row, "cluster")
    f.write(
f"""  "{row["clustertrunk-switchport"]}":
    description: {row["nodename"]}
    config: "{{{{ switch_interface_config_{port_type} }}}}"
""")


def write_storage_port_channel(f, row):
    port_type = get_port_type(row, "storage", False)
    channel = get_port_channel_id(row, "storage")
    f.write(
f"""  "port-channel {channel}":
    description: {row["nodename"]}
    config: "{{{{ switch_interface_config_{port_type} }}}}"
""")


def write_cluster_port_channel(f, row):
    port_type = get_port_type(row, "cluster", False)
    channel = get_port_channel_id(row, "cluster")
    f.write(
f"""  "port-channel {channel}":
    description: {row["nodename"]}
    config: "{{{{ switch_interface_config_{port_type} }}}}"
""")


def main():
    init()
    parsed_args = parse()
    dtypes = {
        "idrac-switch": str,
        "storagetrunk-switch": str,
        "clustertrunk-switch": str,
    }
    df = pd.read_csv(parsed_args.input, sep='\t', dtype=dtypes)

    # Management switch config
    mgmt_switches = sorted(df['idrac-switch'].unique())
    for ms in mgmt_switches:
        if parsed_args.switch and ms != parsed_args.switch:
            continue
        ms_df = df.query('`idrac-switch` == @ms')
        if parsed_args.switch:
            ms_df = ms_df.query("`idrac-switch` == @parsed_args.switch")
        columns = ["nodename", "idrac-switchport", "management-switchport"]
        ms_df = ms_df[columns].dropna().sort_values(by=['idrac-switchport'], key=interface_key)
        try:
           os.makedirs(f"{parsed_args.out_path}/{ms}")
        except FileExistsError:
           pass
        path = f"{parsed_args.out_path}/{ms}/switch-config.yml"
        print("Writing", ms, "interfaces to", path)
        with open(path, "w") as f:
            write_preamble(f)
            empty = True
            for _, row in ms_df.iterrows():
                if empty:
                    f.write("\n")
                    empty = False
                write_mgmt_if(f, row)
                if row['idrac-switchport'] != row['management-switchport']:
                    write_provision_if(f, row)
            if empty:
                f.write(" []\n")

    # Leaf switch config
    leaf_switches = sorted(set(list(df['storagetrunk-switch'].dropna()) + list(df['clustertrunk-switch'].dropna())))
    for ls in leaf_switches:
        if parsed_args.switch and ls != parsed_args.switch:
            continue
        columns = ["nodename", "storagetrunk-switchport", "clustertrunk-switchport"]
        ss_df = df.query('`storagetrunk-switch` == @ls')
        ss_df = ss_df[columns].dropna().sort_values(by=['storagetrunk-switchport'], key=interface_key)
        cs_df = df.query('`clustertrunk-switch` == @ls')
        cs_df = cs_df[columns].dropna().sort_values(by=['clustertrunk-switchport'], key=interface_key)
        path = f"{parsed_args.out_path}/{ls}.yml"
        print("Writing", ls, "interfaces to", path)
        with open(path, "w") as f:
            write_preamble(f)
            empty = True
            for _, row in ss_df.iterrows():
                if is_port_channel(row):
                    if empty:
                        f.write("\n")
                        empty = False
                    write_storage_port_channel(f, row)
            for _, row in cs_df.iterrows():
                if is_port_channel(row):
                    if empty:
                        f.write("\n")
                        empty = False
                    write_cluster_port_channel(f, row)
            for _, row in ss_df.iterrows():
                if empty:
                    f.write("\n")
                    empty = False
                write_storage_if(f, row)
            for _, row in cs_df.iterrows():
                if empty:
                    f.write("\n")
                    empty = False
                write_cluster_if(f, row)
            if empty:
                f.write(" []\n")


if __name__ == "__main__":
    main()
