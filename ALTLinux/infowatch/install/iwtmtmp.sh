#!/bin/bash

sed -i.bak '/^tmpfs[[:space:]]\+\/tmp/s/^/#/' /etc/fstab
sed -i.bak -E 's/\b(nosuid|noxattr),//g; s/,\b(nosuid|noxattr)\b//g' /etc/fstab
reboot
