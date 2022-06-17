# data-transfer

A GPUDirect RDMA data transer demo between two nodes (Back-to-Back) using Mellanox ConnectX-6 Dx and Nvidia Quadro M4000 GPU's



## Installation

Clone the project:

```
git clone https://github.com/saab_demo/data-transfer.git
```

Move to the project folder:

```
cd data-transfer
```

## Requirements
---------------

### Hardware

* `ConnectX*` NIC
* `RDMA enabled GPU` Quadro, Kepler or Ampere class GPU's

### Software

MLNX_OFED 5.1

1) `nvidia-peer-mem` GPUDirect RDMA

To install `CUDA 11.7` on Ubuntu 20.04:

    wget https://developer.download.nvidia.com/compute/cuda/repos/ubuntu2004/x86_64/cuda-ubuntu2004.pin
    sudo mv cuda-ubuntu2004.pin /etc/apt/preferences.d/cuda-repository-pin-600
    wget https://developer.download.nvidia.com/compute/cuda/11.7.0/local_installers/cuda-repo-ubuntu2004-11-7-local_11.7.0-515.43.04-1_amd64.deb
    sudo dpkg -i cuda-repo-ubuntu2004-11-7-local_11.7.0-515.43.04-1_amd64.deb
    sudo cp /var/cuda-repo-ubuntu2004-11-7-local/cuda-*-keyring.gpg /usr/share/keyrings/
    sudo apt-get update
    sudo apt-get -y install cuda

To install `nvidia-peer-mem` on Ubuntu 20.04:

    git clone https://github.com/Mellanox/nv_peer_memory.git
    cd nv_peer_memory
    ./build_module.sh

    cd /tmp
    tar xzf /tmp/nvidia-peer-memory_*
    cd nvidia-peer-memory-*
    dpkg-buildpackage -us -uc
    sudo dpkg -i /tmp/nvidia-peer-memory_*.deb

    sudo service nv_peer_mem start


To install `perftest`:

    sudo apt install libpci-dev libibumad

    git clone https://github.com/linux-rdma/perftest.git
    cd perftest
    ./autogen.sh && ./configure CUDA_H_PATH=/usr/local/cuda/include/cuda.h && make -j
    sudo make install

