#!/bin/bash

set -e

if [ "$EUID" -ne 0 ]; then
    echo "Ошибка: Этот скрипт нужно запускать от имени root!"
    exit 1
fi

repo_path="/opt/repo"

if [[ ! -f "$repo_path/x86_64/base/release" ]]; then
    echo "Ошибка: локальный репозиторий поврежден или не примонтирован."
    exit 1
fi

read -p "Введите FQDN имя сервера (прим. iwtm.test.local): " fqdn_name
read -p "Введите IP адрес и маску сервера (прим. 192.168.1.2/24): " ip_serv
read -p "Введите IP адрес шлюза по умолчанию (прим. 192.168.1.1): " ip_gate
read -p "Контроллер домена имеет такой же IP как у шлюза по умолчанию? [Y/n]: " req_dc
case "${req_dc,,}" in
	""|"y"|"yes")
		ip_dc="$ip_gate"
		;;
	"n"|"no")
		read -p "Введите адрес контроллера домена: " ip_dc
		;;
	*)
		echo "Ошибка: неверный ответ"
		exit 1
		;;
esac

ip_only="${ip_serv%/*}"

ip -br a

read -p "Введите название сетевого интерфейса для настройки: " iface_name

hostnamectl set-hostname $fqdn_name
cat << EOF > /etc/hosts
127.0.0.1 localhost.localdomain localhost
$ip_only $(hostname -f) $(hostname -s)
::1 localhost6.localdomain localhost6
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

fqdn=$(hostname -f)
host=$(hostname -s)
domain=$(hostname -d)
realm=${domain%%.*}
realm_upper=${realm^^}
read -p "Введите имя локального администратора: " localadmin

PAM_FILE="/etc/pam.d/system-auth"
PAM_LINE="session\trequired\tpam_mkhomedir.so skel=/etc/skel umask=0077"
SSH_FILE="/etc/openssh/sshd_config"

cat << 'EOF' > /etc/apt/sources.list.d/sources.list

#rpm cdrom:[ALT SP Server 10.2.2 11100-01 x86_64 build 2025-12-03]/ ALTLinux main
rpm file:/opt/repo x86_64 base
EOF

rm -rf /opt/repo.tar.gz

sed -i -E 's/^#?PubkeyAuthentication.*/PubkeyAuthentication yes/' "$SSH_FILE"

sed -i -E 's/^#?PasswordAuthentication.*/PasswordAuthentication yes/' "$SSH_FILE"

sed -i -E 's/^#?PermitEmptyPasswords.*/PermitEmptyPasswords no/' "$SSH_FILE"

apt-get update
apt-get install sudo task-auth-ad-sssd oddjob-mkhomedir -y

join_domain() {
	read -p "Введите имя администратора домена: " admin_name
	read -p "Введите пароль админитратора домена: " admin_pass
	echo -e "${admin_name}@${domain} ALL=(ALL:ALL) ALL" | tee -a /etc/sudoers
	system-auth write ad "$domain" "$host" "$realm_upper" "$admin_name" "$admin_pass"
	systemctl enable --now oddjobd
}

read -p "Потребуется ли вводить сервер в домен? [Y/n]: " req_domain

case "${req_domain,,}" in
	""|"y"|"yes")
		join_domain
		;;
	"n"|"no")
		echo "Пропускаем ввод в домен"
		;;
	*)
		echo "Ошибка: неверный ответ"
		exit 1
		;;
esac

echo "WHEEL_USERS ALL=(ALL:ALL) ALL" | tee -a /etc/sudoers

usermod -aG wheel $localadmin

grep -q "pam_mkhomedir.so" "$PAM_FILE" || echo -e "$PAM_LINE" | tee -a "$PAM_FILE"

sed -i.bak '/^tmpfs[[:space:]]\+\/tmp/s/^/#/' /etc/fstab
sed -i.bak -E 's/\b(nosuid|noxattr),//g; s/,\b(nosuid|noxattr)\b//g' /etc/fstab

echo "Скрипт выполнит перезагрузку ОС через 5 секунд"
sleep 5
reboot

