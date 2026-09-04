#!/bin/bash

if [ "$EUID" -ne 0 ]; then
    echo "Ошибка: Этот скрипт нужно запускать от имени root!"
    exit 1
fi

repo_path="/opt/repo"
OPENSSL_CONF="/etc/openssl/openssl.cnf"

if [[ ! -f "$repo_path/x86_64/base/release" ]]; then
    echo "Ошибка: локальный репозиторий поврежден или не примонтирован."
    exit 1
fi

cat << 'EOF' >> /etc/sysctl.conf
fs.inotify.max_user_instances = 16384
fs.inotify.max_user_watches = 32768
fs.inotify.max_queued_events = 262144
fs.file-max = 500000
EOF

sysctl -p

apt-get update

apt-get install conntrack-tools socat podman unzip python-modules-sqlite3 python-modules-json python-modules-distutils -y

rm -rf /etc/cni/net.d/*
echo "Скрипт закончил работу"
