# Copyright (c) 2017 StackHPC Ltd.
#
# Licensed under the Apache License, Version 2.0 (the "License"); you may
# not use this file except in compliance with the License. You may obtain
# a copy of the License at
#
#      http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS, WITHOUT
# WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied. See the
# License for the specific language governing permissions and limitations
# under the License.

# -*- coding: utf-8 -*-
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#    http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or
# implied.
# See the License for the specific language governing permissions and
# limitations under the License.

# -- StackHPC Kayobe configuration --------------------------------------
# Variables to override

current_series = "xena"
branch = f"stackhpc/{current_series}"

# Substitutions loader
rst_epilog = """
.. |current_release| replace:: {current_release}
.. |current_release_git_branch_name| replace:: {current_release_git_branch_name}
""".format(  # noqa: E501
    current_release_git_branch_name=branch,
    current_release=current_series,
)

# -- General configuration ----------------------------------------------------

# Add any Sphinx extension module names here, as strings. They can be
# extensions coming with Sphinx (named 'sphinx.ext.*') or your custom ones.
extensions = [
    'reno.sphinxext',
    #'sphinx.ext.autodoc',
    'sphinx.ext.extlinks',
    #'sphinx.ext.intersphinx',
    'sphinxcontrib.rsvgconverter',
]

# autodoc generation is a bit aggressive and a nuisance when doing heavy
# text edit cycles.
# execute "export SPHINX_DEBUG=1" in your terminal to disable

# The suffix of source filenames.
source_suffix = '.rst'

# The master toctree document.
master_doc = 'index'

# General information about the project.
project = 'stackhpc-kayobe-config'

# If true, '()' will be appended to :func: etc. cross-reference text.
add_function_parentheses = True

# If true, the current module name will be prepended to all description
# unit titles (such as .. function::).
add_module_names = True

# The name of the Pygments (syntax highlighting) style to use.
pygments_style = 'native'

# -- Options for HTML output --------------------------------------------------

# The theme to use for HTML and HTML Help pages.  Major themes that come with
# Sphinx are currently 'default' and 'sphinxdoc'.
# html_theme_path = []
html_theme = 'default'
# html_static_path = ['static']

# Add any paths that contain "extra" files, such as .htaccess or
# robots.txt.
# html_extra_path = ['_extra']

html_theme_options = {
    # "show_other_versions": True,
}

# Output file base name for HTML help builder.
htmlhelp_basename = '%sdoc' % project

# Grouping the document tree into LaTeX files. List of tuples
# (source start file, target name, title, author, documentclass
# [howto/manual]).
# latex_documents = [
#     ('index',
#      'doc-%s.tex' % project,
#      '%s Documentation' % project,
#      'OpenStack Foundation', 'manual'),
# ]

# Disable usage of xindy https://bugzilla.redhat.com/show_bug.cgi?id=1643664
latex_use_xindy = False

extlinks_projects = {
    "kayobe",
    "kolla",
    "kolla-ansible",
}

extlinks = {
    f"{project}-doc": (f"https://docs.openstack.org/{project}/{current_series}/", "%s documentation")
    for project in extlinks_projects
}
