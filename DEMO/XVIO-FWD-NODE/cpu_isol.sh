#!/bin/bash

PIDS=$(pstree -pn | grep -v libvirt | grep -v virtio | grep -v slave | grep -v vfio | grep -v qemu | grep -v KVM| grep -o --color '([0-9]*)$' | sed 's/[()]//g' )
for i in $PIDS; do  taskset -pc 0 $i ; done

