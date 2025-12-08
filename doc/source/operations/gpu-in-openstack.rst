=============================
Support for GPUs in OpenStack
=============================

PCI Passthrough
###############

Prerequisite - BIOS Configuration
---------------------------------

On an Intel system:

* Enable ``VT-x`` in the BIOS for virtualisation support.
* Enable ``VT-d`` in the BIOS for IOMMU support.

On an AMD system:

* Enable ``AMD-v`` in the BIOS for virtualisation support.
* Enable ``AMD-Vi`` (also just called ``IOMMU`` on older hardware) in the BIOS
  for IOMMU support.

It may be possible to configure passthrough without these settings, though
stability or performance may be affected.

Host and Service Configuration
------------------------------

PCI passthrough GPU variables can be found in the
``etc/kayobe/stackhpc-compute.yml`` file.

The ``gpu_group_map`` is a dictionary mapping inventory groups to GPU types.
This is used to determine which GPU types each compute node should pass through
to OpenStack. The keys are group names, the values are a list of GPU types.

Possible GPU types are defined in the ``stackhpc_gpu_data`` dictionary. It
contains data for many common GPUs. If you have a GPU that is not included,
extend the dictionary following the same pattern.

The ``resource_name`` is the name that will be used in the flavor extra specs.
These can be overridden e.g. ``a100_80_resource_name: "big_gpu"``.

Example configuration for three groups containing A100s, V100s, and both:

.. code-block:: yaml
   :caption: $KAYOBE_CONFIG_PATH/stackhpc-compute.yml

    gpu_group_map:
      compute_a100:
        - a100_80
      compute_v100:
        - v100_32
      compute_multi_gpu:
        - a100_80
        - v100_32

All groups in the ``gpu_group_map`` must also be added to
``kolla_overcloud_inventory_top_level_group_map`` in ``etc/kayobe/kolla.yml``.
Always include the Kayobe defaults unless you know what you are doing.

When ``gpu_group_map`` is populated, the ``pci-passthrough.yml`` playbook will
be added as a pre-hook to ``kayobe overcloud host configure``. Either run host
configuration or trigger the playbook manually:

.. code-block:: console

    kayobe overcloud host configure --limit compute_a100,compute_v100,compute_multi_gpu
    # OR
    kayobe playbook run $KAYOBE_CONFIG_PATH/ansible/pci-passthrough.yml --limit compute_a100,compute_v100,compute_multi_gpu

The playbook will apply the necessary configuraion and reboot the hosts if
required.

Once host configuration is complete, deploy Nova:

.. code-block:: console

    kayobe overcloud service deploy -kt nova

Create a flavor
---------------

For example, to request two of the GPUs with alias **v100_32**

.. code-block:: text

   openstack flavor set m1.medium-gpu --property "pci_passthrough:alias"="v100_32:2"

This can be also defined in the openstack-config repository.

Add extra_specs to flavor in etc/openstack-config/openstack-config.yml:

.. code-block:: console

   cd src/openstack-config
   vim etc/openstack-config/openstack-config.yml

    name: "m1.medium-gpu"
    ram: 4096
    disk: 40
    vcpus: 2
    extra_specs:
      "pci_passthrough:alias": "v100_32:2"

Invoke configuration playbooks afterwards:

.. code-block:: console

   source src/kayobe-config/etc/kolla/public-openrc.sh
   source venvs/openstack/bin/activate
   tools/openstack-config --vault-password-file <Vault password file path>

Create instance with GPU passthrough
------------------------------------

.. code-block:: text

    openstack server create --flavor m1.medium-gpu --image ubuntu22.04 --wait test-pci

Testing GPU in a Guest VM
-------------------------

The Nvidia drivers must be installed first.  For example, on an Ubuntu guest:

.. code-block:: text

    sudo apt install nvidia-headless-440 nvidia-utils-440 nvidia-compute-utils-440

The ``nvidia-smi`` command will generate detailed output if the driver has
loaded successfully.


Virtual GPUs
############

BIOS configuration
------------------

See upstream documentation: `BIOS configuration <https://docs.openstack.org/kayobe/latest/configuration/reference/vgpu.html#bios-configuration>`__

Obtain driver from NVIDIA licensing portal
------------------------------------------

See upstream documentation: `Obtain driver from NVIDIA licencing portal <https://docs.openstack.org/kayobe/latest/configuration/reference/vgpu.html#obtain-driver-from-nvidia-licensing-portal>`__

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

.. code-block:: yaml
   :caption: $KAYOBE_CONFIG_PATH/vgpu.yml

   # URL of GRID driver in pulp
   vgpu_driver_url: "{{ pulp_url }}/pulp/content/nvidia/NVIDIA-GRID-Linux-KVM-525.105.14-525.105.17-528.89.zip"

See :ref:`NVIDIA Role Configuration`.

.. _NVIDIA control host:

Placing the GRID driver on the ansible control host
---------------------------------------------------

Copy the driver bundle to a known location on the ansible control host. Set the ``vgpu_driver_url`` configuration variable to reference this
path using ``file`` as the url scheme e.g:

.. code-block:: yaml
   :caption: $KAYOBE_CONFIG_PATH/vgpu.yml

    # Location of NVIDIA GRID driver on localhost
    vgpu_driver_url: "file://{{ lookup('env', 'HOME') }}/NVIDIA-GRID-Linux-KVM-525.105.14-525.105.17-528.89.zip"

See :ref:`NVIDIA Role Configuration`.

.. _NVIDIA OS Configuration:

OS Configuration
----------------

Host OS configuration is done by using roles in the `stackhpc.linux <https://github.com/stackhpc/ansible-collection-linux>`_ ansible collection.

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
------------------

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

.. _NVIDIA Kolla Ansible Configuration:

Kolla-Ansible configuration
---------------------------

See upstream documentation: `Kolla Ansible configuration <https://docs.openstack.org/kayobe/latest/configuration/reference/vgpu.html#kolla-ansible-configuration>`__
then follow the rest.

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
-----------------

See upstream documentation: `OpenStack flavors <https://docs.openstack.org/kayobe/latest/configuration/reference/vgpu.html#openstack-flavors>`__

NVIDIA License Server
---------------------

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
------------------------------------------

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
---------------------------------------------------------------

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
----------------

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
--------------------------

See upstream documentation: `Changing VGPU device types <https://docs.openstack.org/kayobe/latest/configuration/reference/vgpu.html#changing-vgpu-device-types>`__

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
