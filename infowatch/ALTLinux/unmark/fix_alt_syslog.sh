#!/bin/bash

set -e

if [ "$EUID" -ne 0 ]; then
    echo "Ошибка: Этот скрипт нужно запускать от имени root!"
    exit 1
fi

sed -i 's/^#ForwardToSyslog=no$/ForwardToSyslog=yes/' /etc/systemd/journald.conf
systemctl restart systemd-journald
systemctl restart rsyslog

