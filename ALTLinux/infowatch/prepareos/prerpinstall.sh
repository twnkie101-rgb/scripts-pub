#!/bin/bash

if [ "$EUID" -ne 0 ]; then
    echo "Ошибка: Этот скрипт нужно запускать от имени root!"
    exit 1
fi

read -p "Введите FQDN(Например server.domain.name): " fqdn
domain="${fqdn#*.}"
domain_upper="${domain^^}"
read -p "Введите имя локального администратора: " localadmin
read -p "Введите имя администратора домена: " admin_name
read -p "Введите пароль админитратора домена: " admin_pass


hostnamectl set-hostname $fqdn 

PAM_FILE="/etc/pam.d/system-auth"
PAM_LINE="session\trequired\tpam_mkhomedir.so skel=/etc/skel umask=0077"
SSH_FILE="/etc/openssh/sshd_config"

cat << 'EOF' > /etc/apt/sources.list.d/altsp.list
# ALT Certified 10
#rpm [cert8] ftp://update.altsp.su/pub/distributions/ALTLinux c10f/branch/x86_64 classic gostcrypto
#rpm [cert8] ftp://update.altsp.su/pub/distributions/ALTLinux c10f/branch/x86_64-i586 classic
#rpm [cert8] ftp://update.altsp.su/pub/distributions/ALTLinux c10f/branch/noarch classic

rpm [cert8] http://update.altsp.su/pub/distributions/ALTLinux c10f/branch/x86_64 classic gostcrypto
rpm [cert8] http://update.altsp.su/pub/distributions/ALTLinux c10f/branch/x86_64-i586 classic
rpm [cert8] http://update.altsp.su/pub/distributions/ALTLinux c10f/branch/noarch classic
EOF

cat << 'EOF' > /etc/apt/sources.list.d/sources.list
#rpm cdrom:[ALT SP Server 11100-01 x86_64 build 2023-05-29]/ ALTLinux main
EOF

sed -i -E 's/^#?PubkeyAuthentication.*/PubkeyAuthentication yes/' "$SSH_FILE"

sed -i -E 's/^#?PasswordAuthentication.*/PasswordAuthentication yes/' "$SSH_FILE"

sed -i -E 's/^#?PermitEmptyPasswords.*/PermitEmptyPasswords no/' "$SSH_FILE"
 
sed -i "/\b127.0.1.1\b/d" /etc/hosts

echo -e "127.0.1.1\t$(hostname -f)\t$(hostname -s)" | tee -a /etc/hosts &> /dev/null

apt-get update &> /dev/null
apt-get install sudo task-auth-ad-sssd oddjob-mkhomedir -y &> /dev/null

echo "WHEEL_USERS ALL=(ALL:ALL) ALL" | tee -a /etc/sudoers &> /dev/null
echo -e "${admin_name}@${domain} ALL=(ALL:ALL) ALL" | tee -a /etc/sudoers &> /dev/null

usermod -aG wheel $(localadmin)

system-auth write ad "$domain" "$(hostname -s)" "$domain_upper" "$admin_name" "$admin_pass" &> /dev/null

systemctl enable --now oddjobd &> /dev/null

grep -q "pam_mkhomedir.so" "$PAM_FILE" || echo -e "$PAM_LINE" | tee -a "$PAM_FILE" &> /dev/null

echo "Скрипт выполнен"
