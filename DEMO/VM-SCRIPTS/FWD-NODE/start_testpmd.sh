#!/bin/bash

#######################################################################
# Please enter MAC addresses of VM on TX side into the correct fields #
#######################################################################
# mac_1=<This will be VM_TX_MAC1 in setup diagram>
# mac_2=<This will be VM_TX_MAC2 in setup diagram>
######################################################
# Please enter PCI addresses into the correct fields #
######################################################
# pci_vf1=
# pci_vf2=
######################################################

if [ -z $mac_1 ] || [ -z $mac_2 ] || [ -z $pci_vf1 ] || [ -z $pci_vf1 ]
then
  echo "Please complete config fields in script"
  exit -1
fi

echo 1024 > /sys/kernel/mm/hugepages/hugepages-2048kB/nr_hugepages


modprobe uio
rmmod igb_uio

igb_uio_driver=$(find / -name "igb_uio.ko" | head -n 1)
if [ -z $igb_uio_driver ]
then
  echo "Cannot load driver IGB_UIO: Not found"
  exit -1
fi

insmod $igb_uio_driver

netdev_1=$(ls /sys/bus/pci/devices/*${pci_vf1}*/net/)
netdev_2=$(ls /sys/bus/pci/devices/*${pci_vf2}*/net/)
ip l set dev $netdev_1 down
ip l set dev $netdev_2 down

devbind=$(find / -name "dpdk-devbind.py" | head -n 1)
if [ -z $devbind ]
then
  echo "Cannot bind VFS: dpdk-devbind not found"
  exit -1
fi

$devbind -b igb_uio $pci_vf1 $pci_vf2
whitelist="-w $pci_vf2 -w $pci_vf2"
peer="--eth-peer=0,$mac_1 --eth-peer=1,$mac_2"

testpmd=$(find / -name "testpmd" | head -n1)
if [ -z $testpmd ]
then
  echo "Testpmd not found!"
  exit -1
fi

$testpmd -n 4 \
    $whitelist \
    --socket-mem $((2*1024)) \
    -- \
    --portmask 0x3 \
    --nb-cores=4 \
    --rxd 2048 \
    --txd 2048 \
    --disable-hw-vlan $peer \
    --forward-mode=mac \
    --disable-crc-strip \
    --mbuf-size=4276







