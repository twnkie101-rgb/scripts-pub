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

read -p "Введите пароль пользователя postgres: " postgres_pass

apt-get update
apt-get -y install postgresql15-contrib pgagent -y

mkdir /etc/systemd/system/postgresql.service.d/
cat << 'EOF' > /etc/systemd/system/postgresql.service.d/override.conf
[Service]
Environment=PGDATA=/u01/postgres
Environment=PGPORT=5433
LimitNOFILE=65536
LimitMEMLOCK=infinity
EOF

systemctl daemon-reload

mkdir -p /u01/postgres
chown postgres:postgres /u01/postgres
export PGSETUP_INITDB_OPTIONS=" --encoding=UTF8"
su - postgres -s /bin/bash -c "initdb --encoding=UTF8 --locale=en_US.UTF-8 -D /u01/postgres"
mkdir -p /u01/postgres/tmp
chown postgres:postgres /u01/postgres/tmp
mkdir -p /u02/pgdata
chown postgres:postgres /u02/pgdata
mkdir -p /u02/pgdata1
chown postgres:postgres /u02/pgdata1
mkdir -p /u02/arch
chown postgres:postgres /u02/arch

echo "Вариант дополнительного файла конфигурации для сервера с 16ГБ ОЗУ выделенной под БД"

cat << 'EOF' > /u01/postgres/iwtm-postgres.conf
# --- Подключение, сеть и порты ---
listen_addresses = '*'
port = 5433
max_connections = 1000            # (требуется перезапуск)

# --- Настройки TCP Keepalives (для стабильности долгих сессий) ---
tcp_keepalives_idle = 60            # TCP_KEEPIDLE, в секундах
tcp_keepalives_interval = 20        # TCP_KEEPINTVL, в секундах
tcp_keepalives_count = 2             # TCP_KEEPCNT

# --- Распределение памяти и ресурсы ---
shared_buffers = '5GB'              # 25% от RAM для БД
effective_cache_size = '15GB'       # 75% от RAM для БД. Ориентир общего кэша для планировщика
work_mem = '10MB'                   # Память на одну операцию сортировки/соединения
maintenance_work_mem = '1GB'        # Память для индексов и VACUUM
temp_buffers = '16MB'               # Память под временные таблицы
huge_pages = try                    # Попытка использовать Huge Pages ядра Linux
max_locks_per_transaction = 512

# --- WAL (Журнал предзаписи) ---
wal_buffers = '16MB'
min_wal_size = '2GB'
max_wal_size = '16GB'

# --- Логирование и сбор статистики ---
logging_collector = on
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

# --- Совместимость и локализация ---
lc_messages = 'en_US.UTF-8'        # Системные ошибки пишем на английском
constraint_exclusion = off
standard_conforming_strings = on

# --- Пути (закомментировано по умолчанию) ---
# stats_temp_directory = '/u01/postgres/pg_stat_tmp'
EOF

chown postgres:postgres /u01/postgres/iwtm-postgres.conf
chmod 600 /u01/postgres/iwtm-postgres.conf

echo "include = 'iwtm-postgres.conf'" >> /u01/postgres/postgresql.conf

sed -i "s|local[[:space:]]*all[[:space:]]*all[[:space:]]*peer|local\tall\t\tall\t\t\t\t\ttrust|" /u01/postgres/pg_hba.conf

sed -i "s|host[[:space:]]*all[[:space:]]*all[[:space:]]*127.0.0.1/32[[:space:]]*ident|host\tall\t\tall\t\t127.0.0.1/32\t\ttrust|" /u01/postgres/pg_hba.conf

sed -i "s|host[[:space:]]*all[[:space:]]*all[[:space:]]*::1/128[[:space:]]*ident|host\tall\t\tall\t\t::1/128\t\ttrust|" /u01/postgres/pg_hba.conf

sed -i '/replication/s/^/# /' /u01/postgres/pg_hba.conf

# Подключение к БД только локальное?
echo "# Enable not local access" >> /u01/postgres/pg_hba.conf
echo -e "host\tpostgres\tall\t\t0.0.0.0/0\t\tmd5" >> /u01/postgres/pg_hba.conf

systemctl enable postgresql.service
systemctl start postgresql.service

su - postgres -s /bin/bash -c "psql -p 5433" <<< "ALTER USER postgres PASSWORD '${postgres_pass}';"

su - postgres -s /bin/bash -c "psql -p 5433 -d postgres" << 'EOF'
CREATE EXTENSION IF NOT EXISTS adminpack;
CREATE EXTENSION IF NOT EXISTS dblink;
CREATE EXTENSION IF NOT EXISTS lo;
CREATE EXTENSION IF NOT EXISTS xml2;
CREATE EXTENSION IF NOT EXISTS tablefunc;
CREATE EXTENSION IF NOT EXISTS intarray;
CREATE EXTENSION IF NOT EXISTS file_fdw;
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS pgcrypto;
CREATE EXTENSION IF NOT EXISTS pgrowlocks;
CREATE EXTENSION IF NOT EXISTS autoinc;
CREATE EXTENSION IF NOT EXISTS hstore;
CREATE EXTENSION IF NOT EXISTS pg_stat_statements;
CREATE EXTENSION IF NOT EXISTS pg_buffercache;
CREATE EXTENSION IF NOT EXISTS pgagent;
EOF

groupadd -f -r pgagent
useradd -g pgagent -r -m -s /bin/bash -c "pgAgent Job Schedule" pgagent

mkdir -p /home/pgagent
cat << EOF > /home/pgagent/.pgpass
*:5433:postgres:postgres:${postgres_pass}
EOF

cat << EOF > /var/lib/pgsql/.pgpass
*:5433:postgres:postgres:${postgres_pass}
EOF

chmod 0600 /var/lib/pgsql/.pgpass
chown postgres:postgres /var/lib/pgsql/.pgpass

chmod 0600 /home/pgagent/.pgpass
chown -R pgagent:pgagent /home/pgagent

cat << 'EOF' > /etc/sudoers.d/pgagent
pgagent ALL = (postgres) NOPASSWD: ALL
Defaults:pgagent !requiretty

EOF

chmod 440 /etc/sudoers.d/pgagent
chown root:root /etc/sudoers.d/pgagent

mkdir -p /etc/pgagent
cat << 'EOF' > /etc/pgagent/pgagent.conf
DBNAME=postgres
DBUSER=postgres
DBHOST=127.0.0.1
DBPORT=5433
LOGFILE=/var/log/pgagent.log
EOF

touch /var/log/pgagent.log && chown pgagent:pgagent /var/log/pgagent.log

mkdir -p /usr/lib/systemd/system

cat << 'EOF' > /etc/systemd/system/pgagent.service
[Unit]
Description=PgAgent for PostgreSQL
After=syslog.target
After=network.target
After=postgresql.service

[Service]
Type=forking
User=pgagent
Group=pgagent
# Location of the configuration file
EnvironmentFile=/etc/pgagent/pgagent.conf
# Where to send early-startup messages from the server (before the logging
# options of pgagent.conf take effect)
# This is normally controlled by the global default set by systemd
# StandardOutput=syslog
# Disable OOM kill on the postmaster
OOMScoreAdjust=-100
ExecStart=/usr/bin/pgagent -l 0 -s ${LOGFILE} hostaddr=${DBHOST} dbname=${DBNAME} user=${DBUSER} port=${DBPORT}
KillMode=mixed
KillSignal=SIGINT
Restart=on-failure
# Give a reasonable amount of time for the server to start up/shut down
TimeoutSec=300
[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable pgagent
systemctl start pgagent

# Если требуется запретить траст
#sed -i "s/^local[[:space:]]\+all[[:space:]]\+all[[:space:]]\+trust/local\tall\t\tall\t\t\t\t\tmd5/" /u01/postgres/pg_hba.conf
#
#sed -i "s/^host[[:space:]]\+all[[:space:]]\+all[[:space:]]\+127.0.0.1\/32[[:space:]]\+trust/host\tall\t\tall\t\t127.0.0.1\/32\t\tmd5/" /u01/postgres/pg_hba.conf
#
#sed -i "s/^host[[:space:]]\+all[[:space:]]\+all[[:space:]]\+::1\/128[[:space:]]\+trust/host\tall\t\tall\t\t::1\/128\t\t\tmd5/" /u01/postgres/pg_hba.conf
#
#systemctl restart postgresql
#systemctl restart pgagent
echo "Скрипт завершил работу"
