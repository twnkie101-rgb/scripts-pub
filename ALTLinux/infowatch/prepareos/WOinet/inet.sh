#!/bin/bash

set -e

if [ "$EUID" -ne 0 ]; then
    echo "Ошибка: Этот скрипт нужно запускать от имени root!"
    exit 1
fi

read -p "Введите FQDN имя сервера (прим. iwtm.test.local): " fqdn_name
read -p "Введите IP адрес и маску сервера (прим. 192.168.1.2/24): " ip_serv
read -p "Введите IP адрес шлюза по умолчанию (прим. 192.168.1.1): " ip_gate
read -p "Введите IP адрес контроллера домена (прим. 192.168.1.1): " ip_dc

ip -br a

read -p "Введите название сетевого интерфейса для настройки: " iface_name

hostnamectl set-hostname $fqdn_name
cat << EOF > /etc/hosts
127.0.0.1      localhost.localdomain localhost
127.0.1.1      $(hostname -f) $(hostname -s)
::1      localhost6.localdomain localhost6
EOF

mkdir -p /etc/net/ifaces/$iface_name/

cat << EOF > /etc/net/ifaces/$iface_name/options
BOOTPROTO=static
TYPE=eth
ONBOOT=yes
EOF

cat << EOF > /etc/net/ifaces/$iface_name/ipv4address
$ip_serv
EOF

cat << EOF > /etc/net/ifaces/$iface_name/ipv4route
default via $ip_gate
EOF

cat << EOF > /etc/net/ifaces/$iface_name/resolv.conf
search $(hostname -d)
nameserver $ip_dc
EOF

systemctl restart network

echo "Скрипт закончил работу"
