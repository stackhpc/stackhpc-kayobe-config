# Contributing to Scientific Openstack
We love your input! We want to make contributing to this project as easy and transparent as possible, whether it's:

- Reporting a bug
- Discussing the current state of the code
- Submitting a fix
- Proposing new features
- Becoming a maintainer

## We Develop with Gitlab
We use gitlab to host code, to track issues and feature requests, as well as accept merge requests.

## We Use [a variant of Git Flow](https://docs.gitlab.com/ee/topics/gitlab_flow.html), So All Code Changes Happen Through Merge Requests
Merge requests are the best way to propose changes to the codebase. We actively welcome your merge requests:

1. Fork the repo and create your branch from the current default branch. Currently this is: `scientific-openstack/wallaby`.
2. If you've added code that should be tested, add tests.
3. If you've add functionality, update the documentation.
4. Ensure the test suite passes.
5. Make sure your code lints.
6. Issue that merge request!

Updating older branches:

If your change affects all branches:

1. Follow the steps for integrating your code (as outlined above) into the current default branch.
2. Once this has merged, cherry-pick the change back to all release branches up to and including your target branch.
   E.g if you require the fix in `scientific-openstack/ussuri` and the current default is `scientific-openstack/wallaby`,
   you need cherry-pick the change to the following branches:
    - `scientific-openstack/victoria`
    - `scientific-openstack/ussuri`
3. Each merge request will trigger CI. Ensure this passes.

If your change only affects a single branch:

1. Fork the repo and create your branch from the target branch.
2. Issue that merge request!
3. Ensure the test suite passes.
4. Make sure your code lints.

## Any contributions you make will be under the Apache 2.0 Software License
In short, when you submit code changes, your submissions are understood to be under the same [Apache 2.0 License](https://choosealicense.com/licenses/apache-2.0/) that covers the project. Feel free to contact the maintainers if that's a concern.

## Report bugs using Gitlab's [issues](https://gitlab.com/scientific-openstack/infrastructure/kayobe-config/-/issues?sort=created_date)
We use Gitlab issues to track public bugs. Report a bug by [opening a new issue](); it's that easy!

## Write bug reports with detail, background, and sample code

**Great Bug Reports** tend to have:

- A quick summary and/or background
- Steps to reproduce
  - Be specific!
  - Give sample code if you can. [My stackoverflow question](http://stackoverflow.com/q/12488905/180626) includes sample code that *anyone* with a base R setup can run to reproduce what I was seeing
- What you expected would happen
- What actually happens
- Notes (possibly including why you think this might be happening, or stuff you tried that didn't work)

People *love* thorough bug reports. I'm not even kidding.

## Use a Consistent Coding Style

* You can run `yamllint` to check for style violations
  - This is run via CI. No other jobs will run if this job fails.
  - **Note**: This doesn't support yaml with jinja templating, so you may need to disable the linting on certain files.
* 2 spaces for indentation rather than tabs

## License
By contributing, you agree that your contributions will be licensed under its Apache 2.0 License.

## External code

This source code in this repository references source code from several
external sources. Please follow the contribution guide for that particular
project. It is possible to update the configuration to reference a different
repository and/or version. Use this functionality to test changes.

### Kolla-ansible

Quick reference:

* StackHPC maintained fork
* Please submit bug reports using the upstream bug tracker first.
* Issues related to StackHPC maintained additions should be raised against the StackHPC GitHub repository.

Code:

* Repository: https://github.com/stackhpc/kolla
* Branch: stackhpc/wallaby

### kolla

Quick reference:

* StackHPC maintained fork
* Please submit bug reports using the upstream bug tracker first.
* Issues related to StackHPC maintained additions should be raised against the StackHPC GitHub repository.

Code:

* Repository: https://github.com/stackhpc/kolla
* Branch: stackhpc/wallaby

### kayobe

Quick reference:

* Scientific OpenStack maintained fork, but looking to mainline the changes.
* Please submit bug reports using the upstream bug tracker first.
* Issues related to Scientific Openstack maintained additions should be raised against the Scientific Openstack Gitlab repository.

Code:

* Repository: https://gitlab.com/scientific-openstack/infrastructure/kayobe
* Branch: scientific-openstack/wallaby

## References
This document was adapted from the open-source contribution guidelines for [Facebook's Draft](https://github.com/facebook/draft-js/blob/a9316a723f9e918afde44dea68b5f9f39b7d9b00/CONTRIBUTING.md)
