=============================
Hardware Inventory Management
=============================

At its lowest level, hardware inventory is managed in the Bifrost service.

Reconfiguring Control Plane Hardware
====================================

If a server's hardware or firmware configuration is changed, it should be
re-inspected in Bifrost before it is redeployed into service. A single server
can be reinspected like this:

.. code-block:: console

   kayobe# kayobe overcloud hardware inspect --limit <Host name>

.. _enrolling-new-hypervisors:

Enrolling New Hypervisors
-------------------------

New hypervisors can be added to the Bifrost inventory by using its discovery
capabilities. Assuming that new hypervisors have IPMI enabled and are
configured to network boot on the provisioning network, the following commands
will instruct them to PXE boot. The nodes will boot on the Ironic Python Agent
kernel and ramdisk, which is configured to extract hardware information and
send it to Bifrost. Note that IPMI credentials can be found in the encrypted
file located at ``${KAYOBE_CONFIG_PATH}/secrets.yml``.

.. code-block:: console

   bifrost# ipmitool -I lanplus -U <ipmi username> -H <Hostname>-ipmi chassis bootdev pxe

If node is are off, power them on:

.. code-block:: console

   bifrost# ipmitool -I lanplus -U <ipmi username> -H <Hostname>-ipmi power on

If nodes is on, reset them:

.. code-block:: console

   bifrost# ipmitool -I lanplus -U <ipmi username> -H <Hostname>-ipmi power reset

Once node have booted and have completed introspection, they should be visible
in Bifrost:

.. code-block:: console

   bifrost# baremetal node list --provision-state enroll
   +--------------------------------------+-----------------------+---------------+-------------+--------------------+-------------+
   | UUID                                 | Name                  | Instance UUID | Power State | Provisioning State | Maintenance |
   +--------------------------------------+-----------------------+---------------+-------------+--------------------+-------------+
   | da0c61af-b411-41b9-8909-df2509f2059b | example-hypervisor-01 | None          | power off   | enroll             | False       |
   +--------------------------------------+-----------------------+---------------+-------------+--------------------+-------------+

After editing ``${KAYOBE_CONFIG_PATH}/overcloud.yml`` to add these new hosts to
the correct groups, import them in Kayobe's inventory with:

.. code-block:: console

   kayobe# kayobe overcloud inventory discover

We can then provision and configure them:

.. code-block:: console

   kayobe# kayobe overcloud provision --limit <Hostname>
   kayobe# kayobe overcloud host configure --limit <Hostname>
   kayobe# kayobe overcloud service deploy --limit <Hostname> --kolla-limit <Hostname>

Replacing a Failing Hypervisor
------------------------------

To replace a failing hypervisor, proceed as follows:

* :ref:`Disable the hypervisor to avoid scheduling any new instance on it <taking-a-hypervisor-out-of-service>`
* :ref:`Evacuate all instances <evacuating-all-instances>`
* :ref:`Set the node to maintenance mode in Bifrost <set-bifrost-maintenance-mode>`
* Physically fix or replace the node
* It may be necessary to reinspect the node if hardware was changed (this will require deprovisioning and reprovisioning)
* If the node was replaced or reprovisioned, follow :ref:`enrolling-new-hypervisors`

To deprovision an existing hypervisor, run:

.. code-block:: console

   kayobe# kayobe overcloud deprovision --limit <Hypervisor hostname>

.. warning::

   Always use ``--limit`` with ``kayobe overcloud deprovision`` on a production
   system. Running this command without a limit will deprovision all overcloud
   hosts.

.. _evacuating-all-instances:

Evacuating all instances
------------------------

.. code-block:: console

   admin# openstack server evacuate $(openstack server list --host <Hypervisor hostname> --format value --column ID)

You should now check the status of all the instances that were running on that
hypervisor. They should all show the status ACTIVE. This can be verified with:

.. code-block:: console

   admin# openstack server show <instance uuid>

Troubleshooting
===============

Servers that have been shut down
--------------------------------

If there are any instances that are SHUTOFF they won’t be migrated, but you can
use ``openstack server migrate`` for them once the live migration is finished.

Also if a VM does heavy memory access, it may take ages to migrate (Nova tries
to incrementally increase the expected downtime, but is quite conservative).
You can use ``openstack server migration force complete --os-compute-api-version 2.22 <instance_uuid>
<migration_id>`` to trigger the final move.

You get the migration ID via ``openstack server migration list --server <instance_uuid>``.

For more details see:
http://www.danplanet.com/blog/2016/03/03/evacuate-in-nova-one-command-to-confuse-us-all/

Flavors have changed
--------------------

If the size of the flavors has changed, some instances will also fail to
migrate as the process needs manual confirmation. You can do this with:

.. code-block:: console

   openstack # openstack server resize confirm <instance-uuid>

The symptom to look out for is that the server is showing a status of ``VERIFY
RESIZE`` as shown in this snippet of ``openstack server show <instance-uuid>``:

.. code-block:: console

   | status | VERIFY_RESIZE |

.. _set-bifrost-maintenance-mode:

Set maintenance mode on a node in Bifrost
-----------------------------------------

.. code-block:: console

   seed# docker exec -it bifrost_deploy /bin/bash
   (bifrost-deploy)[root@seed bifrost-base]# export OS_CLOUD=bifrost
   (bifrost-deploy)[root@seed bifrost-base]# baremetal node maintenance set <Hostname>

.. _unset-bifrost-maintenance-mode:

Unset maintenance mode on a node in Bifrost
-------------------------------------------

.. code-block:: console

   seed# docker exec -it bifrost_deploy /bin/bash
   (bifrost-deploy)[root@seed bifrost-base]# export OS_CLOUD=bifrost
   (bifrost-deploy)[root@seed bifrost-base]# baremetal node maintenance unset <Hostname>

Detect hardware differences with ADVise
=======================================

Hardware information captured during the Ironic introspection process can be
analysed to detect hardware differences, such as mismatches in firmware
versions or missing storage devices. The `ADVise <https://github.com/stackhpc/ADVise>`__
tool can be used for this purpose.

Extract Bifrost introspection data
----------------------------------

The ADVise tool assumes that hardware introspection data has already been gathered in JSON format.
The ``extra-hardware`` disk builder element enabled when building the IPA image for the required data to be available.

To build ipa image with extra-hardware  you need to edit ``ipa.yml`` and add this:
.. code-block:: console

   # Whether to build IPA images from source.
   ipa_build_images: true

   # List of additional Diskimage Builder (DIB) elements to use when building IPA
   images. Default is none.
   ipa_build_dib_elements_extra:
   - "extra-hardware"

   # List of additional inspection collectors to run.
   ipa_collectors_extra:
   - "extra-hardware"

Extract introspection data from Bifrost with Kayobe. JSON files will be created
into ``${KAYOBE_CONFIG_PATH}/overcloud-introspection-data``:

.. code-block:: console

   kayobe# kayobe overcloud introspection data save

Using ADVise
------------

The Ansible playbook ``advise-run.yml`` can be found at ``${KAYOBE_CONFIG_PATH}/ansible/advise-run.yml``.

The playbook will:

1. Install ADVise and dependencies
2. Run the mungetout utility for extracting the required information from the introspection data ready for use with ADVise.
3. Run ADVise on the data.

.. code-block:: console

   cd ${KAYOBE_CONFIG_PATH}
   ansible-playbook ${KAYOBE_CONFIG_PATH}/ansible/advise-run.yml

The playbook has the following optional parameters:

- venv : path to the virtual environment to use. Default: ``"~/venvs/advise-review"``
- input_dir: path to the hardware introspection data. Default: ``"{{ lookup('env', 'PWD') }}/overcloud-introspection-data"``
- output_dir: path to where results should be saved. Default: ``"{{ lookup('env', 'PWD') }}/review"``
- advise-pattern: regular expression to specify what introspection data should be analysed. Default: ``".*.eval"``

You can override them by provide new values with ``-e <variable>=<value>``

Example command to run the tool on data about the compute nodes in a system, where compute nodes are named cpt01, cpt02, cpt03…:

.. code-block:: console

    ansible-playbook advise-run.yml -e advise_pattern=’(cpt)(.*)(.eval)’


.. note::
    The mungetout utility will always use the file extension .eval

Using the results
-----------------

The ADVise tool will output a selection of results found under output_dir/results these include:

- ``.html`` files to display network visualisations of any hardware differences.
- The folder ``Paired_Comparisons`` which contains information on the shared and differing fields found between the systems.
  This is a reflection of the network visualisation webpage, with more detail as to what the differences are.
- ``_summary``, a listing of how the systems can be grouped into sets of identical hardware.
- ``_performance``, the results of analysing the benchmarking data gathered.
- ``_perf_summary``, a subset of the performance metrics, just showing any potentially anomalous data such as where variance
  is too high, or individual nodes have been found to over/underperform.

The ADVise tool will also launch an interactive Dash webpage, which displays the network visualisations,
tables with information on the differing hardware attributes, the performance metrics as a range of box-plots,
and specifies which individual nodes may be anomalous via box-plot outliers. This can be accessed at ``localhost:8050``.
To close this service, simply ``Ctrl+C`` in the terminal where you ran the playbook.

To get visuallised result, It is recommanded to copy instrospection data to your local machine then run ADVise playbook locally.

Recommanded Workflow
--------------------

1. Run the playbook as outlined above.
2. Open the Dash webpage at ``localhost:8050``.
3. Review the hardware differences. Note that hovering over a group will display the nodes it contains.
4. Identify any unexpected differences in the systems. If multiple differing fields exist they will be graphed separately.
   As an example, here we expected all compute nodes to be identical.
5. Use the dropdown menu beneath each graph to show a table of the differences found between two sets of groups.
   If required, information on shared fields can be found under ``output_dir/results/Paired_Comparisons``.
6. Scroll down the webpage to the performance review. Identify if any of the discovered performance results could be
   indicative of a larger issue.
7. Examine the ``_performance`` and ``_perf_summary`` files if you require any more information.
