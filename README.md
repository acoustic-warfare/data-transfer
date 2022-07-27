# data-transfer

A COTS GPUDirect RDMA data transer demo between two nodes (Back-to-Back) using Mellanox ConnectX-6 Dx and Nvidia Quadro M4000 GPU's over UCX.

![Transfer Demo](https://github.com/acoustic-warfare/data-transfer/blob/main/synthetic_transfer_demo.gif)

## Installation

Clone the project:

```
git clone https://github.com/acoustic-warfare/data-transfer.git
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
* Quadro™ P-Series (Ours)


### Software

* **NIC**
In order to use the network interface cards, the package NVIDIA Firmware Tools: `mft` must be installed for firmware management together with correct drivers for Linux `MLNX_OFED`.

* **GPU**
In order to utilize GPUDirect RDMA, the package `nvidia-peer-mem` must be installed.
MLNX_OFED 5.1

* **Data Transfer**
To be able to control the host channel adapter (HCA), the HPC networking library `ucx` is required with support for GPUDirect RDMA.




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

**3.1 GDRCopy (OPTIONAL)**

To install `gdrcopy`

    git clone https://github.com/NVIDIA/gdrcopy.git
    cd gdrcopy
    sudo apt install check libsubunit0 libsubunit-dev
    mkdir final
    make prefix=final CUDA="$CUDA_HOME" all install

**3.2 Performance Benchmark (OPTIONAL)**

    sudo apt update -y
    sudo apt install -y libpci-dev libibumad

    git clone https://github.com/linux-rdma/perftest.git
    cd perftest
    ./autogen.sh && ./configure CUDA_H_PATH=/usr/local/cuda/include/cuda.h && make -j
    sudo make install

**4. UCX**

To install `ucx` on Ubuntu 20.04, python bindings are required together with python3+ packages. To maintain a working environment, installing conda is highly recomended. 

**4.1 Conda**

    wget https://repo.anaconda.com/miniconda/Miniconda3-latest-Linux-x86.sh

    bash Miniconda3-latest-Linux-x86.sh

Disable auto-init

    conda config --set auto_activate_base false

Recreate an environment inside data-transfer

    conda env create -f environment.yml

Activate and enter the newly created environment

    conda activate data-transfer
    ...
    (data-transfer) $ 

**4.2 Development packages for the program**

Ensure that the latest updates are installed.

    sudo apt update -y

Install development packages in Ubuntu 20.04. `libnuma-dev`, `cython3`.

    sudo apt install -y libnuma-dev cython3

**4.3 Install dependencies**

Some python modules require more dependencies to run.

    pip install pynvml cpython

To build the project requires having the `gcc` compiler.

    sudo apt install gcc cmake


## Setup

The adapters need assigned IP addresses, we used the GNOME Network Manager GUI and assigned the IPv4 addresses `10.0.0.x` format with netmask `255.255.255.0`

To run the demo, make sure both network adapters are connected and working properly by performing a ping. It is important to specify the correct interface when pinging:

    ping -I <LOCAL_INTERFACE> <REMOTE_ADDRESS>

Eg:

    (data-transfer) scarecrow@node1:~/data-transfer$ ping -I ens4f0np0 10.0.0.4
    PING 10.0.0.4 (10.0.0.4) from 10.0.0.3 ens4f0np0: 56(84) bytes of data.
    64 bytes from 10.0.0.4: icmp_seq=1 ttl=64 time=0.110 ms
    64 bytes from 10.0.0.4: icmp_seq=2 ttl=64 time=0.112 ms
    64 bytes from 10.0.0.4: icmp_seq=3 ttl=64 time=0.109 ms
    ^C
    --- 10.0.0.4 ping statistics ---
    3 packets transmitted, 3 received, 0% packet loss, time 2029ms
    rtt min/avg/max/mdev = 0.109/0.110/0.112/0.001 ms

To find out which interface to use:
```bash
(data-transfer) scarecrow@node1:~/data-transfer$ ifconfig

    eno1: flags=4099<UP,BROADCAST,MULTICAST>  mtu 1500
        ether 54:bf:64:6a:91:31  txqueuelen 1000  (Ethernet)
        RX packets 0  bytes 0 (0.0 B)
        RX errors 0  dropped 0  overruns 0  frame 0
        TX packets 0  bytes 0 (0.0 B)
        TX errors 0  dropped 0 overruns 0  carrier 0  collisions 0
        device interrupt 16  memory 0x92f00000-92f20000  

    # The one we used: Mellanox ConnectX-6 Dx (first port)
    -----------------
 -> ens4f0np0: flags=4163<UP,BROADCAST,RUNNING,MULTICAST>  mtu 1500
            inet 10.0.0.3  netmask 255.255.255.0  broadcast 10.0.0.255
            inet6 fe80::4e4d:abee:c38d:4b6f  prefixlen 64  scopeid 0x20<link>
            ether 10:70:fd:60:c1:cc  txqueuelen 1000  (Ethernet)
            RX packets 1021  bytes 63776 (63.7 KB)
            RX errors 0  dropped 0  overruns 0  frame 0
            TX packets 841  bytes 52495 (52.4 KB)
            TX errors 0  dropped 0 overruns 0  carrier 0  collisions 0
    -----------------

    ens4f1np1: flags=4163<UP,BROADCAST,RUNNING,MULTICAST>  mtu 1500
            inet 10.0.0.1  netmask 255.255.255.0  broadcast 10.0.0.255
            inet6 fe80::40ba:65b6:cb4e:4521  prefixlen 64  scopeid 0x20<link>
            ether 10:70:fd:60:c1:cd  txqueuelen 1000  (Ethernet)
            RX packets 36  bytes 4419 (4.4 KB)
            RX errors 0  dropped 0  overruns 0  frame 0
            TX packets 23  bytes 3072 (3.0 KB)
            TX errors 0  dropped 0 overruns 0  carrier 0  collisions 0

    lo: flags=73<UP,LOOPBACK,RUNNING>  mtu 65536
            inet 127.0.0.1  netmask 255.0.0.0
            inet6 ::1  prefixlen 128  scopeid 0x10<host>
            loop  txqueuelen 1000  (Local Loopback)
            RX packets 1782  bytes 168796 (168.7 KB)
            RX errors 0  dropped 0  overruns 0  frame 0
            TX packets 1782  bytes 168796 (168.7 KB)
            TX errors 0  dropped 0 overruns 0  carrier 0  collisions 0

    wlx04421a4d9e71: flags=4163<UP,BROADCAST,RUNNING,MULTICAST>  mtu 1500
            inet 81.236.101.159  netmask 255.255.254.0  broadcast 81.236.101.255
            inet6 fe80::7207:baa6:6cea:6bd3  prefixlen 64  scopeid 0x20<link>
            ether 04:42:1a:4d:9e:71  txqueuelen 1000  (Ethernet)
            RX packets 66840  bytes 48821412 (48.8 MB)
            RX errors 0  dropped 7  overruns 0  frame 0
            TX packets 61150  bytes 44974817 (44.9 MB)
            TX errors 0  dropped 0 overruns 0  carrier 0  collisions 0
```

If the connection is working building can be started


## Building

Building the demo will create three executable files: `run`, `web_gauge` and `fpga_emulator`. `run` is the main data-transfer program. `fpga_emulator` is a program to emulate incoming datastream (data generator) to send from one GPU to the other. `web_gauge` is a web GUI showing a speedometer of the current transfer rate.

    make

To only build `fpga_emulator`:

    make fpga

To only build `web_gauge`:

    make web_gauge

To cleanup and removal of executables:

    make clean

 
## Usage

Running the demo requires that both computers are connected via infiniband and correct software and modules are installed and running. 



### Receiver
Start the receiving end (Will receive a continuous flow of data)

    ./run --server -a <ADDRESS> -p <PORT>

### Transmitter (Requires a running receiver)
Start the receiving end (Will receive a continuous flow of data)

    ./run --client -a <SERVER_ADDRESS> -p <PORT>

### Data Generation (Requires a running transmitter)
Start the FPGA device sending data to a UDP socket or run the the emulator:

    ./fpga_emulator -a "localhost" -p <PORT>

### Live Online Demo (Requires a running data-transfer)
Start the data-transfer demo:

    ./web_gauge --web-host <IP> -w <PORT> -a "localhost" -p 30000

View the running application running on specified `IP` and `PORT`:

    firefox http://IP:PORT/





## Problems

### Network Cards Shutting Down

If the network adapters stops working after a period of time can be a result of insufficient cooling. The ConnectX cards require continuous cooling, we found that after exceeding 110°C, the modules were being unloaded from the system `mlx5_core` followed by many warnings when shown with `dmesg`. After exceeding the 120°C mark, the cards were physically shutdown by an onboard safety mechanism resulting in reloading the kernel modules was impossible and required a complete restart of the system.

From Nvidia https://docs.nvidia.com/networking/display/ConnectX5EN/Thermal+Sensors

    The adapter card incorporates the ConnectX IC which operates in the range of temperatures between 0C and 105C.

    There are three thermal threshold definitions which impact the overall system operation state:

        Warning – 105°C: On managed systems only: When the device crosses the 100°C threshold, a Warning Threshold message will be issued by the management SW, indicating to system administration that the card has crossed the Warning threshold. Note that this temperature threshold does not require nor lead to any action by hardware (such as adapter card shutdown).

        Critical – 115°C: When the device crosses this temperature, the firmware will automatically shut down the device.
        
        Emergency – 130°C: In case the firmware fails to shut down the device upon crossing the Critical threshold, the device will auto-shutdown upon crossing the Emergency (130°C) threshold.

    The card's thermal sensors can be read through the system’s SMBus. The user can read these thermal sensors and adapt the system airflow in accordance with the readouts and the needs of the above-mentioned IC thermal requirements.

To check temperature of the cards install the

To find the cards:

    (data-transfer) scarecrow@node1:~/data-transfer$ lspci | grep Mellanox
    04:00.0 Ethernet controller: Mellanox Technologies MT2892 Family [ConnectX-6 Dx]
    04:00.1 Ethernet controller: Mellanox Technologies MT2892 Family [ConnectX-6 Dx]

To probe `04:00.0` (requires root privileges):

    sudo mget_temp -d 04:00.0
    53

### libpython3.7m.so.1.0 not found

If during runtime, the linker cannot find `libpython3.7m.so.1.0` like this:

    error while loading shared libraries: libpython3.7m.so.1.0: cannot open shared object file: No such file or directory

A temporal solution is to export the path to the module using

    export LD_LIBRARY_PATH=~/miniconda3/envs/data-transfer/lib/

