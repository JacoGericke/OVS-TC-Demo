#!/bin/bash

#remote_ip1=10.10.10.10
#remote_ip2=20.20.20.20

#local_ip1=10.10.10.100
#local_ip2=20.20.20.200

bridge=br0
mac_repr1=ens3np0np0
mac_repr2=ens3np1np1
pf_netdev=ens3

ifconfig $pf_netdev mtu 9100


VF0="$(ip -d link show | grep -B 2 'pf0vf21 ' | awk '/: eth/ {print $2}'| tr -d ':')"
VF1="$(ip -d link show | grep -B 2 'pf0vf22 ' | awk '/: eth/ {print $2}'| tr -d ':')"

echo "[$VF0 $VF1]"
ovs-vsctl del-br ${bridge}
ovs-vsctl add-br ${bridge}

ovs-ofctl del-flows ${bridge}
## Tunnel ports, with key = flow
#ovs-vsctl add-port ${bridge} tun0 -- set Interface tun0 type=vxlan options:local_ip=$local_ip1 options:remote_ip=$remote_ip1 options:key=flow ofport_request=1000
#ovs-vsctl add-port ${bridge} tun1 -- set Interface tun1 type=vxlan options:local_ip=$local_ip2 options:remote_ip=$remote_ip2 options:key=flow ofport_request=1001

ovs-vsctl add-port ${bridge} ${mac_repr1} -- set Interface ${mac_repr1} ofport_request=1000

## VF representors
# Loop over all reprs

ovs-vsctl add-port ${bridge} $VF0 -- set Interface $VF0 ofport_request=22
ifconfig $VF0 up mtu 9100

ovs-vsctl add-port ${bridge} $VF1 -- set Interface $VF1 ofport_request=23
ifconfig $VF1 up mtu 9100

# MAC representors
# NOTE: Here is how we will swap to a flat network, we just add these ports into
# the bridge instead of the tunnel ports above. Then drop the 'set_tunnel' actions
# from the rules below.
ifconfig $mac_repr1 up mtu 9100
ifconfig $mac_repr2 up mtu 9100

rm -r /tmp/flows.txt

##########
# EGRESS #
##########

for match_val in $(seq 0 16383); do
  echo "in_port=23,tcp,tcp_dst=$match_val,actions=1000" >>  /tmp/flows.txt
#  echo "in_port=22,tcp,tcp_dst=$match_val,actions=1000" >>  /tmp/flows.txt
done

for match_val in $(seq 16383 32767); do
  echo "in_port=22,tcp,tcp_dst=$match_val,actions=1000" >>  /tmp/flows.txt
#  echo "in_port=23,tcp,tcp_dst=$match_val,actions=1000" >>  /tmp/flows.txt
done


###########
# INGRESS #
###########

for match_val in $(seq 0 16383); do
  echo "in_port=1000,tcp,tcp_dst=$match_val,actions=22" >> /tmp/flows.txt
done

for match_val in $(seq 16383 32767); do
  echo "in_port=1000,tcp,tcp_dst=$match_val,actions=23" >> /tmp/flows.txt
done


ovs-ofctl replace-flows --bundle ${bridge} /tmp/flows.txt


