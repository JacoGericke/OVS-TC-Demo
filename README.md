##### 1. Machines need to be setup back-to-back.

##### 2. Enable hugepages 
    echo 8196 > /sys/kernel/mm/hugepages/hugepages-2048kB/nr_hugepages

##### 3. Install DPDK 17.11
    Build DPDK with following parameters
        CONFIG_RTE_MAX_ETHPORTS=64 in /<dpdk-dir>/config/common_base
        CONFIG_RTE_LIBRTE_VHOST_NUMA=y in /<dpdk-dir>/config/common_base
        CONFIG_RTE_LIBRTE_NFP_PMD=y in /<dpdk-dir>/config/common_base

##### 4. Enable Netronome repos
    wget https://deb.netronome.com/gpg/NetronomePublic.key
    apt-key add NetronomePublic.key
    echo "deb https://deb.netronome.com/apt stable main" > /etc/apt/sources.list.d/netronome.list
    apt-get update

##### 5. Install from repos
    apt-get install agilio-nfp-driver-dkms 
    apt-get install nfp-bsp-6000-b0
    apt-get install agilio-flower-app-firmware
    
##### 6. Install OVS 2.9 from source 
    git clone https://github.com/openvswitch/ovs.git
    git checkout branch-2.9
    ./boot.sh
    ./configure.sh
    make -j 8
    make -j 8 install

##### 7. Virtio install (only on XVIO nodes)
    apt install protobuf-c-compiler libprotobuf-c0-dev libzmq3-dev protobuf-compiler python3-sphinx libnuma-dev libdpdk-dev dpdk-dev libpcap-dev libxen-dev
    git clone https://github.com/Netronome/virtio-forwarder
    export RTE_SDK=<DPDK dir>
    export RTE_TARGET=x86_64-native-linuxapp-gcc

##### 8. Prep VMs
    Ubuntu 16.04
    Build DPDK 
        wget http://fast.dpdk.org/rel/dpdk-17.11.2.tar.xz
    Build prox
        git clone https://github.com/opnfv/samplevnf.git



