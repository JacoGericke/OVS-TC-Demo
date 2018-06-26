#!/bin/bash

VM_NAME=test1
VM_CPU_COUNT=5

VF_NAME_11="virtfn11"
VF_NAME_12="virtfn12"

VF11="pf0vf11"
VF12="pf0vf12"

BRIDGE_NAME=br0

echo 8196 > /sys/kernel/mm/hugepages/hugepages-2048kB/nr_hugepages

path_ovs=$(find /root/ovs -name "ovs-ctl" | sed 's=/ovs-ctl==g' | grep ovs | sed -n 1p)
test=$(echo $PATH | grep $path_ovs)
if [[ -z "$test" ]];then
    export PATH="$PATH:$path_ovs"
    echo "PATH=\"$PATH\"" > /etc/environment
fi

DPDK_DEVBIND=$(find /opt/src -name "dpdk-devbind.py" | head -1)
if [ -z $DPDK_DEVBIND ]
then
  echo "Could not find dpdk-devbind.py"
  exit -1
fi

##############################################################################################################
# FUNCTIONS
##############################################################################################################

function find_repr()
{
  local REPR=$1
  for i in /sys/class/net/*;
  do
    phys_port_name=$(cat $i/phys_port_name 2>&1 /dev/null)
    if [ "$phys_port_name" == "$REPR" ];
    then
      echo "$i"
    fi
  done
}

function bind_vfio()
{
  DRIVER=vfio-pci
  lsmod | grep --silent vfio_pci || modprobe vfio_pci
  INTERFACE_PCI=$1
  current=$(lspci -ks ${INTERFACE_PCI} | awk '/in use:/ {print $5}')
  echo "INTERFACE_PCI: $INTERFACE_PCI"
  echo "current driver: $current"
  echo "expected driver: $DRIVER"
  if [ "$current" != "$DRIVER" ]; then
    if [ "$current" != "" ]; then
      echo "testing: bind $current on ${INTERFACE_PCI}"
      echo ${INTERFACE_PCI} > /sys/bus/pci/devices/${INTERFACE_PCI}/driver/unbind
      echo ${DRIVER} > /sys/bus/pci/devices/${INTERFACE_PCI}/driver_override
      echo ${INTERFACE_PCI} > /sys/bus/pci/drivers/vfio-pci/bind
    fi
  fi
}

function clean-ovs-bridges()
{
  ovs-vsctl list-br | while read BRIDGE;
  do
    echo "Deleting: $BRIDGE"
    ovs-vsctl del-br $BRIDGE
  done
}

function general-ovs-config()
{
  ovs-vsctl --no-wait set Open_vSwitch . other_config:hw-offload=true
  ovs-vsctl --no-wait set Open_vSwitch . other_config:tc-policy=none
  ovs-vsctl --no-wait set Open_vSwitch . other_config:max-idle=10000
  ovs-vsctl set Open_vSwitch . other_config:flow-limit=1000000
}

##############################################################################################################
# RESTART OVS
##############################################################################################################

pci=$(lspci -d 19ee: | grep 4000 | cut -d ' ' -f1)
if [[ "$pci" == *":"*":"*"."* ]]; then
    echo "PCI correct format"
elif [[ "$pci" == *":"*"."* ]]; then
    echo "PCI corrected"
    pci="0000:$pci"
fi
echo $pci

/root/ovs/utilities/ovs-ctl stop

echo "Remove VFs"
echo 0 > /sys/bus/pci/devices/$pci/sriov_numvfs

ip link set $(find_repr pf0 | rev | cut -d "/" -f 1 | rev) down
ip link set $(find_repr p1 | rev | cut -d "/" -f 1 | rev) down
ip link set $(find_repr p0 | rev | cut -d "/" -f 1 | rev) down

echo "Reloading nfp module"
rmmod nfp
sleep 1
modprobe nfp nfp_dev_cpp=1


echo "32" > /sys/bus/pci/devices/$pci/sriov_numvfs
echo "Creating 32 VFs"

for ndev in $(ls /sys/bus/pci/devices/$pci/net); do
    echo $ndev
    ip l set $ndev up
    ethtool -K $ndev hw-tc-offload on
done
echo "Start OVS"
/root/ovs/utilities/ovs-ctl start


general-ovs-config
clean-ovs-bridges

##############################################################################################################
# SETUP TEST CASE
##############################################################################################################

ovs-vsctl add-br $BRIDGE_NAME

repr_vf11=$(find_repr $VF11 | rev | cut -d '/' -f 1 | rev)
echo "Add $repr_vf11 to $BRIDGE_NAME"
ovs-vsctl add-port $BRIDGE_NAME $repr_vf11 -- set interface $repr_vf11 type=vxlan ofport_request=11
ip link set $repr_vf11 up

VF11_PCI_ADDRESS=$(readlink -f /sys/bus/pci/devices/${pci}/${VF_NAME_11} | rev | cut -d '/' -f1 | rev)
echo "VF11_PCI_ADDRESS: $VF11_PCI_ADDRESS"
bind_vfio ${VF11_PCI_ADDRESS}
echo "FIRST VF DONE"


repr_vf12=$(find_repr $VF12 | rev | cut -d '/' -f 1 | rev)
echo "Add $repr_vf12 to $BRIDGE_NAME"
ovs-vsctl add-port $BRIDGE_NAME $repr_vf12 -- set interface $repr_vf12 type=vxlan ofport_request=12
ip link set $repr_vf12 up

VF12_PCI_ADDRESS=$(readlink -f /sys/bus/pci/devices/${pci}/${VF_NAME_12} | rev | cut -d '/' -f1 | rev)
echo "VF12_PCI_ADDRESS: $VF12_PCI_ADDRESS"
bind_vfio ${VF12_PCI_ADDRESS}
echo "SECOND VF DONE"


# UP PFs
#PF
repr_pf0=$(find_repr pf0 | rev | cut -d "/" -f 1 | rev)
echo "pf0 = $repr_pf0"
ip link set $repr_pf0 up

#NFP_P0
repr_p0=$(find_repr p0 | rev | cut -d "/" -f 1 | rev)
echo "p0 = $repr_p0"
ip link set $repr_p0 up

#NFP_P1
repr_p1=$(find_repr p1 | rev | cut -d "/" -f 1 | rev)
echo "p1 = $repr_p1"
ip link set $repr_p1 up


ovs-vsctl add-port $BRIDGE_NAME $repr_p0 -- set interface $repr_p0 ofport_request=1

ovs-ofctl del-flows $BRIDGE_NAME


################################################
# ADD IN OUT RULES
################################################

ovs-ofctl add-flow $BRIDGE_NAME in_port=11,actions=1
ovs-ofctl add-flow $BRIDGE_NAME in_port=12,actions=1

ovs-ofctl add-flow $BRIDGE_NAME in_port=1,dl_type=0x0800,nw_dst=10.10.10.1,actions=11
ovs-ofctl add-flow $BRIDGE_NAME in_port=1,dl_type=0x0800,nw_dst=20.20.20.1,actions=12

ovs-ofctl add-flow $BRIDGE_NAME in_port=1,dl_type=0x0806,actions=11,12

ovs-vsctl set Open_vSwitch . other_config:n-handler-threads=1
ovs-vsctl set Open_vSwitch . other_config:n-revalidator-threads=1

ovs-vsctl show
ovs-ofctl show $BRIDGE_NAME


###############################################
# VM XML EDIT
###############################################

max_memory=$(virsh dominfo $VM_NAME | grep 'Max memory:' | awk '{print $3}')

# Remove vhostuser interface
EDITOR='sed -i "/<interface type=.vhostuser.>/,/<\/interface>/d"' virsh edit $VM_NAME
EDITOR='sed -i "/<hostdev mode=.subsystem. type=.pci./,/<\/hostdev>/d"' virsh edit $VM_NAME

bus=$(echo $VF12_PCI_ADDRESS | cut -d ':' -f2 )

slot_1=$(echo $VF11_PCI_ADDRESS | cut -d ':' -f3 | cut -d '.' -f1 )
slot_2=$(echo $VF12_PCI_ADDRESS | cut -d ':' -f3 | cut -d '.' -f1 )

func_1=$(echo $VF11_PCI_ADDRESS | cut -d '.' -f2 )
func_2=$(echo $VF12_PCI_ADDRESS | cut -d '.' -f2 )

sleep 1

EDITOR='sed -i "/<devices/a \<hostdev mode=\"subsystem\" type=\"pci\" managed=\"yes\">  <source> <address domain=\"0x0000\" bus=\"0x'${bus}'\" slot=\"0x'$slot_1'\" function=\"0x'$func_1'\"\/> <\/source>  <address type=\"pci\" domain=\"0x0000\" bus=\"0x00\" slot=\"0x0a\" function=\"0x0\"\/> <\/hostdev>"' virsh edit $VM_NAME
EDITOR='sed -i "/<devices/a \<hostdev mode=\"subsystem\" type=\"pci\" managed=\"yes\">  <source> <address domain=\"0x0000\" bus=\"0x'${bus}'\" slot=\"0x'$slot_2'\" function=\"0x'$func_2'\"\/> <\/source>  <address type=\"pci\" domain=\"0x0000\" bus=\"0x00\" slot=\"0x0b\" function=\"0x0\"\/> <\/hostdev>"' virsh edit $VM_NAME

EDITOR='sed -i "/<cpu /,/<\/cpu>/d"' virsh edit $VM_NAME
EDITOR='sed -i "/<memoryBacking>/,/<\/memoryBacking>/d"' virsh edit $VM_NAME

# MemoryBacking
EDITOR='sed -i "/<domain/a \<memoryBacking><hugepages><page size=\"2048\" unit=\"KiB\" nodeset=\"0\"\/><\/hugepages><\/memoryBacking>"' virsh edit $VM_NAME
EDITOR='sed -i "/<domain/a \<cpu mode=\"host-model\"><model fallback=\"allow\"\/><numa><cell id=\"0\" cpus=\"0-'$((VM_CPU_COUNT-1))'\" memory=\"'${max_memory}'\" unit=\"KiB\" memAccess=\"shared\"\/><\/numa><\/cpu>"' virsh edit $VM_NAME



#############################################
# VM PINNING
##############################################

card_node=$(cat /sys/bus/pci/drivers/nfp/0*/numa_node | head -n1 | cut -d " " -f1)
nfp_cpu_list=$(lscpu -a -p | awk -F',' -v var="$card_node" '$4 == var {printf "%s%s",sep,$1; sep=" "} END{print ""}')

nfp_cpu_list=($nfp_cpu_list)
echo "nfp_cpu_list: ${nfp_cpu_list[@]}"
sleep 5

for counter in $(seq 0 $((VM_CPU_COUNT-1)))
  do
    virsh --quiet vcpupin $VM_NAME $counter ${nfp_cpu_list[$counter+1]} --config
  done
virsh vcpupin $VM_NAME




