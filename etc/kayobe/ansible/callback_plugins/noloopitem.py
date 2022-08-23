__metaclass__ = type

DOCUMENTATION = '''
    callback: noloopitem
    type: stdout
    short_description: Strips loop item on failure
    description:
        - Extends default to strip loop item on failure. This can
          leak sensitive information. no_log makes debugging too
          hard.
    extends_documentation_fragment:
      - default_callback
    requirements:
      - set as noloopitem in configuration
'''

from ansible.plugins.callback.default import CallbackModule as DefaultCallback

class CallbackModule(DefaultCallback):

    '''
    Extends the default callback plugin to strip loop item.
    '''

    CALLBACK_VERSION = 1.0
    CALLBACK_TYPE = 'stdout'
    CALLBACK_NAME = 'noloopitem'

    def v2_runner_item_on_failed(self, result):
        result._result.pop("item")
        super(CallbackModule, self).v2_runner_item_on_failed(result)
