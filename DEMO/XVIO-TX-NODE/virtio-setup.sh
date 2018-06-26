#!/bin/bash

#./hugepages.sh
chmod 777 /tmp/virtio-forwarder
echo 9096 > /sys/kernel/mm/hugepages/hugepages-2048kB/nr_hugepages
modprobe vfio-pci
modprobe nfp nfp_dev_cpp=1

XVIO_CORES=2

VM_NAME=prox1
VM_CPU_COUNT=5

VF_NAME_21="virtfn21"
VF_NAME_22="virtfn22"

VF21="pf0vf21"
VF22="pf0vf22"

BRIDGE_NAME=br0


path_ovs=$(find /root/ovs -name "ovs-ctl" | sed 's=/ovs-ctl==g' | grep ovs | sed -n 1p)
test=$(echo $PATH | grep $path_ovs)
if [[ -z "$test" ]];then
    export PATH="$PATH:$path_ovs"
    echo $PATH
    echo "PATH=\"$PATH\"" > /etc/environment
fi


DPDK_DEVBIND=$(find /opt/src -name "dpdk-devbind.py" | head -1)

systemctl stop virtio-forwarder
ovs-ctl stop

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

function bind_igb_uio()
{
  DRIVER=vfio-pci
  lsmod | grep --silent vfio-pci || modprobe vfio-pci
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
  ovs-vsctl --no-wait set Open_vSwitch . other_config:max-idle=60000
  ovs-vsctl set Open_vSwitch . other_config:flow-limit=1000000
}

##############################################################################################################
# SETUP VIRTIOFORWARDER
##############################################################################################################


ovs_db=$(find / -name "db.sock")

card_node=$(cat /sys/bus/pci/drivers/nfp/0*/numa_node | head -n1 | cut -d ' ' -f1)

nfp_cpu_list=$(lscpu -a -p | awk -F',' -v var="$card_node" '$4 == var {printf "%s%s",sep,$1; sep=" "} END{print ""}')

xvio_cpus_list=()
nfp_cpu_list=( $nfp_cpu_list )

#echo "NFP CPU: $nfp_cpu_list"
for i in ${nfp_cpu_list[@]}; do echo $i; done

for counter in $(seq 0 $((XVIO_CORES-1)))
  do
        echo ""
        echo "count : $counter "
        echo "${nfp_cpu_list[$counter+1]}"
        echo ""
	xvio_cpus_list+=(${nfp_cpu_list[$counter+1]})
done

#echo "XVIO CPUS: $xvio_cpus_list"
#for i in ${xvio_cpus_list[@]}; do echo $i; done

for counter in $(seq 0 $((XVIO_CORES-1)))
  do
        echo ""
        echo "count : $counter "
        echo "${nfp_cpu_list[@]:1}"
        echo ""
	nfp_cpu_list=(${nfp_cpu_list[@]:1})
done
echo "NFP CPUS: $nfp_cpu_list"
for i in ${nfp_cpu_list[@]}; do echo $i; done

xvio_cpus_string=$(IFS=',';echo "${xvio_cpus_list[*]}";IFS=$' \t\n')

sed "s#^VIRTIOFWD_LOG_LEVEL=.*#VIRTIOFWD_LOG_LEVEL=7#g" -i /etc/default/virtioforwarder
sed "s#^VIRTIOFWD_ZMQ_PORT_CONTROL_EP=.*#VIRTIOFWD_ZMQ_PORT_CONTROL_EP=ipc:///var/run/virtio-forwarder/port_control#g" -i /etc/default/virtioforwarder
sed "s#^VIRTIOFWD_OVSDB_SOCK_PATH=.*#VIRTIOFWD_OVSDB_SOCK_PATH=$ovs_db#g" -i /etc/default/virtioforwarder
sed "s#^VIRTIOFWD_CPU_MASK=.*#VIRTIOFWD_CPU_MASK=$xvio_cpus_string#g" -i /etc/default/virtioforwarder
sed 's#^VIRTIOFWD_SOCKET_OWNER=.*#VIRTIOFWD_SOCKET_OWNER=libvirt-qemu#g' -i /etc/default/virtioforwarder
sed 's#^VIRTIOFWD_SOCKET_GROUP=.*#VIRTIOFWD_SOCKET_GROUP=kvm#g' -i /etc/default/virtioforwarder
sed 's#^VIRTIOFWD_MRGBUF=.*#VIRTIOFWD_MRGBUF=y#g' -i /etc/default/virtioforwarder
sed 's#^VIRTIOFWD_TSO=.*#VIRTIOFWD_TSO=y#g' -i /etc/default/virtioforwarder

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


echo "55" > /sys/bus/pci/devices/$pci/sriov_numvfs
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

repr_vf21=$(find_repr $VF21 | rev | cut -d '/' -f 1 | rev)
echo "Add $repr_vf21 to $BRIDGE_NAME"
ovs-vsctl add-port $BRIDGE_NAME $repr_vf21 -- set interface $repr_vf21 ofport_request=21 external_ids:virtio_forwarder=21
ip link set $repr_vf21 up
VF21_PCI_ADDRESS=$(readlink -f /sys/bus/pci/devices/${pci}/${VF_NAME_21} | rev | cut -d '/' -f1 | rev)
echo "VF21_PCI_ADDRESS: $VF21_PCI_ADDRESS"
bind_igb_uio ${VF21_PCI_ADDRESS}
echo "FIRST VF DONE"

repr_vf22=$(find_repr $VF22 | rev | cut -d '/' -f 1 | rev)
echo "Add $repr_vf22 to $BRIDGE_NAME"
ovs-vsctl add-port $BRIDGE_NAME $repr_vf22 -- set interface $repr_vf22 ofport_request=22 external_ids:virtio_forwarder=22
ip link set $repr_vf22 up
VF22_PCI_ADDRESS=$(readlink -f /sys/bus/pci/devices/${pci}/${VF_NAME_22} | rev | cut -d '/' -f1 | rev)
echo "VF22_PCI_ADDRESS: $VF22_PCI_ADDRESS"
bind_igb_uio ${VF22_PCI_ADDRESS}
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
# SETUP XVIO VFS
################################################

sed "s#^VIRTIOFWD_STATIC_VFS=.*#VIRTIOFWD_STATIC_VFS=($VF21_PCI_ADDRESS=21 $VF22_PCI_ADDRESS=22)#g" -i /etc/default/virtioforwarder


################################################
# ADD IN OUT RULES
################################################

ovs-ofctl add-flow $BRIDGE_NAME in_port=21,actions=1
ovs-ofctl add-flow $BRIDGE_NAME in_port=22,actions=1

ovs-ofctl add-flow $BRIDGE_NAME in_port=1,dl_type=0x0800,nw_dst=15.15.15.1,actions=21
ovs-ofctl add-flow $BRIDGE_NAME in_port=1,dl_type=0x0800,nw_dst=25.25.25.1,actions=22

ovs-ofctl add-flow $BRIDGE_NAME in_port=1,dl_type=0x0806,actions=21,22

ovs-vsctl set Open_vSwitch . other_config:n-handler-threads=1
ovs-vsctl set Open_vSwitch . other_config:n-revalidator-threads=1

ovs-vsctl set Open_vSwitch . other_config:flow-limit=1000000
ovs-appctl upcall/set-flow-limit 1000000
ovs-vsctl --no-wait set Open_vSwitch . other_config:hw-offload=true
ovs-vsctl --no-wait set Open_vSwitch . other_config:tc-policy=none 
ovs-vsctl --no-wait set Open_vSwitch . other_config:max-idle=60000

ovs-vsctl show
ovs-ofctl show $BRIDGE_NAME


###############################################
# VM XML EDIT
###############################################

max_memory=$(virsh dominfo $VM_NAME | grep 'Max memory:' | awk '{print $3}')

# Remove vhostuser interface
EDITOR='sed -i "/<interface type=.vhostuser.>/,/<\/interface>/d"' virsh edit $VM_NAME
EDITOR='sed -i "/<hostdev mode=.subsystem. type=.pci./,/<\/hostdev>/d"' virsh edit $VM_NAME

bus=$(echo $VF22_PCI_ADDRESS | cut -d ':' -f2 )

slot_1=$(echo $VF21_PCI_ADDRESS | cut -d ':' -f3 | cut -d '.' -f1 )
slot_2=$(echo $VF22_PCI_ADDRESS | cut -d ':' -f3 | cut -d '.' -f1 )

func_1=$(echo $VF21_PCI_ADDRESS | cut -d '.' -f2 )
func_2=$(echo $VF22_PCI_ADDRESS | cut -d '.' -f2 )

sleep 1

EDITOR='sed -i "/<devices/a \<interface type=\"vhostuser\">  <source type=\"unix\" path=\"/tmp/virtio-forwarder/virtio-forwarder21.sock\" mode=\"server\"\/>  <model type=\"virtio\"/>  <driver name=\"vhost\" queues=\"1\"\/>  <address type=\"pci\" domain=\"0x0000\" bus=\"0x01\" slot=\"0x0a\" function=\"0x0\"\/><\/interface>"' virsh edit $VM_NAME
EDITOR='sed -i "/<devices/a \<interface type=\"vhostuser\">  <source type=\"unix\" path=\"/tmp/virtio-forwarder/virtio-forwarder22.sock\" mode=\"server\"\/>  <model type=\"virtio\"/>  <driver name=\"vhost\" queues=\"1\"\/>  <address type=\"pci\" domain=\"0x0000\" bus=\"0x01\" slot=\"0x0b\" function=\"0x0\"\/><\/interface>"' virsh edit $VM_NAME

EDITOR='sed -i "/<cpu /,/<\/cpu>/d"' virsh edit $VM_NAME
EDITOR='sed -i "/<memoryBacking>/,/<\/memoryBacking>/d"' virsh edit $VM_NAME

# MemoryBacking
EDITOR='sed -i "/<domain/a \<memoryBacking><hugepages><page size=\"2048\" unit=\"KiB\" nodeset=\"0\"\/><\/hugepages><\/memoryBacking>"' virsh edit $VM_NAME
EDITOR='sed -i "/<domain/a \<cpu mode=\"host-model\"><model fallback=\"allow\"\/><numa><cell id=\"0\" cpus=\"0-'$((VM_CPU_COUNT-1))'\" memory=\"'${max_memory}'\" unit=\"KiB\" memAccess=\"shared\"\/><\/numa><\/cpu>"' virsh edit $VM_NAME



#############################################
# VM PINNING
##############################################

echo "NFP CPUS: $nfp_cpu_list"
for i in ${nfp_cpu_list[@]}; do echo $i; done


for counter in $(seq 0 $((VM_CPU_COUNT-1)))
  do
    virsh --quiet vcpupin $VM_NAME $counter ${nfp_cpu_list[$counter+1]} --config
  done
virsh vcpupin $VM_NAME

chmod 777 /tmp/virtio-forwarder/

echo "Starting Virtio..."
systemctl start virtio-forwarder






