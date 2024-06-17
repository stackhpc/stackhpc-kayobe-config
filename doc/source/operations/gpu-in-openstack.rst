=============================
Support for GPUs in OpenStack
=============================

NVIDIA Virtual GPU
##################

BIOS configuration
------------------

Intel
^^^^^

* Enable `VT-x` in the BIOS for virtualisation support.
* Enable `VT-d` in the BIOS for IOMMU support.

Dell
^^^^

Enabling SR-IOV with `racadm`:

.. code:: shell

    /opt/dell/srvadmin/bin/idracadm7 set BIOS.IntegratedDevices.SriovGlobalEnable Enabled
    /opt/dell/srvadmin/bin/idracadm7 jobqueue create BIOS.Setup.1-1
    <reboot>


Obtain driver from NVIDIA licensing portal
-------------------------------------------

Download Nvidia GRID driver from `here <https://docs.nvidia.com/grid/latest/grid-software-quick-start-guide/index.html#redeeming-pak-and-downloading-grid-software>`__
(This requires a login). The file can either be placed on the :ref:`ansible control host<NVIDIA control host>` or :ref:`uploaded to pulp<NVIDIA Pulp>`.

.. _NVIDIA Pulp:

Uploading the GRID driver to pulp
---------------------------------

Uploading the driver to pulp will make it possible to run kayobe from any host. This can be useful when
running in a CI environment.

.. code:: shell

    pulp artifact upload --file ~/NVIDIA-GRID-Linux-KVM-525.105.14-525.105.17-528.89.zip
    pulp file content create --relative-path "NVIDIA-GRID-Linux-KVM-525.105.14-525.105.17-528.89.zip" --sha256 c8e12c15b881df35e618bdee1f141cbfcc7e112358f0139ceaa95b48e20761e0
    pulp file repository create --name nvidia
    pulp file repository content add --repository nvidia --sha256 c8e12c15b881df35e618bdee1f141cbfcc7e112358f0139ceaa95b48e20761e0 --relative-path "NVIDIA-GRID-Linux-KVM-525.105.14-525.105.17-528.89.zip"
    pulp file publication create --repository nvidia
    pulp file distribution create --name nvidia --base-path nvidia --repository nvidia

The file will then be available at ``<pulp_url>/pulp/content/nvidia/NVIDIA-GRID-Linux-KVM-525.105.14-525.105.17-528.89.zip``. You
will need to set the ``vgpu_driver_url`` configuration option to this value:

.. code:: yaml

   # URL of GRID driver in pulp
   vgpu_driver_url: "{{ pulp_url }}/pulp/content/nvidia/NVIDIA-GRID-Linux-KVM-525.105.14-525.105.17-528.89.zip"

See :ref:`NVIDIA Role Configuration`.

.. _NVIDIA control host:

Placing the GRID driver on the ansible control host
---------------------------------------------------

Copy the driver bundle to a known location on the ansible control host. Set the ``vgpu_driver_url`` configuration variable to reference this
path using ``file`` as the url scheme e.g:

.. code:: yaml

    # Location of NVIDIA GRID driver on localhost
    vgpu_driver_url: "file://{{ lookup('env', 'HOME') }}/NVIDIA-GRID-Linux-KVM-525.105.14-525.105.17-528.89.zip"

See :ref:`NVIDIA Role Configuration`.

.. _NVIDIA OS Configuration:

OS Configuration
----------------

Host OS configuration is done by using roles in the `stackhpc.linux <https://github.com/stackhpc/ansible-collection-linux>`_ ansible collection.

Add the following to your ansible ``requirements.yml``:

.. code-block:: yaml
   :caption: $KAYOBE_CONFIG_PATH/ansible/requirements.yml

    #FIXME: Update to known release When VGPU and IOMMU roles have landed
    collections:
      - name: stackhpc.linux
        source: git+https://github.com/stackhpc/ansible-collection-linux.git,preemptive/vgpu-iommu
        type: git

Create a new playbook or update an existing on to apply the roles:

.. code-block:: yaml
   :caption: $KAYOBE_CONFIG_PATH/ansible/host-configure.yml

    ---

      - hosts: iommu
        tags:
          - iommu
        tasks:
          - import_role:
              name: stackhpc.linux.iommu
        handlers:
          - name: reboot
            set_fact:
              kayobe_needs_reboot: true

      - hosts: vgpu
        tags:
          - vgpu
        tasks:
          - import_role:
              name: stackhpc.linux.vgpu
        handlers:
          - name: reboot
            set_fact:
              kayobe_needs_reboot: true

      - name: Reboot when required
        hosts: iommu:vgpu
        tags:
          - reboot
        tasks:
          - name: Reboot
            reboot:
              reboot_timeout: 3600
            become: true
            when: kayobe_needs_reboot | default(false) | bool

Ansible Inventory Configuration
-------------------------------

Add some hosts into the ``vgpu`` group. The example below maps two custom
compute groups, ``compute_multi_instance_gpu`` and ``compute_vgpu``,
into the ``vgpu`` group:

.. code-block:: yaml
   :caption: $KAYOBE_CONFIG_PATH/inventory/custom

    [compute]
    [compute_multi_instance_gpu]
    [compute_vgpu]

    [vgpu:children]
    compute_multi_instance_gpu
    compute_vgpu

    [iommu:children]
    vgpu

Having multiple groups is useful if you want to be able to do conditional
templating in ``nova.conf`` (see :ref:`NVIDIA Kolla Ansible
Configuration`). Since the vgpu role requires iommu to be enabled, all of the
hosts in the ``vgpu`` group are also added to the ``iommu`` group.

If using bifrost and the ``kayobe overcloud inventory discover`` mechanism,
hosts can automatically be mapped to these groups by configuring
``overcloud_group_hosts_map``:

.. code-block:: yaml
   :caption: ``$KAYOBE_CONFIG_PATH/overcloud.yml``

    overcloud_group_hosts_map:
      compute_vgpu:
        - "computegpu000"
      compute_mutli_instance_gpu:
        - "computegpu001"

.. _NVIDIA Role Configuration:

Role Configuration
^^^^^^^^^^^^^^^^^^

Configure the location of the NVIDIA driver:

.. code-block:: yaml
   :caption: $KAYOBE_CONFIG_PATH/vgpu.yml

    ---

    vgpu_driver_url: "http://{{ pulp_url }}/pulp/content/nvidia/NVIDIA-GRID-Linux-KVM-525.105.14-525.105.17-528.89.zip"

Configure the VGPU devices:

.. code-block:: yaml
   :caption: $KAYOBE_CONFIG_PATH/inventory/group_vars/compute_vgpu/vgpu

    #nvidia-692 GRID A100D-4C
    #nvidia-693 GRID A100D-8C
    #nvidia-694 GRID A100D-10C
    #nvidia-695 GRID A100D-16C
    #nvidia-696 GRID A100D-20C
    #nvidia-697 GRID A100D-40C
    #nvidia-698 GRID A100D-80C
    #nvidia-699 GRID A100D-1-10C
    #nvidia-700 GRID A100D-2-20C
    #nvidia-701 GRID A100D-3-40C
    #nvidia-702 GRID A100D-4-40C
    #nvidia-703 GRID A100D-7-80C
    #nvidia-707 GRID A100D-1-10CME
    vgpu_definitions:
        # Configuring a MIG backed VGPU
        - pci_address: "0000:17:00.0"
          virtual_functions:
            - mdev_type: nvidia-700
              index: 0
            - mdev_type: nvidia-700
              index: 1
            - mdev_type: nvidia-700
              index: 2
            - mdev_type: nvidia-699
              index: 3
          mig_devices:
            "1g.10gb": 1
            "2g.20gb": 3
        # Configuring a card in a time-sliced configuration (non-MIG backed)
        - pci_address: "0000:65:00.0"
          virtual_functions:
            - mdev_type: nvidia-697
              index: 0
            - mdev_type: nvidia-697
              index: 1

Running the playbook
^^^^^^^^^^^^^^^^^^^^

The playbook defined in the :ref:`previous step<NVIDIA OS Configuration>`
should be run after `kayobe overcloud host configure` has completed. This will
ensure the host has been fully bootstrapped. With default settings, internet
connectivity is required to download `MIG Partition Editor for NVIDIA GPUs`. If
this is not desirable, you can override the one of the following variables
(depending on host OS):

.. code-block:: yaml
   :caption: $KAYOBE_CONFIG_PATH/inventory/group_vars/compute_vgpu/vgpu

   vgpu_nvidia_mig_manager_rpm_url: "https://github.com/NVIDIA/mig-parted/releases/download/v0.5.1/nvidia-mig-manager-0.5.1-1.x86_64.rpm"
   vgpu_nvidia_mig_manager_deb_url: "https://github.com/NVIDIA/mig-parted/releases/download/v0.5.1/nvidia-mig-manager_0.5.1-1_amd64.deb"

For example, you may wish to upload these artifacts to the local pulp.

Run the playbook that you defined earlier:

.. code-block:: shell

  kayobe playbook run $KAYOBE_CONFIG_PATH/ansible/host-configure.yml

Note: This will reboot the hosts on first run.

The playbook may be added as a hook in ``$KAYOBE_CONFIG_PATH/hooks/overcloud-host-configure/post.d``; this will
ensure you do not forget to run it when hosts are enrolled in the future.

.. _NVIDIA Kolla Ansible Configuration:

Kolla-Ansible configuration
^^^^^^^^^^^^^^^^^^^^^^^^^^^

To use the mdev devices that were created, modify nova.conf to add a list of mdev devices that
can be passed through to guests:

.. code-block::
   :caption: $KAYOBE_CONFIG_PATH/kolla/config/nova/nova-compute.conf

    {% if inventory_hostname in groups['compute_multi_instance_gpu'] %}
    [devices]
    enabled_mdev_types = nvidia-700, nvidia-699

    [mdev_nvidia-700]
    device_addresses = 0000:21:00.4,0000:21:00.5,0000:21:00.6,0000:81:00.4,0000:81:00.5,0000:81:00.6
    mdev_class = CUSTOM_NVIDIA_700

    [mdev_nvidia-699]
    device_addresses = 0000:21:00.7,0000:81:00.7
    mdev_class = CUSTOM_NVIDIA_699

    {% elif inventory_hostname in groups['compute_vgpu'] %}
    [devices]
    enabled_mdev_types = nvidia-697

    [mdev_nvidia-697]
    device_addresses = 0000:21:00.4,0000:21:00.5,0000:81:00.4,0000:81:00.5
    # Custom resource classes don't work when you only have single resource type.
    mdev_class = VGPU

    {% endif %}

You will need to adjust the PCI addresses to match the virtual function
addresses. These can be obtained by checking the mdevctl configuration after
running the role:

.. code-block:: shell

   # mdevctl list

   73269d0f-b2c9-438d-8f28-f9e4bc6c6995 0000:17:00.4 nvidia-700 manual (defined)
   dc352ef3-efeb-4a5d-a48e-912eb230bc76 0000:17:00.5 nvidia-700 manual (defined)
   a464fbae-1f89-419a-a7bd-3a79c7b2eef4 0000:17:00.6 nvidia-700 manual (defined)
   f3b823d3-97c8-4e0a-ae1b-1f102dcb3bce 0000:17:00.7 nvidia-699 manual (defined)
   330be289-ba3f-4416-8c8a-b46ba7e51284 0000:65:00.4 nvidia-700 manual (defined)
   1ba5392c-c61f-4f48-8fb1-4c6b2bbb0673 0000:65:00.5 nvidia-700 manual (defined)
   f6868020-eb3a-49c6-9701-6c93e4e3fa9c 0000:65:00.6 nvidia-700 manual (defined)
   00501f37-c468-5ba4-8be2-8d653c4604ed 0000:65:00.7 nvidia-699 manual (defined)

The mdev_class maps to a resource class that you can set in your flavor definition.
Note that if you only define a single mdev type on a given hypervisor, then the
mdev_class configuration option is silently ignored and it will use the ``VGPU``
resource class (bug?).

Map through the kayobe inventory groups into kolla:

.. code-block:: yaml
   :caption: $KAYOBE_CONFIG_PATH/kolla.yml

    kolla_overcloud_inventory_top_level_group_map:
      control:
        groups:
          - controllers
      network:
        groups:
          - network
      compute_cpu:
        groups:
          - compute_cpu
      compute_gpu:
        groups:
          - compute_gpu
      compute_multi_instance_gpu:
        groups:
          - compute_multi_instance_gpu
      compute_vgpu:
        groups:
          - compute_vgpu
      compute:
        groups:
          - compute
      monitoring:
        groups:
          - monitoring
      storage:
        groups:
          "{{ kolla_overcloud_inventory_storage_groups }}"

Where the ``compute_<suffix>`` groups have been added to the kayobe defaults.

You will need to reconfigure nova for this change to be applied:

.. code-block:: shell

  kayobe overcloud service deploy -kt nova --kolla-limit compute_vgpu

Openstack flavors
^^^^^^^^^^^^^^^^^

Define some flavors that request the resource class that was configured in nova.conf.
An example definition, that can be used with ``openstack.cloud.compute_flavor`` Ansible module,
is shown below:

.. code-block:: yaml

  vgpu_a100_2g_20gb:
    name: "vgpu.a100.2g.20gb"
    ram: 65536
    disk: 30
    vcpus: 8
    is_public: false
    extra_specs:
      hw:cpu_policy: "dedicated"
      hw:cpu_thread_policy: "prefer"
      hw:mem_page_size: "1GB"
      hw:cpu_sockets: 2
      hw:numa_nodes: 8
      hw_rng:allowed: "True"
      resources:CUSTOM_NVIDIA_700: "1"

You now should be able to launch a VM with this flavor.

NVIDIA License Server
^^^^^^^^^^^^^^^^^^^^^

The Nvidia delegated license server is a virtual machine based appliance. You simply need to boot an instance
using the image supplied on the NVIDIA Licensing portal. This can be done on the OpenStack cloud itself. The
requirements are:

* All tenants wishing to use GPU based instances must have network connectivity to this machine. (network licensing)
  - It is possible to configure node locked licensing where tenants do not need access to the license server
* Satisfy minimum requirements detailed `here <https://docs.nvidia.com/license-system/dls/2.1.0/nvidia-dls-user-guide/index.html#dls-virtual-appliance-platform-requirements>`__.

The official documentation for configuring the instance
can be found `here <https://docs.nvidia.com/license-system/dls/2.1.0/nvidia-dls-user-guide/index.html#about-service-instances>`__.

Below is a snippet of openstack-config for defining a project, and a security group that can be used for a non-HA deployment:

.. code-block:: yaml

  secgroup_rules_nvidia_dls:
    # Allow ICMP (for ping, etc.).
    - ethertype: IPv4
      protocol: icmp
    # Allow SSH.
    - ethertype: IPv4
      protocol: tcp
      port_range_min: 22
      port_range_max: 22
    # https://docs.nvidia.com/license-system/latest/nvidia-license-system-user-guide/index.html
    - ethertype: IPv4
      protocol: tcp
      port_range_min: 443
      port_range_max: 443
    - ethertype: IPv4
      protocol: tcp
      port_range_min: 80
      port_range_max: 80
    - ethertype: IPv4
      protocol: tcp
      port_range_min: 7070
      port_range_max: 7070

    secgroup_nvidia_dls:
      name: nvidia-dls
      project: "{{ project_cloud_services.name }}"
      rules: "{{ secgroup_rules_nvidia_dls }}"

    openstack_security_groups:
      - "{{ secgroup_nvidia_dls }}"

    project_cloud_services:
      name: "cloud-services"
      description: "Internal Cloud services"
      project_domain: default
      user_domain: default
      users: []
      quotas: "{{ quotas_project }}"

Booting the VM:

.. code-block:: shell

  # Uploading the image and making it available in the cloud services project
  $ openstack image create --file nls-3.0.0-bios.qcow2 nls-3.0.0-bios --disk-format qcow2
  $ openstack image add project nls-3.0.0-bios cloud-services
  $ openstack image set --accept nls-3.0.0-bios --project cloud-services
  $ openstack image member list nls-3.0.0-bios

  # Booting a server as the admin user in the cloud-services project. We pre-create the port so that
  # we can recreate it without changing the MAC address.
  $ openstack port create --mac-address fa:16:3e:a3:fd:19 --network external nvidia-dls-1 --project cloud-services
  $ openstack role add member --project cloud-services --user admin
  $ export OS_PROJECT_NAME=cloud-services
  $ openstack server group create nvidia-dls --policy anti-affinity
  $ openstack server create --flavor 8cpu-8gbmem-30gbdisk --image nls-3.0.0-bios --port nvidia-dls-1 --hint group=179dfa59-0947-4925-a0ff-b803bc0e58b2 nvidia-dls-cci1-1 --security-group nvidia-dls
  $ openstack server add security group nvidia-dls-1 nvidia-dls


Manual VM driver and licence configuration
^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^

vGPU client VMs need to be configured with Nvidia drivers to run GPU workloads.
The host drivers should already be applied to the hypervisor.

GCP hosts compatible client drivers `here
<https://cloud.google.com/compute/docs/gpus/grid-drivers-table>`__.

Find the correct version (when in doubt, use the same version as the host) and
download it to the VM. The exact dependencies will depend on the base image you
are using but at a minimum, you will need GCC installed.

Ubuntu Jammy example:

.. code-block:: bash

    sudo apt update
    sudo apt install -y make gcc wget
    wget https://storage.googleapis.com/nvidia-drivers-us-public/GRID/vGPU17.1/NVIDIA-Linux-x86_64-550.54.15-grid.run
    sudo sh NVIDIA-Linux-x86_64-550.54.15-grid.run

Check the ``nvidia-smi`` client is available:

.. code-block:: bash

    nvidia-smi

Generate a token from the licence server, and copy the token file to the client
VM.

On the client, create an Nvidia grid config file from the template:

.. code-block:: bash

    sudo cp /etc/nvidia/gridd.conf.template  /etc/nvidia/gridd.conf

Edit it to set ``FeatureType=1`` and leave the rest of the settings as default.

Copy the client configuration token into the ``/etc/nvidia/ClientConfigToken``
directory.

Ensure the correct permissions are set:

.. code-block:: bash

    sudo chmod 744 /etc/nvidia/ClientConfigToken/client_configuration_token_<datetime>.tok

Restart the ``nvidia-gridd`` service:

.. code-block:: bash

    sudo systemctl restart nvidia-gridd

Check that the token has been recognised:

.. code-block:: bash

    nvidia-smi -q | grep 'License Status'

If not, an error should appear in the journal:

.. code-block:: bash

    sudo journalctl -xeu nvidia-gridd

A successfully licenced VM can be snapshotted to create an image in Glance that
includes the drivers and licencing token. Alternatively, an image can be
created using Diskimage Builder.

Disk image builder recipe to automatically license VGPU on boot
^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^

`stackhpc-image-elements <https://github.com/stackhpc/stackhpc-image-elements>`__ provides a ``nvidia-vgpu``
element to configure the nvidia-gridd service in VGPU mode. This allows you to boot VMs that automatically license themselves.
Snippets of ``openstack-config`` that allow you to do this are shown below:

.. code-block:: shell

  image_rocky9_nvidia:
    name: "Rocky9-NVIDIA"
    type: raw
    elements:
      - "rocky-container"
      - "rpm"
      - "nvidia-vgpu"
      - "cloud-init"
      - "epel"
      - "cloud-init-growpart"
      - "selinux-permissive"
      - "dhcp-all-interfaces"
      - "vm"
      - "extra-repos"
      - "grub2"
      - "stable-interface-names"
      - "openssh-server"
    is_public: True
    packages:
      - "dkms"
      - "git"
      - "tmux"
      - "cuda-minimal-build-12-1"
      - "cuda-demo-suite-12-1"
      - "cuda-libraries-12-1"
      - "cuda-toolkit"
      - "vim-enhanced"
    env:
      DIB_CONTAINERFILE_NETWORK_DRIVER: host
      DIB_CONTAINERFILE_RUNTIME: docker
      DIB_RPMS: "http://192.168.1.2:80/pulp/content/nvidia/nvidia-linux-grid-525-525.105.17-1.x86_64.rpm"
      YUM: dnf
      DIB_EXTRA_REPOS: "https://developer.download.nvidia.com/compute/cuda/repos/rhel9/x86_64/cuda-rhel9.repo"
      DIB_NVIDIA_VGPU_CLIENT_TOKEN: "{{ lookup('file' , 'secrets/client_configuration_token_05-30-2023-12-41-40.tok') }}"
      DIB_CLOUD_INIT_GROWPART_DEVICES:
        - "/"
      DIB_RELEASE: "9"
    properties:
      os_type: "linux"
      os_distro: "rocky"
      os_version: "9"

  openstack_images:
    - "{{ image_rocky9_nvidia }}"

  openstack_image_git_elements:
    - repo: "https://github.com/stackhpc/stackhpc-image-elements"
      local: "{{ playbook_dir }}/stackhpc-image-elements"
      version: master
      elements_path: elements

The gridd driver was uploaded pulp using the following procedure:

.. code-block:: shell

  $ unzip NVIDIA-GRID-Linux-KVM-525.105.14-525.105.17-528.89.zip
  $ pulp artifact upload --file ~/nvidia-linux-grid-525-525.105.17-1.x86_64.rpm
  $ pulp file content create --relative-path "nvidia-linux-grid-525-525.105.17-1.x86_64.rpm" --sha256 58fda68d01f00ea76586c9fd5f161c9fbb907f627b7e4f4059a309d8112ec5f5
  $ pulp file repository add --name nvidia --sha256 58fda68d01f00ea76586c9fd5f161c9fbb907f627b7e4f4059a309d8112ec5f5 --relative-path "nvidia-linux-grid-525-525.105.17-1.x86_64.rpm"
  $ pulp file publication create --repository nvidia
  $ pulp file distribution update --name nvidia --base-path nvidia --repository nvidia

This is the file we reference in ``DIB_RPMS``. It is important to keep the driver versions aligned between hypervisor and guest VM.

The client token can be downloaded from the web interface of the licensing portal. Care should be taken
when copying the contents as it can contain invisible characters. It is best to copy the file directly
into your openstack-config repository and vault encrypt it. The ``file`` lookup plugin can be used to decrypt
the file (as shown in the example above).

Testing vGPU VMs
^^^^^^^^^^^^^^^^

vGPU VMs can be validated using the following test workload. The test should
succeed if the VM is correctly licenced and drivers are correctly installed for
both the host and client VM.

Install ``cuda-toolkit`` using the instructions `here
<https://docs.nvidia.com/cuda/cuda-installation-guide-linux/index.html>`__.

Ubuntu Jammy example:

.. code-block:: bash

    wget https://developer.download.nvidia.com/compute/cuda/repos/ubuntu2204/x86_64/cuda-keyring_1.1-1_all.deb
    sudo dpkg -i cuda-keyring_1.1-1_all.deb
    sudo apt update -y
    sudo apt install -y cuda-toolkit make

The VM may require a reboot at this point.

Clone the ``cuda-samples`` repo:

.. code-block:: bash

    git clone https://github.com/NVIDIA/cuda-samples.git

Build and run a test workload:

.. code-block:: bash

    cd cuda-samples/Samples/6_Performance/transpose
    make
    ./transpose

Example output:

.. code-block::

    Transpose Starting...

    GPU Device 0: "Ampere" with compute capability 8.0

    > Device 0: "GRID A100D-1-10C MIG 1g.10gb"
    > SM Capability 8.0 detected:
    > [GRID A100D-1-10C MIG 1g.10gb] has 14 MP(s) x 64 (Cores/MP) = 896 (Cores)
    > Compute performance scaling factor = 1.00

    Matrix size: 1024x1024 (64x64 tiles), tile size: 16x16, block size: 16x16

    transpose simple copy       , Throughput = 159.1779 GB/s, Time = 0.04908 ms, Size = 1048576 fp32 elements, NumDevsUsed = 1, Workgroup = 256
    transpose shared memory copy, Throughput = 152.1922 GB/s, Time = 0.05133 ms, Size = 1048576 fp32 elements, NumDevsUsed = 1, Workgroup = 256
    transpose naive             , Throughput = 117.2670 GB/s, Time = 0.06662 ms, Size = 1048576 fp32 elements, NumDevsUsed = 1, Workgroup = 256
    transpose coalesced         , Throughput = 135.0813 GB/s, Time = 0.05784 ms, Size = 1048576 fp32 elements, NumDevsUsed = 1, Workgroup = 256
    transpose optimized         , Throughput = 145.4326 GB/s, Time = 0.05372 ms, Size = 1048576 fp32 elements, NumDevsUsed = 1, Workgroup = 256
    transpose coarse-grained    , Throughput = 145.2941 GB/s, Time = 0.05377 ms, Size = 1048576 fp32 elements, NumDevsUsed = 1, Workgroup = 256
    transpose fine-grained      , Throughput = 150.5703 GB/s, Time = 0.05189 ms, Size = 1048576 fp32 elements, NumDevsUsed = 1, Workgroup = 256
    transpose diagonal          , Throughput = 117.6831 GB/s, Time = 0.06639 ms, Size = 1048576 fp32 elements, NumDevsUsed = 1, Workgroup = 256
    Test passed

Changing VGPU device types
^^^^^^^^^^^^^^^^^^^^^^^^^^

Converting the second card to an NVIDIA-698 (whole card). The hypervisor
is empty so we can freely delete mdevs. First clean up the mdev
definition:

.. code:: shell

   [stack@computegpu007 ~]$ sudo mdevctl list
   5c630867-a673-5d75-aa31-a499e6c7cb19 0000:21:00.4 nvidia-697 manual (defined)
   eaa6e018-308e-58e2-b351-aadbcf01f5a8 0000:21:00.5 nvidia-697 manual (defined)
   72291b01-689b-5b7a-9171-6b3480deabf4 0000:81:00.4 nvidia-697 manual (defined)
   0a47ffd1-392e-5373-8428-707a4e0ce31a 0000:81:00.5 nvidia-697 manual (defined)

   [stack@computegpu007 ~]$ sudo mdevctl stop --uuid 72291b01-689b-5b7a-9171-6b3480deabf4
   [stack@computegpu007 ~]$ sudo mdevctl stop --uuid 0a47ffd1-392e-5373-8428-707a4e0ce31a

   [stack@computegpu007 ~]$ sudo mdevctl undefine --uuid 0a47ffd1-392e-5373-8428-707a4e0ce31a

   [stack@computegpu007 ~]$ sudo mdevctl list --defined
   5c630867-a673-5d75-aa31-a499e6c7cb19 0000:21:00.4 nvidia-697 manual (active)
   eaa6e018-308e-58e2-b351-aadbcf01f5a8 0000:21:00.5 nvidia-697 manual (active)
   72291b01-689b-5b7a-9171-6b3480deabf4 0000:81:00.4 nvidia-697 manual

   # We can re-use the first virtual function

Secondly remove the systemd unit that starts the mdev device:

.. code:: shell

   [stack@computegpu007 ~]$ sudo rm /etc/systemd/system/multi-user.target.wants/nvidia-mdev@0a47ffd1-392e-5373-8428-707a4e0ce31a.service

Example config change:

.. code:: shell

   diff --git a/etc/kayobe/environments/cci1/inventory/host_vars/computegpu007/vgpu b/etc/kayobe/environments/cci1/inventory/host_vars/computegpu007/vgpu
   new file mode 100644
   index 0000000..6cea9bf
   --- /dev/null
   +++ b/etc/kayobe/environments/cci1/inventory/host_vars/computegpu007/vgpu
   @@ -0,0 +1,12 @@
   +---
   +vgpu_definitions:
   +    - pci_address: "0000:21:00.0"
   +      virtual_functions:
   +        - mdev_type: nvidia-697
   +          index: 0
   +        - mdev_type: nvidia-697
   +          index: 1
   +    - pci_address: "0000:81:00.0"
   +      virtual_functions:
   +        - mdev_type: nvidia-698
   +          index: 0
   diff --git a/etc/kayobe/kolla/config/nova/nova-compute.conf b/etc/kayobe/kolla/config/nova/nova-compute.conf
   index 6f680cb..e663ec4 100644
   --- a/etc/kayobe/kolla/config/nova/nova-compute.conf
   +++ b/etc/kayobe/kolla/config/nova/nova-compute.conf
   @@ -39,7 +39,19 @@ cpu_mode = host-model
    {% endraw %}

    {% raw %}
   -{% if inventory_hostname in groups['compute_multi_instance_gpu'] %}
   +{% if inventory_hostname == "computegpu007" %}
   +[devices]
   +enabled_mdev_types = nvidia-697, nvidia-698
   +
   +[mdev_nvidia-697]
   +device_addresses = 0000:21:00.4,0000:21:00.5
   +mdev_class = VGPU
   +
   +[mdev_nvidia-698]
   +device_addresses = 0000:81:00.4
   +mdev_class = CUSTOM_NVIDIA_698
   +
   +{% elif inventory_hostname in groups['compute_multi_instance_gpu'] %}
    [devices]
    enabled_mdev_types = nvidia-700, nvidia-699

   @@ -50,15 +62,14 @@ mdev_class = CUSTOM_NVIDIA_700
    [mdev_nvidia-699]
    device_addresses = 0000:21:00.7,0000:81:00.7
    mdev_class = CUSTOM_NVIDIA_699
   -{% endif %}

   -{% if inventory_hostname in groups['compute_vgpu'] %}
   +{% elif inventory_hostname in groups['compute_vgpu'] %}
    [devices]
    enabled_mdev_types = nvidia-697

    [mdev_nvidia-697]
    device_addresses = 0000:21:00.4,0000:21:00.5,0000:81:00.4,0000:81:00.5
   -# Custom resource classes don't seem to work for this card.
   +# Custom resource classes don't work when you only have single resource type.
    mdev_class = VGPU

    {% endif %}

Re-run the configure playbook:

.. code:: shell

   (kayobe) [stack@ansiblenode1 kayobe]$ kayobe playbook run $KAYOBE_CONFIG_PATH/ansible/host-configure.yml --tags vgpu --limit computegpu007

Check the result:

.. code:: shell

   [stack@computegpu007 ~]$ mdevctl list
   5c630867-a673-5d75-aa31-a499e6c7cb19 0000:21:00.4 nvidia-697 manual
   eaa6e018-308e-58e2-b351-aadbcf01f5a8 0000:21:00.5 nvidia-697 manual
   72291b01-689b-5b7a-9171-6b3480deabf4 0000:81:00.4 nvidia-698 manual

Reconfigure nova to match the change:

.. code:: shell

   kayobe overcloud service reconfigure -kt nova --kolla-limit computegpu007 --skip-prechecks


PCI Passthrough
###############

This guide has been developed for Nvidia GPUs and CentOS 8.

See `Kayobe Ops <https://github.com/stackhpc/kayobe-ops>`_ for
a playbook implementation of host setup for GPU.

BIOS Configuration Requirements
-------------------------------

On an Intel system:

* Enable `VT-x` in the BIOS for virtualisation support.
* Enable `VT-d` in the BIOS for IOMMU support.

Hypervisor Configuration Requirements
-------------------------------------

Find the GPU device IDs
^^^^^^^^^^^^^^^^^^^^^^^

From the host OS, use ``lspci -nn`` to find the PCI vendor ID and
device ID for the GPU device and supporting components.  These are
4-digit hex numbers.

For example:

.. code-block:: text

   01:00.0 VGA compatible controller [0300]: NVIDIA Corporation GM204M [GeForce GTX 980M] [10de:13d7] (rev a1) (prog-if 00 [VGA controller])
   01:00.1 Audio device [0403]: NVIDIA Corporation GM204 High Definition Audio Controller [10de:0fbb] (rev a1)

In this case the vendor ID is ``10de``, display ID is ``13d7`` and audio ID is ``0fbb``.

Alternatively, for an Nvidia Quadro RTX 6000:

.. code-block:: yaml

   # NVIDIA Quadro RTX 6000/8000 PCI device IDs
   vendor_id: "10de"
   display_id: "1e30"
   audio_id: "10f7"
   usba_id: "1ad6"
   usba_class: "0c0330"
   usbc_id: "1ad7"
   usbc_class: "0c8000"

These parameters will be used for device-specific configuration.

Kernel Ramdisk Reconfiguration
^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^

The ramdisk loaded during kernel boot can be extended to include the
vfio PCI drivers and ensure they are loaded early in system boot.

.. code-block:: yaml

   - name: Template dracut config
     blockinfile:
       path: /etc/dracut.conf.d/gpu-vfio.conf
       block: |
         add_drivers+="vfio vfio_iommu_type1 vfio_pci vfio_virqfd"
       owner: root
       group: root
       mode: 0660
       create: true
     become: true
     notify:
       - Regenerate initramfs
       - reboot

The handler for regenerating the Dracut initramfs is:

.. code-block:: yaml

   - name: Regenerate initramfs
     shell: |-
       #!/bin/bash
       set -eux
       dracut -v -f /boot/initramfs-$(uname -r).img $(uname -r)
     become: true

Kernel Boot Parameters
^^^^^^^^^^^^^^^^^^^^^^

Set the following kernel parameters by adding to
``GRUB_CMDLINE_LINUX_DEFAULT`` or ``GRUB_CMDLINE_LINUX`` in
``/etc/default/grub.conf``.  We can use the
`stackhpc.grubcmdline <https://galaxy.ansible.com/stackhpc/grubcmdline>`_
role from Ansible Galaxy:

.. code-block:: yaml

   - name: Add vfio-pci.ids kernel args
     include_role:
       name: stackhpc.grubcmdline
     vars:
       kernel_cmdline:
         - intel_iommu=on
         - iommu=pt
         - "vfio-pci.ids={{ vendor_id }}:{{ display_id }},{{ vendor_id }}:{{ audio_id }}"
       kernel_cmdline_remove:
         - iommu
         - intel_iommu
         - vfio-pci.ids

Kernel Device Management
^^^^^^^^^^^^^^^^^^^^^^^^

In the hypervisor, we must prevent kernel device initialisation of
the GPU and prevent drivers from loading for binding the GPU in the
host OS.  We do this using ``udev`` rules:

.. code-block:: yaml

   - name: Template udev rules to blacklist GPU usb controllers
     blockinfile:
       # We want this to execute as soon as possible
       path: /etc/udev/rules.d/99-gpu.rules
       block: |
         #Remove NVIDIA USB xHCI Host Controller Devices, if present
         ACTION=="add", SUBSYSTEM=="pci", ATTR{vendor}=="0x{{ vendor_id }}", ATTR{class}=="0x{{ usba_class }}", ATTR{remove}="1"
         #Remove NVIDIA USB Type-C UCSI devices, if present
         ACTION=="add", SUBSYSTEM=="pci", ATTR{vendor}=="0x{{ vendor_id }}", ATTR{class}=="0x{{ usbc_class }}", ATTR{remove}="1"
       owner: root
       group: root
       mode: 0644
       create: true
      become: true

Kernel Drivers
^^^^^^^^^^^^^^

Prevent the ``nouveau`` kernel driver from loading by
blacklisting the module:

.. code-block:: yaml

   - name: Blacklist nouveau
     blockinfile:
       path: /etc/modprobe.d/blacklist-nouveau.conf
       block: |
         blacklist nouveau
         options nouveau modeset=0
       mode: 0664
       owner: root
       group: root
       create: true
     become: true
     notify:
       - reboot
       - Regenerate initramfs

Ensure that the ``vfio`` drivers are loaded into the kernel on boot:

.. code-block:: yaml

   - name: Add vfio to modules-load.d
     blockinfile:
       path: /etc/modules-load.d/vfio.conf
       block: |
         vfio
         vfio_iommu_type1
         vfio_pci
         vfio_virqfd
       owner: root
       group: root
       mode: 0664
       create: true
     become: true
     notify: reboot

Once this code has taken effect (after a reboot), the VFIO kernel drivers should be loaded on boot:

.. code-block:: text

   # lsmod | grep vfio
   vfio_pci               49152  0
   vfio_virqfd            16384  1 vfio_pci
   vfio_iommu_type1       28672  0
   vfio                   32768  2 vfio_iommu_type1,vfio_pci
   irqbypass              16384  5 vfio_pci,kvm

   # lspci -nnk -s 3d:00.0
   3d:00.0 VGA compatible controller [0300]: NVIDIA Corporation GM107GL [Tesla M10] [10de:13bd] (rev a2)
   Subsystem: NVIDIA Corporation Tesla M10 [10de:1160]
   Kernel driver in use: vfio-pci
   Kernel modules: nouveau

IOMMU should be enabled at kernel level as well - we can verify that on the compute host:

.. code-block:: text

   # docker exec -it nova_libvirt virt-host-validate | grep IOMMU
   QEMU: Checking for device assignment IOMMU support                         : PASS
   QEMU: Checking if IOMMU is enabled by kernel                               : PASS

OpenStack Nova configuration
----------------------------

Configure nova-scheduler
^^^^^^^^^^^^^^^^^^^^^^^^

The nova-scheduler service must be configured to enable the ``PciPassthroughFilter``
To enable it add it to the list of filters to Kolla-Ansible configuration file:
``etc/kayobe/kolla/config/nova.conf``, for instance:

.. code-block:: yaml

   [filter_scheduler]
   available_filters = nova.scheduler.filters.all_filters
   enabled_filters = AvailabilityZoneFilter, ComputeFilter, ComputeCapabilitiesFilter, ImagePropertiesFilter, ServerGroupAntiAffinityFilter, ServerGroupAffinityFilter, PciPassthroughFilter

Configure nova-compute
^^^^^^^^^^^^^^^^^^^^^^

Configuration can be applied in flexible ways using Kolla-Ansible's
methods for `inventory-driven customisation of configuration
<https://docs.openstack.org/kayobe/latest/configuration/reference/kolla-ansible.html#service-configuration>`_.
The following configuration could be added to
``etc/kayobe/kolla/config/nova/nova-compute.conf`` to enable PCI
passthrough of GPU devices for hosts in a group named ``compute_gpu``.
Again, the 4-digit PCI Vendor ID and Device ID extracted from ``lspci
-nn`` can be used here to specify the GPU device(s).

.. code-block:: jinja

   [pci]
   {% raw %}
   {% if inventory_hostname in groups['compute_gpu'] %}
   # We could support multiple models of GPU.
   # This can be done more selectively using different inventory groups.
   # GPU models defined here:
   # NVidia Tesla V100 16GB
   # NVidia Tesla V100 32GB
   # NVidia Tesla P100 16GB
   passthrough_whitelist = [{ "vendor_id":"10de", "product_id":"1db4" },
                            { "vendor_id":"10de", "product_id":"1db5" },
                            { "vendor_id":"10de", "product_id":"15f8" }]
   alias = { "vendor_id":"10de", "product_id":"1db4", "device_type":"type-PCI", "name":"gpu-v100-16" }
   alias = { "vendor_id":"10de", "product_id":"1db5", "device_type":"type-PCI", "name":"gpu-v100-32" }
   alias = { "vendor_id":"10de", "product_id":"15f8", "device_type":"type-PCI", "name":"gpu-p100" }
   {% endif %}
   {% endraw %}

Configure nova-api
^^^^^^^^^^^^^^^^^^

pci.alias also needs to be configured on the controller.
This configuration should match the configuration found on the compute nodes.
Add it to Kolla-Ansible configuration file:
``etc/kayobe/kolla/config/nova/nova-api.conf``, for instance:

.. code-block:: yaml

   [pci]
   alias = { "vendor_id":"10de", "product_id":"1db4", "device_type":"type-PCI", "name":"gpu-v100-16" }
   alias = { "vendor_id":"10de", "product_id":"1db5", "device_type":"type-PCI", "name":"gpu-v100-32" }
   alias = { "vendor_id":"10de", "product_id":"15f8", "device_type":"type-PCI", "name":"gpu-p100" }

Reconfigure nova service
^^^^^^^^^^^^^^^^^^^^^^^^

.. code-block:: text

   kayobe overcloud service reconfigure --kolla-tags nova --kolla-skip-tags common --skip-prechecks

Configure a flavor
^^^^^^^^^^^^^^^^^^

For example, to request two of the GPUs with alias gpu-p100

.. code-block:: text

   openstack flavor set m1.medium --property "pci_passthrough:alias"="gpu-p100:2"


This can be also defined in the openstack-config repository

add extra_specs to flavor in etc/openstack-config/openstack-config.yml:

.. code-block:: console

   admin# cd src/openstack-config
   admin# vim etc/openstack-config/openstack-config.yml

    name: "m1.medium"
    ram: 4096
    disk: 40
    vcpus: 2
    extra_specs:
      "pci_passthrough:alias": "gpu-p100:2"

Invoke configuration playbooks afterwards:

.. code-block:: console

   admin# source src/kayobe-config/etc/kolla/public-openrc.sh
   admin# source venvs/openstack/bin/activate
   admin# tools/openstack-config --vault-password-file <Vault password file path>

Create instance with GPU passthrough
^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^

.. code-block:: text

   openstack server create --flavor m1.medium --image ubuntu2004 --wait test-pci

Testing GPU in a Guest VM
-------------------------

The Nvidia drivers must be installed first.  For example, on an Ubuntu guest:

.. code-block:: text

   sudo apt install nvidia-headless-440 nvidia-utils-440 nvidia-compute-utils-440

The ``nvidia-smi`` command will generate detailed output if the driver has loaded
successfully.

Further Reference
-----------------

For PCI Passthrough and GPUs in OpenStack:

* Consumer-grade GPUs: https://gist.github.com/claudiok/890ab6dfe76fa45b30081e58038a9215
* https://www.jimmdenton.com/gpu-offloading-openstack/
* https://docs.openstack.org/nova/latest/admin/pci-passthrough.html
* https://docs.openstack.org/nova/latest/admin/virtual-gpu.html (vGPU only)
* Tesla models in OpenStack: https://egallen.com/openstack-nvidia-tesla-gpu-passthrough/
* https://wiki.archlinux.org/index.php/PCI_passthrough_via_OVMF
* https://www.kernel.org/doc/Documentation/Intel-IOMMU.txt
* https://access.redhat.com/documentation/en-us/red_hat_virtualization/4.1/html/installation_guide/appe-configuring_a_hypervisor_host_for_pci_passthrough
* https://www.gresearch.co.uk/article/utilising-the-openstack-placement-service-to-schedule-gpu-and-nvme-workloads-alongside-general-purpose-instances/
