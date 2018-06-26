#!/bin/bash

######################################################
# Please enter PCI addresses into the correct fields #
######################################################
# pci_vf1=""
# pci_vf2=""
######################################################

# PROX config setup
VM_TX_MAC1=$(cat setup_diagram.txt | grep VM_TX_MAC1=[0-9a-z] | cut -d '=' -f2)
VM_TX_MAC2=$(cat setup_diagram.txt | grep VM_TX_MAC2=[0-9a-z] | cut -d '=' -f2)
VM_4D_MAC1=$(cat setup_diagram.txt | grep VM_4D_MAC1=[0-9a-z] | cut -d '=' -f2)
VM_4D_MAC2=$(cat setup_diagram.txt | grep VM_4D_MAC2=[0-9a-z] | cut -d '=' -f2)

if [ -z "$VM_TX_MAC1" ] || [ -z "$VM_TX_MAC1" ] || [ -z "$VM_4D_MAC1" ] || [ -z "$VM_4D_MAC1" ]
then
  echo "Please complete setup_diagram.txt MAC addresses"
  exit -1
fi

if [ -z $pci_vf1 ] || [ -z $pci_vf1 ]
then
  echo "Please complete PCI config fields in script"
  exit -1
fi

sed -i "s/^\$srcmac1=.*/\$srcmac1=$VM_TX_MAC1/g" ./config.cfg
sed -i "s/^\$srcmac2=.*/\$srcmac1=$VM_TX_MAC2/g" ./config.cfg
sed -i "s/^\$dstmac1=.*/\$dstmac2=$VM_4D_MAC1/g" ./config.cfg
sed -i "s/^\$dstmac2=.*/\$dstmac2=$VM_4D_MAC2/g" ./config.cfg

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

netdev_1=$(ls /sys/bus/pci/devices/*${pci_vf1}/net/ 2>/dev/null || echo "Interface down")
echo $netdev_1
netdev_2=$(ls /sys/bus/pci/devices/*${pci_vf2}/net/ 2>/dev/null || echo "Interface down")
echo $netdev_2

if [ "$netdev_1" != "Interface down" ]
then
  ip l set dev $netdev_1 down
fi
if [ "$netdev_2" != "Interface down" ]
then
  ip l set dev $netdev_2 down
fi

devbind=$(find / -name "dpdk-devbind.py" | head -n 1)
if [ -z $devbind ]
then
  echo "Cannot bind VFS: dpdk-devbind not found"
  exit -1
fi

$devbind -b igb_uio $pci_vf1 $pci_vf2

prox=$(find / -name "prox" | head -n 1)
if [ -z $prox ]
then
  echo "Cannot find PROX"
  exit -1
fi

$prox -f config.cfg


