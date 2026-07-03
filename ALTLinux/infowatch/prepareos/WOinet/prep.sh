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

fqdn=$(hostname -f)
host=$(hostname -s)
domain=$(hostname -d)
realm=${domain%%.*}
realm_upper=${realm^^}
read -p "Введите имя локального администратора: " localadmin
read -p "Введите имя администратора домена: " admin_name
read -p "Введите пароль админитратора домена: " admin_pass

PAM_FILE="/etc/pam.d/system-auth"
PAM_LINE="session\trequired\tpam_mkhomedir.so skel=/etc/skel umask=0077"
SSH_FILE="/etc/openssh/sshd_config"

cat << 'EOF' > /etc/apt/sources.list.d/sources.list

#rpm cdrom:[ALT SP Server 10.2.2 11100-01 x86_64 build 2025-12-03]/ ALTLinux main
rpm file:/opt/repo x86_64 classic
EOF

rm -rf /opt/repo.tar.gz

sed -i -E 's/^#?PubkeyAuthentication.*/PubkeyAuthentication yes/' "$SSH_FILE"

sed -i -E 's/^#?PasswordAuthentication.*/PasswordAuthentication yes/' "$SSH_FILE"

sed -i -E 's/^#?PermitEmptyPasswords.*/PermitEmptyPasswords no/' "$SSH_FILE"

apt-get update 
apt-get install sudo task-auth-ad-sssd oddjob-mkhomedir -y 

echo "WHEEL_USERS ALL=(ALL:ALL) ALL" | tee -a /etc/sudoers 
echo -e "${admin_name}@${domain} ALL=(ALL:ALL) ALL" | tee -a /etc/sudoers 

usermod -aG wheel $localadmin

system-auth write ad "$domain" "$host" "$realm_upper" "$admin_name" "$admin_pass" 

systemctl enable --now oddjobd 

grep -q "pam_mkhomedir.so" "$PAM_FILE" || echo -e "$PAM_LINE" | tee -a "$PAM_FILE" 

sed -i.bak '/^tmpfs[[:space:]]\+\/tmp/s/^/#/' /etc/fstab
sed -i.bak -E 's/\b(nosuid|noxattr),//g; s/,\b(nosuid|noxattr)\b//g' /etc/fstab

echo "Скрипт выполнит перезагрузку ОС через 5 секунд"
sleep 5
reboot
