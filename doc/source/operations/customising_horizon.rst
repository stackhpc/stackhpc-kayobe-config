.. include:: vars.rst

====================================
Customising Horizon
====================================

Horizon is the most frequent site-specific container customisation required:
other customisations tend to be common across deployments, but personalisation
of Horizon is unique to each institution.

This describes a simple process for customising the Horizon theme.

Creating a custom Horizon theme
-------------------------------

A simple custom theme for Horizon can be implemented as small modifications of
an existing theme, such as the `Default
<https://opendev.org/openstack/horizon/src/branch/master/openstack_dashboard/themes/default>`__
one.

A theme contains at least two files: ``static/_styles.scss``, which can be empty, and
``static/_variables.scss``, which can reference another theme like this:

.. code-block:: scss

   @import "/themes/default/variables";
   @import "/themes/default/styles";

Some resources such as logos can be overridden by dropping SVG image files into
``static/img`` (since the Ocata release, files must be SVG instead of PNG). See
`the Horizon documentation
<https://docs.openstack.org/horizon/latest/configuration/themes.html#customizing-the-logo>`__
for more details.

Content on some pages such as the splash (login) screen can be updated using
templates.

See `our example horizon-theme <https://github.com/stackhpc/horizon-theme>`__
which inherits from the default theme and includes:

* a custom splash screen logo
* a custom top-left logo
* a custom message on the splash screen

Further reading:

* https://docs.openstack.org/horizon/latest/configuration/customizing.html
* https://docs.openstack.org/horizon/latest/configuration/themes.html
* https://docs.openstack.org/horizon/latest/configuration/branding.html

Building a Horizon container image with custom theme
----------------------------------------------------

Building a custom container image for Horizon can be done by modifying
``kolla.yml`` to fetch the custom theme and include it in the image:

.. code-block:: yaml
   :substitutions:

   kolla_sources:
     horizon-additions-theme-<custom theme name>:
       type: "git"
       location: <custom theme repository url>
       reference: master

   kolla_build_blocks:
     horizon_footer: |
       # Binary images cannot use the additions mechanism.
       {% raw %}
       {% if install_type == 'source' %}
       ADD additions-archive /
       RUN mkdir -p /etc/openstack-dashboard/themes/<custom theme name> \
         && cp -R /additions/horizon-additions-theme-<custom theme name>-archive-master/* /etc/openstack-dashboard/themes/<custom theme name>/ \
         && chown -R horizon: /etc/openstack-dashboard/themes
       {% endif %}
       {% endraw %}

If using a specific container image tag, don't forget to set:

.. code-block:: yaml

   kolla_tag: mytag

Build the image with:

.. code-block:: console

   kayobe overcloud container image build horizon -e kolla_install_type=source --push

Pull the new Horizon container to the controller:

.. code-block:: console

   kayobe overcloud container image pull --kolla-tags horizon

Deploy and use the custom theme
-------------------------------

Switch to source image type in ``${KAYOBE_CONFIG_PATH}/kolla/globals.yml``:

.. code-block:: yaml

   horizon_install_type: source

You may also need to update the container image tag:

.. code-block:: yaml

   horizon_tag: mytag

Configure Horizon to include the custom theme and use it by default:

.. code-block:: console

   mkdir -p ${KAYOBE_CONFIG_PATH}/kolla/config/horizon/

Add to ``${KAYOBE_CONFIG_PATH}/kolla/config/horizon/custom_local_settings``:

.. code-block:: console

   AVAILABLE_THEMES = [
       ('default', 'Default', 'themes/default'),
       ('material', 'Material', 'themes/material'),
       ('<custom theme name>', '<custom theme visible name>', '/etc/openstack-dashboard/themes/<custom theme name>'),
   ]
   DEFAULT_THEME = '<custom theme name>'

You can also set other customisations in this file, such as the HTML title of the page:

.. code-block:: console

   SITE_BRANDING = "<Your Branding>"

Deploy with:

.. code-block:: console

   kayobe overcloud service reconfigure --kolla-tags horizon

Troubleshooting
---------------

Make sure you build source images, as binary images cannot use the addition
mechanism used here.

If the theme is selected but the logo doesn’t load, try running these commands
inside the ``horizon`` container:

.. code-block:: console

   /var/lib/kolla/venv/bin/python /var/lib/kolla/venv/bin/manage.py collectstatic --noinput --clear
   /var/lib/kolla/venv/bin/python /var/lib/kolla/venv/bin/manage.py compress --force
   settings_bundle | md5sum > /var/lib/kolla/.settings.md5sum.txt

Alternatively, try changing anything in ``custom_local_settings`` and restarting
the ``horizon`` container.

If the ``horizon`` container is restarting with the following error:

.. code-block:: console

   /var/lib/kolla/venv/bin/python /var/lib/kolla/venv/bin/manage.py compress --force
   CommandError: An error occurred during rendering /var/lib/kolla/venv/lib/python3.6/site-packages/openstack_dashboard/templates/horizon/_scripts.html: Couldn't find any precompiler in COMPRESS_PRECOMPILERS setting for mimetype '\'text/javascript\''.

It can be resolved by dropping cached content with ``docker restart
memcached``. Note this will log out users from Horizon, as Django sessions are
stored in Memcached.
