# data-transfer

A GPUDirect RDMA data transer demo between two nodes (Back-to-Back) using Mellanox ConnectX-6 Dx and Nvidia Quadro M4000 GPU's



## Installation

Clone the project:

```
git clone https://github.com/Irreq/data-transfer.git
```

Move to the project folder:

```
cd data-transfer
```

## Requirements
---------------

### Hardware

**1. NICs**

* ConnectX-6 Lx
* ConnectX-6 Dx (Ours)
* ConnectX-6
* ConnectX-5
* ConnectX-4 Lx

**2. GPUs**

Nvidia:
* Tesla™ (any)
* Quadro™ K-Series
* Quadro™ P-Series


### Software

* **NIC** In order to use the network interface cards, the package NVIDIA Firmware Tools: `mft` must be installed for firmware management together with correct drivers for Linux `MLNX_OFED`.

* **GPU**
In order to utilize GPUDirect RDMA, the package `nvidia-peer-mem` must be installed.
MLNX_OFED 5.1

1) `nvidia-peer-mem` GPUDirect RDMA

## Installation

**NVIDIA Drivers**

It is preffered to install display drivers using the distribution's native package management tool, i.e `apt`. If not installed already, NVIDIA display drivers can be installed from [NVIDIA Download Center](https://www.nvidia.com/Download/index.aspx?lang=en-us).

**1. CUDA** Runtime and Toolkit

To install CUDA Toolkit `CUDA 11.7` from Nvidia on Ubuntu 20.04:

    wget https://developer.download.nvidia.com/compute/cuda/repos/ubuntu2004/x86_64/cuda-ubuntu2004.pin
    sudo mv cuda-ubuntu2004.pin /etc/apt/preferences.d/cuda-repository-pin-600
    wget https://developer.download.nvidia.com/compute/cuda/11.7.0/local_installers/cuda-repo-ubuntu2004-11-7-local_11.7.0-515.43.04-1_amd64.deb

    sudo dpkg -i cuda-repo-ubuntu2004-11-7-local_11.7.0-515.43.04-1_amd64.deb
    sudo cp /var/cuda-repo-ubuntu2004-11-7-local/cuda-*-keyring.gpg /usr/share/keyrings/

    sudo apt-get update
    sudo apt-get -y install cuda

**2. MLNX_OFED** NIC Firmware (v2.1-x.x.x or later)

To install Linux drivers for ethernet and infiniband adapters, `MLNX_OFED`. See [Download Center](https://network.nvidia.com/products/infiniband-drivers/linux/mlnx_ofed/) or for Ubuntu 20.04:

```
wget http://www.mellanox.com/downloads/ofed/MLNX_OFED-5.6-2.0.9.0/MLNX_OFED_LINUX-5.6-2.0.9.0-ubuntu20.04-x86_64.tgz
tar -xvf MLNX_OFED_LINUX*

cd MLNX_OFED_LINUX*
sudo ./mlnxofedinstall --upstream-libs --dpdk --force

sudo /etc/init.d/openibd restart
```

**3. GPUDirect RDMA**

To install `nvidia-peer-mem` on Ubuntu 20.04:

    git clone https://github.com/Mellanox/nv_peer_memory.git
    cd nv_peer_memory
    ./build_module.sh

    cd /tmp
    tar xzf /tmp/nvidia-peer-memory_*
    cd nvidia-peer-memory-*
    dpkg-buildpackage -us -uc
    sudo dpkg -i /tmp/nvidia-peer-memory_*.deb

    sudo service nv_peer_mem restart


To install `perftest`:

    sudo apt install libpci-dev libibumad

    git clone https://github.com/linux-rdma/perftest.git
    cd perftest
    ./autogen.sh && ./configure CUDA_H_PATH=/usr/local/cuda/include/cuda.h && make -j
    sudo make install


