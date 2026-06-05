#!/usr/bin/env python3

from ansible.errors import AnsibleFilterError

class FilterModule(object):
    def filters(self):
        return {
            'group_hostvars_by_var':
            self.group_hostvars_by_var,
            'get_hostvars_by_host':
            self.get_hostvars_by_host
        }

    def group_hostvars_by_var(self, hostvars, var, subkey=None):
        """
        Returns a dictionary where the keys are values for the
        specified var in hostvars, and the values are the hosts
        that match that value.

        For example, a grouping of hosts by OS release might look like:
        distribution_release:
          noble:
            - node1
            - node2
          jammy:
            - node3
            - node4
            - node5

        Some Ansible commands, such as ansible.builtin.command, return a
        dict rather than a single value. So 'subkey' is used for these cases
        to access the desired value.
        """
        result = {}

        for host in hostvars.keys():
            try:
                indiv_host_var = hostvars[host][var]
                if subkey is not None:
                    indiv_host_var = indiv_host_var[subkey]
                result.setdefault(indiv_host_var, []).append(host)
            except KeyError as e:
                raise AnsibleFilterError(f"Variable {var} not found for host {host} in hostvars: {e}")

        return result

    def get_hostvars_by_host(self, hostvars, var, subkey=None):
        """
        Returns a dictionary where the keys are hosts and the values
        are the values for the specified var in hostvars.

        For example, the deployed containers by host might look like:
        deployed_containers:
            node1:
              - grafana
              - glance
              - nova
              - prometheus
            node2:
              - designate
              - neutron
              - nova
        
        Some Ansible commands, such as ansible.builtin.command, return a
        dict rather than a single value. So 'subkey' is used for these cases
        to access the desired value.
        """
        result = {}
        for host in hostvars.keys():
            try:
                indiv_host_var = hostvars[host][var]
                for key in indiv_host_var.keys():
                    # Check if task to assign value was skipped
                    if key == "skipped":
                        result[host] = "No data"
                        continue
                if subkey is not None:
                    indiv_host_var = indiv_host_var[subkey]
                if indiv_host_var:
                    result[host] = indiv_host_var
                else:
                    result[host] = []

            except KeyError as e:
                raise AnsibleFilterError(f"Variable {var} not found for host {host} in hostvars: {e}")

        return result
