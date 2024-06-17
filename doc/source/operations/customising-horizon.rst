===================
Customising Horizon
===================

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

Adding the custom theme
-----------------------

Create a directory and transfer custom theme files to it ``$KAYOBE_CONFIG_PATH/kolla/config/horizon/themes/<custom theme name>``.

Define the custom theme in ``etc/kayobe/kolla/globals.yml``

.. code-block:: yaml
   horizon_custom_themes:
      - name: <custom theme name>
        label: <custom theme label> # This will be the visible name to users

Deploy and use the custom theme
-------------------------------

Configure Horizon to include the custom theme and use it by default:

.. code-block:: console

   mkdir -p $KAYOBE_CONFIG_PATH/kolla/config/horizon/

Create file ``$KAYOBE_CONFIG_PATH/kolla/config/horizon/custom_local_settings`` and add followings

.. code-block:: console

   AVAILABLE_THEMES = [
       ('default', 'Default', 'themes/default'),
       ('material', 'Material', 'themes/material'),
       ('<custom theme name>', '<custom theme label>', 'themes/<custom theme name>'),
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
