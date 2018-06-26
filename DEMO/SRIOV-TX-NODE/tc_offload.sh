#!/bin/bash

switchid="00154d"

policy="none"
ctrl="true"
if [ "$1" = "disable" ]; then
  policy="skip_hw"
  ctrl="false"
fi

ovs-vsctl --no-wait set Open_vSwitch . other_config:hw-offload=$ctrl
ovs-vsctl --no-wait set Open_vSwitch . other_config:tc-policy=$policy
/usr/local/share/openvswitch/scripts/ovs-ctl restart

exit

rm -f /tmp/$0.log
for ifc in `ip -d link show | grep -B2 $switchid | awk '/mtu/ {print $2}' | tr -d ':'`; do
  ifconfig $ifc down
  ethtool -K $ifc hw-tc-offload $ctrl >> /tmp/$0.log 2>&1
  echo "$ifc: $(ethtool -k $ifc 2>/dev/null | grep 'hw-tc-offload')"
  ifconfig $ifc up
done

  ovs-vsctl --no-wait set Open_vSwitch . other_config:tc-policy=none
