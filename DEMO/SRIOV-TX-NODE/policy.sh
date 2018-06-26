#!/bin/bash

set -x
ovs-ofctl add-flow br0 priority=50000,tcp,tp_src=1,tp_dst=1,actions=drop
ovs-ofctl dump-flows br0 | grep drop
sleep 5
ovs-ofctl dump-flows br0 | grep drop

