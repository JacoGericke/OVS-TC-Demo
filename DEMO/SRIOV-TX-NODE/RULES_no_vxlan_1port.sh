#!/bin/bash

bridge=br0
mac_repr1=ens1np0
mac_repr2=ens1np1

ifconfig ens1 mtu 9100

VF0=$(ip -d link show | grep -B 2 'pf0vf11 ' | awk '/: eth/ {print $2}'| tr -d ':')
VF1=$(ip -d link show | grep -B 2 'pf0vf12 ' | awk '/: eth/ {print $2}'| tr -d ':')
echo "$VF0"
echo "$VF1"
ovs-vsctl del-br ${bridge}
ovs-vsctl add-br ${bridge}

ovs-ofctl del-flows ${bridge}

ovs-vsctl add-port ${bridge} $mac_repr1 -- set Interface $mac_repr1 ofport_request=1000

## VF representors
# Loop over all reprs
ovs-vsctl add-port ${bridge} $VF0 -- set Interface $VF0 ofport_request=22
ifconfig $VF0 up mtu 9100
ovs-vsctl add-port ${bridge} $VF1 -- set Interface $VF1 ofport_request=23
ifconfig $VF1 up mtu 9100

## MAC representors
# NOTE: Here is how we will swap to a flat network, we just add these ports into
# the bridge instead of the tunnel ports above. Then drop the 'set_tunnel' actions
# from the rules below.

ifconfig $mac_repr1 0 up mtu 9100
ifconfig $mac_repr2 0 up mtu 9100


rm -r /tmp/flows.txt

##########
# EGRESS #
##########

for match_val in $(seq 0 16383); do
  echo "in_port=22,tcp,tcp_dst=$match_val,actions=1000" >> /tmp/flows.txt
done

for match_val in $(seq 16383 32767); do
  echo "in_port=23,tcp,tcp_dst=$match_val,actions=1000" >> /tmp/flows.txt
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




