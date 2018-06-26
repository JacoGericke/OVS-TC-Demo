#!/bin/bash 

sw=$(taskset 0x1 ovs-dpctl dump-flows 2>/dev/null| wc -l)
hw=$(taskset 0x1 ovs-dpctl dump-flows type=offloaded 2>/dev/null| wc -l)

echo "OVS datapath flows = $hw"
echo "Offloaded datapath flows = $hw"
