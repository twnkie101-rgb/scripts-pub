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
fs.inotify.max_user_watches = 524288
fs.inotify.max_queued_events = 262144
fs.file-max = 500000
EOF

sysctl -p

apt-get update

apt-get install conntrack-tools socat podman unzip python-modules-sqlite3 python-modules-json python-modules-distutils postgresql15-server postgresql15 postgresql15-contrib samba samba-client -y

rm -rf /etc/cni/net.d/*

su - postgres -s /bin/bash -c "initdb"

systemctl restart postgresql

echo "Вариант основго файла конфигурации для сервера с 10ГБ ОЗУ выделенной под БД"

cat << 'EOF' > /var/lib/pgsql/data/postgresql.conf
# ==============================================================================
#                       POSTGRESQL CONFIGURATION FILE
#               Сервер: 8 vCPU / 10 GB RAM / SAS 10K RPM / 250 Connections
# ==============================================================================

# --- Подключение, сеть и порты ---
listen_addresses = '*'
port = 5432
max_connections = 250
password_encryption = 'scram-sha-256'

# --- Настройки TCP Keepalives ---
tcp_keepalives_idle = 60
tcp_keepalives_interval = 10
tcp_keepalives_count = 5

# --- Распределение памяти и ресурсы ---
shared_buffers = 2560MB
effective_cache_size = 7GB
work_mem = 8MB
maintenance_work_mem = 512MB
autovacuum_work_mem = 128MB
temp_buffers = 8MB
huge_pages = try
max_locks_per_transaction = 512

# --- Дисковая подсистема и планировщик ---
checkpoint_completion_target = 0.9
checkpoint_timeout = 15min
random_page_cost = 2.5
effective_io_concurrency = 4

# --- Автовакуум ---
autovacuum_max_workers = 3
autovacuum_naptime = 30s
autovacuum_vacuum_cost_limit = 400
autovacuum_vacuum_cost_delay = 10ms
autovacuum_freeze_max_age = 200000000

# --- Параллелизм запросов ---
max_worker_processes = 8
max_parallel_workers = 6
max_parallel_workers_per_gather = 2
max_parallel_maintenance_workers = 2

# --- WAL (Журнал предзаписи) ---
wal_buffers = 16MB
min_wal_size = 2GB
max_wal_size = 16GB

# --- Логирование ---
log_destination = 'stderr'
logging_collector = on
log_directory = 'pg_log'
log_filename = 'postgresql-%Y-%m-%d_%H%M%S.log'
log_file_mode = 0600
log_rotation_age = 1d
log_rotation_size = 100MB
log_truncate_on_rotation = on
log_min_messages = warning
log_connections = on
log_disconnections = on
log_checkpoints = on
log_min_duration_statement = 5000
log_autovacuum_min_duration = 10000
log_line_prefix = '%m [%p] %q%u@%d '

# --- Мониторинг и расширения ---
shared_preload_libraries = 'pg_stat_statements'
pg_stat_statements.track = top
pg_stat_statements.max = 10000
track_io_timing = on
track_activity_query_size = 32768

# --- Локализация и системное ---
datestyle = 'iso, dmy'
timezone = 'UTC'
log_timezone = 'UTC'
lc_messages = 'en_US.UTF-8'
lc_monetary = 'ru_RU.UTF-8'
lc_numeric = 'ru_RU.UTF-8'
lc_time = 'ru_RU.UTF-8'
default_text_search_config = 'pg_catalog.russian'
standard_conforming_strings = on
constraint_exclusion = partition
dynamic_shared_memory_type = posix
EOF

cat << EOF > /var/lib/pgsql/data/pg_hba.conf
# TYPE  DATABASE        USER            ADDRESS                 METHOD

# "local" is for Unix domain socket connections only
local   all             all                                     trust
# IPv4 local connections:
host	all		all		127.0.0.1/32		scram-sha-256
# IPv6 local connections:
host	all		all		::1/128			scram-sha-256
# Allow replication connections from localhost, by a user with the
# replication privilege.
#local   replication     all                                     trust
#host    replication     all             127.0.0.1/32            trust
#host    replication     all             ::1/128                 trust
host	all		all		0.0.0.0/0		scram-sha-256
EOF

systemctl daemon-reload
systemctl enable --now postgresql
systemctl restart postgresql

su - postgres -s /bin/bash -c "psql" <<< "ALTER USER postgres PASSWORD '${postgres_pass}';"
su - postgres -s /bin/bash -c "psql" <<< "CREATE EXTENSION pg_stat_statements;"

echo "Скрипт закончил работу"
