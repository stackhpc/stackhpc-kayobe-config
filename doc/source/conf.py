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

current_series = "2025.1"
previous_series = "2024.1"
branch = f"stackhpc/{current_series}"
ceph_series = "squid"

# Substitutions loader
rst_prolog = """
.. |current_release| replace:: {current_release}
.. |current_release_git_branch_name| replace:: {current_release_git_branch_name}
.. |previous_release| replace:: {previous_release}
.. |ceph_series| replace:: {ceph_series}
""".format(  # noqa: E501
    current_release_git_branch_name=branch,
    current_release=current_series,
    previous_release=previous_series,
    ceph_series=ceph_series,
)

# -- General configuration ----------------------------------------------------

# Add any Sphinx extension module names here, as strings. They can be
# extensions coming with Sphinx (named 'sphinx.ext.*') or your custom ones.
extensions = [
    'sphinx_immaterial',
    'reno.sphinxext',
    #'sphinx.ext.autodoc',
    'sphinx.ext.extlinks',
    #'sphinx.ext.intersphinx',
    'sphinxcontrib.rsvgconverter',
    'sphinx_copybutton',
    'sphinx_substitution_extensions',
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
html_theme = 'sphinx_immaterial'
html_static_path = ['_static']
html_css_files = ['custom.css']

# Add any paths that contain "extra" files, such as .htaccess or
# robots.txt.
# html_extra_path = ['_extra']

html_theme_options = {
    "palette": [

        {
            "media": "(prefers-color-scheme: light)",
            "scheme": "default",
            "toggle": {
                "icon": "material/weather-sunny",
                "name": "Switch to dark mode",
            }
        },
        {
            "media": "(prefers-color-scheme: dark)",
            "scheme": "slate",
            "toggle": {
                "icon": "material/weather-night",
                "name": "Switch to system preference",
            }
        },
    ],
    "features": [
        "navigation.expand",
        "navigation.top",
        "navigation.footer",
        "search.suggest",
        "content.code.copy",
        "toc.follow",
        "toc.sticky",
    ]
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
    f"{project}-doc": (f"https://docs.openstack.org/{project}/{current_series}/%s", "%s documentation")
    for project in extlinks_projects
}
extlinks["skc-doc"] = (f"https://stackhpc-kayobe-config.readthedocs.io/en/stackhpc-{current_series}/%s", "%s documentation")
extlinks["kayobe-renos"] = (f"https://docs.openstack.org/releasenotes/kayobe/{current_series}.html%s", "%s release notes")
extlinks["kolla-ansible-renos"] = (f"https://docs.openstack.org/releasenotes/kolla-ansible/{current_series}.html%s", "%s release notes")
extlinks["ceph-doc"] = (f"https://docs.ceph.com/en/{ceph_series}/%s", "%s documentation")
