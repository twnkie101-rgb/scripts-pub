#!/bin/bash

if [ "$EUID" -ne 0 ]; then
    echo "Ошибка: Этот скрипт нужно запускать от имени root!"
    exit 1
fi


sed -i.bak '/^tmpfs[[:space:]]\+\/tmp/s/^/#/' /etc/fstab
sed -i.bak -E 's/\b(nosuid|noxattr),//g; s/,\b(nosuid|noxattr)\b//g' /etc/fstab
reboot
