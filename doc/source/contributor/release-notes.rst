=============
Release notes
=============

To add a release note, install the ``reno`` package in a Python virtual
environment, then run the following command:

.. code-block:: console

   reno new <summary-line-with-dashes>

Writing release notes
=====================

Release notes are read by operators deciding what an update means for their
cloud, not by the reviewers of a PR. Each note should answer two questions:
what is different, and do I need to do anything? Remember, the note should make
sense to someone who has never seen the PR.

When to add a release note
--------------------------

Add a release note for any change that affects a deployment, including
container image updates and dependency bumps. If it affects the end user,
(StackHPC employees or customers, OpenStack Administrators/Operators), it needs
a release note.

If it *only* affects maintainers of ``stackhpc-kayobe-config``, it does not
need a release note. Do not add a release note for changes that only affect
docs or CI.

Style
-----

Release notes are formatted as a list, for users to read before they upgrade.
Their objective is to be clear and naturally readable.

- **Describe the result, not the action.** Lead with the thing that changed,
  and say how it is now. Avoid commit-message style such as "Bumps X",
  "Adds Y" or "Makes X do Y".
- **Describe fixes by the symptom users saw**, not by the code that changed.
- **One change per bullet point.** A section can contain several items, so split
  unrelated changes rather than combining them in one paragraph.
- **Upgrade notes must say what to do.** Name the variable, file or command
  involved, and what happens if no action is taken.
- **Keep it short.** One to three sentences is usually enough. If you find
  yourself writing more, split it into more bullet points, or link to a docs
  page. instead
- Use double backtics: `````` for ``variables``, ``files``, ``commands`` and
  ``versions``, and to use links in text (```Kolla fix <https://...>`__``)
  rather than bare URLs.

Which section to use
--------------------

- **features**: new functionality.
- **fixes**: bug fixes, including pulling in fixes from upstream.
- **upgrade**: Anything that requires action or changes
  behaviour on upgrade. **This is not for dependency bumps**.
- **security**: CVE fixes and accepted vulnerabilities.
- **deprecations**: features or variables that will be removed.

Examples
--------

Instead of:

.. code-block:: yaml

    upgrade:
    - |
        Updates Magnum CAPI Helm driver version to v1.4.0
    fixes:
    - |
        Resolves issue with Magnum tenant cluster being incorrectly
        reported as unhealthy

Write:

.. code-block:: yaml

    features:
    - |
        The Magnum CAPI Helm driver has been updated to
        `v1.4.0 <https://...>`__.
    fixes:
    - |
        Magnum tenant clusters are no longer incorrectly reported as
        unhealthy.

Instead of:

.. code-block:: yaml

    fixes:
    - |
        Swap usage warning message now correctly displays percentage of swap used
        Network packets dropped now uses ``rate()`` instead of ``irate()``

Write:

.. code-block:: yaml

    fixes:
    - |
        The swap usage alert now shows the correct percentage of swap in use.
    - |
        The network packets dropped alert is less likely to fire on brief
        spikes, as it now uses ``rate()`` instead of ``irate()``.

Release notes for the current release are included in the :ref:`documentation`.
Note that a note won't be included in the generated documentation until it is
tracked by ``git``.

All release notes can be inspected by browsing ``releasenotes/notes``
directory.
