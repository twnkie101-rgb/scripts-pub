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

read -p "Введите пароль пользователя postgres: " postgres_pass

cat << 'EOF' >> /etc/sysctl.conf
fs.inotify.max_user_instances = 16384
fs.inotify.max_user_watches = 32768
fs.inotify.max_queued_events = 262144
fs.file-max = 500000
EOF

sysctl -p

apt-get update

apt-get install conntrack-tools socat podman unzip python-modules-sqlite3 python-modules-json python-modules-distutils postgresql15-server postgresql15 postgresql15-contrib samba samba-client -y

rm -rf /etc/cni/net.d/*

su - postgres -s /bin/bash -c "initdb"

systemctl restart postgresql

if ! grep -q '^openssl_conf[[:space:]]*=[[:space:]]*default_conf$' "$OPENSSL_CONF"; then
    sed -i '/^oid_section[[:space:]]*=.*new_oids/a\
\
# System default\
openssl_conf = default_conf
' "$OPENSSL_CONF"
fi

if ! grep -q '^\[default_conf\]' "$OPENSSL_CONF"; then
cat <<'EOF' >> "$OPENSSL_CONF"

[default_conf]
ssl_conf = ssl_sect

[ssl_sect]
system_default = system_default_sect

[system_default_sect]
MinProtocol = TLSv1.2
CipherString = DEFAULT:@SECLEVEL=1
EOF
fi

echo "Вариант основго файла конфигурации для сервера с 10ГБ ОЗУ выделенной под БД"

cat << 'EOF' > /var/lib/pgsql/data/postgresql.conf
# --- Подключение, сеть и порты ---
listen_addresses = '*'
port = 5432
max_connections = 250
password_encryption = 'scram-sha-256'

# --- Настройки TCP Keepalives (для стабильности долгих сессий) ---
tcp_keepalives_idle = 60              # TCP_KEEPIDLE, в секундах
tcp_keepalives_interval = 20          # TCP_KEEPINTVL, в секундах
tcp_keepalives_count = 2              # TCP_KEEPCNT

# --- Распределение памяти и ресурсы ---
shared_buffers = '3GB'                # 25% от RAM для БД
effective_cache_size = '7GB'          # 50% от RAM для БД. Ориентир общего кэша для планировщика
work_mem = '32MB'                     # Память на одну операцию сортировки/соединения. 32М рекомендовано для DM
maintenance_work_mem = '1GB'        # Память для индексов и VACUUM
temp_buffers = '8MB'                  # Память под временные таблицы
huge_pages = try                      # Попытка использовать Huge Pages ядра Linux
max_locks_per_transaction = 512

# --- WAL (Журнал предзаписи) ---
wal_buffers = '16MB'
min_wal_size = '2GB'
max_wal_size = '16GB'

# --- Логирование и сбор статистики ---
log_min_messages = warning
logging_collector = on
log_connections = on
log_disconnections = on
log_checkpoints = on
log_destination = 'stderr'
log_directory = 'pg_log'
log_filename = 'postgresql-%Y-%m-%d_%H%M%S.log'
log_rotation_age = '1d'
log_rotation_size = '100MB'
log_min_duration_statement = 120000    # Логировать запросы тяжелее 2 минут (120000 мс)
log_autovacuum_min_duration = 30000    # Логировать автовакуум, если он шел дольше 30 сек
shared_preload_libraries = 'pg_stat_statements'
track_io_timing = on
track_activity_query_size = 32768      # Размер буфера для текста запросов (требуется перезапуск)

# --- Автовакуум (Очистка и сбор статистики таблиц) ---
autovacuum_max_workers = 5
autovacuum_naptime = 20
autovacuum_freeze_max_age = 200000000

# --- Совместимость, врмененные зоны и локализация ---
lc_messages = 'en_US.UTF-8'           # Системные ошибки пишем на английском
constraint_exclusion = off
standard_conforming_strings = on
log_timezone = 'UTC'
datestyle = 'iso, dmy'
timezone = 'UTC'
lc_monetary = 'ru_RU.UTF-8'                     
lc_numeric = 'ru_RU.UTF-8'
lc_time = 'ru_RU.UTF-8'
default_text_search_config = 'pg_catalog.russian'

# --- Системное ---
dynamic_shared_memory_type = posix
log_file_mode = 0600
EOF

cat << EOF > /var/lib/pgsql/data/pg_hba.conf
# TYPE  DATABASE        USER            ADDRESS                 METHOD

# "local" is for Unix domain socket connections only
local   all             all                                     trust
# IPv4 local connections:
host	all		all		127.0.0.1/32		trust
# IPv6 local connections:
host	all		all		::1/128			trust
# Allow replication connections from localhost, by a user with the
# replication privilege.
#local   replication     all                                     trust
#host    replication     all             127.0.0.1/32            trust
#host    replication     all             ::1/128                 trust
host	all		all		0.0.0.0/0		md5
EOF

systemctl daemon-reload
systemctl enable --now postgresql
systemctl restart postgresql

su - postgres -s /bin/bash -c "psql" <<< "ALTER USER postgres PASSWORD '${postgres_pass}';"

echo "Скрипт закончил работу"
