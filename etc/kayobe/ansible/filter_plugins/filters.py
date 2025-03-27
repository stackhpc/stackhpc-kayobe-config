#!/usr/bin/env python3

from ansible.errors import AnsibleFilterError
from ansible.plugins.filter.core import to_bool

class FilterModule(object):
    def filters(self):
        return {
            'select_enabled': self.select_enabled
        }

    def select_enabled(self, items: list[dict], key: str = 'items') -> list:
        """Filters a list of dictionaries to select enabled items.

        Parameters:
            items:
                List of dictionaries - Each item contains an 'enabled' key, and
                a key matching the "key" parameter.
            key:
                String - The key in each dictionary to extract when 'enabled'
                is true.
        
        Returns:
            A list of values from the specified key in each dictionary where
            'enabled' is true. List values are flattened.
        """
        result = []
        for item in items:
            try:
                if to_bool(item["enabled"]):
                    result += item[key] if isinstance(item[key], list) else [item[key]]
            except KeyError as e:
                raise AnsibleFilterError("Key %s not found in item: %s" % (e, item))
        return result
