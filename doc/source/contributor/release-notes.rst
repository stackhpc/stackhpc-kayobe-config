=============
Release notes
=============

StackHPC Kayobe configuration uses the following release notes sections:

- ``features`` --- for new features or functionality; these should ideally
  refer to the blueprint being implemented;
- ``fixes`` --- for fixes closing bugs; these must refer to the bug being
  closed;
- ``upgrade`` --- for notes relevant when upgrading from previous version;
  these should ideally be added only between major versions; required when
  the proposed change affects behaviour in a non-backwards compatible way or
  generally changes something impactful;
- ``deprecations`` --- to track deprecated features; relevant changes may
  consist of only the commit message and the release note;
- ``prelude`` --- filled in by the PTL before each release or RC.

Other release note types may be applied per common sense.
Each change should include a release note unless being a ``TrivialFix``
change or affecting only docs or CI. Such changes should `not` include
a release note to avoid confusion.
Remember release notes are mostly for end users which, in case of Kolla,
are OpenStack administrators/operators.

To add a release note, install the ``reno`` package in a Python virtual
environment, then run the following command:

.. code-block:: console

   reno new <summary-line-with-dashes>

Release notes for the current release are included in the :ref:`documentation`.
Note that a note won't be included in the generated documentation until it is
tracked by ``git``.

All release notes can be inspected by browsing ``releasenotes/notes``
directory.
