#!/bin/bash

if [ "$EUID" -ne 0 ]; then
    echo "Ошибка: Этот скрипт нужно запускать от имени root!"
    exit 1
fi

read -p "Введите пароль пользователя postgres: " postgres_pass

cat << 'EOF' > /etc/apt/sources.list.d/altsp.list
# ALT Certified 10
#rpm [cert8] ftp://update.altsp.su/pub/distributions/ALTLinux c10f2/branch/x86_64 classic gostcrypto
#rpm [cert8] ftp://update.altsp.su/pub/distributions/ALTLinux c10f2/branch/x86_64-i586 classic
#rpm [cert8] ftp://update.altsp.su/pub/distributions/ALTLinux c10f2/branch/noarch classic

rpm [cert8] http://update.altsp.su/pub/distributions/ALTLinux c10f2/branch/x86_64 classic gostcrypto
rpm [cert8] http://update.altsp.su/pub/distributions/ALTLinux c10f2/branch/x86_64-i586 classic
rpm [cert8] http://update.altsp.su/pub/distributions/ALTLinux c10f2/branch/noarch classic
EOF

cat << 'EOF' >> /etc/sysctl.conf
fs.inotify.max_user_instances = 16384
fs.inotify.max_user_watches = 32768
fs.inotify.max_queued_events = 262144
fs.file-max = 500000
EOF

sysctl -p

apt-get update

apt-get install sudo conntrack-tools socat podman unzip runc python3 python3-module-yaml python3-modules-sqlite3 postgresql15-server postgresql15-contrib postgresql15-python kubernetes1.31-kubeadm kubernetes1.31-kubelet kubernetes1.31-crio cri-tools1.31 libbacktrace libpython3 libossp-uuid16 libunwind python-modules-json python-modules-distutils python-modules-sqlite3 -y

rm -rf /etc/cni/net.d/*

su - postgres -s /bin/bash -c "initdb"

podman pull registry.altlinux.org/k8s-c10f2/kube-apiserver:v1.31.1
podman pull registry.altlinux.org/k8s-c10f2/kube-controller-manager:v1.31.1
podman pull registry.altlinux.org/k8s-c10f2/kube-scheduler:v1.31.1
podman pull registry.altlinux.org/k8s-c10f2/kube-proxy:v1.31.1
podman pull registry.altlinux.org/k8s-c10f2/pause:3.10
podman pull registry.altlinux.org/k8s-c10f2/etcd:3.5.15-0
podman pull registry.altlinux.org/k8s-c10f2/coredns:v1.11.3
podman pull registry.altlinux.org/k8s-c10f2/flannel:v0.25.7
podman pull registry.altlinux.org/k8s-c10f2/flannel-cni-plugin:v1.4.0-flannel1

podman tag registry.altlinux.org/k8s-c10f2/pause:3.10 registry.k8s.io/pause:3.10
podman tag registry.altlinux.org/k8s-c10f2/etcd:3.5.15-0 registry.altlinux.org/k8s-c10f2/etcd:3.5.24-0

swapoff -a

cat << EOF > /etc/crio/crio.conf
[crio]
root = "/var/lib/containers/storage"
runroot = "/var/run/containers/storage"
storage_option = [
        "overlay.override_kernel_check=1",
]
log_level = "info"

[crio.api]
listen = "/var/run/crio/crio.sock"

[crio.runtime]
conmon = "/usr/bin/conmon"
cgroup_manager = "systemd"
default_runtime = "runc"

[crio.runtime.runtimes.runc]
runtime_path = "/usr/bin/runc"
runtime_type = "oci"

[crio.image]
pause_image = "registry.k8s.io/pause:3.10"
storage_driver = "overlay"

[crio.network]
network_dir = "/etc/cni/net.d/"
plugin_dirs = ["/usr/libexec/cni", "/opt/cni/bin"]

[crio.metrics]

[crio.tracing]

[crio.nri]

[crio.stats]

EOF

systemctl enable --now crio kubelet

unset http_proxy
unset https_proxy

cat << EOF > init.yml
apiVersion: kubeadm.k8s.io/v1beta4
bootstrapTokens:
- groups:
  - system:bootstrappers:kubeadm:default-node-token
  ttl: "0s"
  usages:
  - signing
  - authentication
kind: InitConfiguration
localAPIEndpoint:
  advertiseAddress: 0.0.0.0
  bindPort: 6443
nodeRegistration:
  criSocket: unix:///run/crio/crio.sock
  name: ${HOSTNAME}
  ignorePreflightErrors:
    - Swap
  taints: null
timeouts:
  controlPlaneComponentHealthCheck: 4m0s
  discovery: 5m0s
  etcdAPICall: 8m0s
  kubeletHealthCheck: 4m0s
  kubernetesAPICall: 4m0s
  tlsBootstrap: 5m0s
  upgradeManifests: 5m0s
---
apiVersion: kubeadm.k8s.io/v1beta4
kind: ClusterConfiguration
certificatesDir: /etc/kubernetes/pki
clusterName: iwplatform
apiServer:
  extraArgs:
    - name: service-node-port-range
      value: "80-65535"
    - name: enable-admission-plugins
      value: "NodeRestriction"
    - name: tls-min-version
      value: "VersionTLS13"
    - name: tls-cipher-suites
      value: "TLS_ECDHE_RSA_WITH_AES_128_GCM_SHA256,TLS_ECDHE_RSA_WITH_AES_256_GCM_SHA384"
    - name: profiling
      value: "false"
    - name: audit-log-path
      value: "/var/log/kube-audit/audit.log"
    - name: audit-log-maxage
      value: "30"
    - name: audit-log-maxbackup
      value: "10"
    - name: audit-log-maxsize
      value: "100"
    - name: audit-log-maxsize
      value: "100"
  extraVolumes:
    - name: audit-log
      hostPath: /var/log/kube-audit
      mountPath: /var/log/kube-audit
      pathType: DirectoryOrCreate
controllerManager:
  extraArgs:
    - name: leader-elect
      value: "false"
    - name: tls-min-version
      value: "VersionTLS13"
    - name: profiling
      value: "false"
    - name: terminated-pod-gc-threshold
      value: "100"
etcd:
  local:
    dataDir: /var/lib/etcd
    extraArgs:
      - name: cipher-suites
        value: "TLS_ECDHE_RSA_WITH_AES_128_GCM_SHA256,TLS_ECDHE_RSA_WITH_AES_256_GCM_SHA384"
imageRepository: registry.altlinux.org/k8s-c10f2
kubernetesVersion: v1.31.1
networking:
  dnsDomain: iwplatform.local
  serviceSubnet: 10.96.0.0/12
  podSubnet: 10.244.0.0/16
scheduler:
    extraArgs:
      - name: leader-elect
        value: "false"
      - name: profiling
        value: "false"
---
apiVersion: kubelet.config.k8s.io/v1beta1
kind: KubeletConfiguration
evictionHard:
    memory.available: "100Mi"
    nodefs.available: "3Gi"
    imagefs.available: "3Gi"
failSwapOn: false
containerLogMaxSize: "200Mi"
containerLogMaxFiles: 5
tlsMinVersion: "VersionTLS13"
imageGCHighThresholdPercent: 100
imageGCLowThresholdPercent: 99
EOF

kubeadm init --config init.yml

mkdir -p $HOME/.kube
sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
sudo chown $(id -u):$(id -g) $HOME/.kube/config

cat << EOF > kube-flannel.yml
apiVersion: v1
kind: Namespace
metadata:
  labels:
    k8s-app: flannel
    pod-security.kubernetes.io/enforce: privileged
  name: kube-flannel
---
apiVersion: v1
kind: ServiceAccount
metadata:
  labels:
    k8s-app: flannel
  name: flannel
  namespace: kube-flannel
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  labels:
    k8s-app: flannel
  name: flannel
rules:
- apiGroups:
  - ""
  resources:
  - pods
  verbs:
  - get
- apiGroups:
  - ""
  resources:
  - nodes
  verbs:
  - get
  - list
  - watch
- apiGroups:
  - ""
  resources:
  - nodes/status
  verbs:
  - patch
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  labels:
    k8s-app: flannel
  name: flannel
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: flannel
subjects:
- kind: ServiceAccount
  name: flannel
  namespace: kube-flannel
---
apiVersion: v1
data:
  cni-conf.json: |
    {
      "name": "cbr0",
      "cniVersion": "0.3.1",
      "plugins": [
        {
          "type": "flannel",
          "delegate": {
            "hairpinMode": true,
            "isDefaultGateway": true
          }
        },
        {
          "type": "portmap",
          "capabilities": {
            "portMappings": true
          }
        }
      ]
    }
  net-conf.json: |
    {
      "Network": "10.244.0.0/16",
      "EnableNFTables": false,
      "Backend": {
        "Type": "vxlan"
      }
    }
kind: ConfigMap
metadata:
  labels:
    app: flannel
    k8s-app: flannel
    tier: node
  name: kube-flannel-cfg
  namespace: kube-flannel
---
apiVersion: apps/v1
kind: DaemonSet
metadata:
  labels:
    app: flannel
    k8s-app: flannel
    tier: node
  name: kube-flannel-ds
  namespace: kube-flannel
spec:
  selector:
    matchLabels:
      app: flannel
      k8s-app: flannel
  template:
    metadata:
      labels:
        app: flannel
        k8s-app: flannel
        tier: node
    spec:
      affinity:
        nodeAffinity:
          requiredDuringSchedulingIgnoredDuringExecution:
            nodeSelectorTerms:
            - matchExpressions:
              - key: kubernetes.io/os
                operator: In
                values:
                - linux
      containers:
      - args:
        - --ip-masq
        - --kube-subnet-mgr
        command:
        - /opt/bin/flanneld
        env:
        - name: POD_NAME
          valueFrom:
            fieldRef:
              fieldPath: metadata.name
        - name: POD_NAMESPACE
          valueFrom:
            fieldRef:
              fieldPath: metadata.namespace
        - name: EVENT_QUEUE_DEPTH
          value: "5000"
        - name: CONT_WHEN_CACHE_NOT_READY
          value: "false"
        image: registry.altlinux.org/k8s-c10f2/flannel:v0.25.7
        name: kube-flannel
        resources:
          requests:
            cpu: 100m
            memory: 50Mi
        securityContext:
          capabilities:
            add:
            - NET_ADMIN
            - NET_RAW
          privileged: false
        volumeMounts:
        - mountPath: /run/flannel
          name: run
        - mountPath: /etc/kube-flannel/
          name: flannel-cfg
        - mountPath: /run/xtables.lock
          name: xtables-lock
      hostNetwork: true
      initContainers:
      - args:
        - -f
        - /flannel
        - /opt/cni/bin/flannel
        command:
        - cp
        image: registry.altlinux.org/k8s-c10f2/flannel-cni-plugin:v1.4.0-flannel1
        name: install-cni-plugin
        volumeMounts:
        - mountPath: /opt/cni/bin
          name: cni-plugin
      - args:
        - -f
        - /etc/kube-flannel/cni-conf.json
        - /etc/cni/net.d/10-flannel.conflist
        command:
        - cp
        image: registry.altlinux.org/k8s-c10f2/flannel:v0.25.7
        name: install-cni
        volumeMounts:
        - mountPath: /etc/cni/net.d
          name: cni
        - mountPath: /etc/kube-flannel/
          name: flannel-cfg
      priorityClassName: system-node-critical
      serviceAccountName: flannel
      tolerations:
      - effect: NoSchedule
        operator: Exists
      volumes:
      - hostPath:
          path: /run/flannel
        name: run
      - hostPath:
          path: /opt/cni/bin
        name: cni-plugin
      - hostPath:
          path: /etc/cni/net.d
        name: cni
      - configMap:
          name: kube-flannel-cfg
        name: flannel-cfg
      - hostPath:
          path: /run/xtables.lock
          type: FileOrCreate
        name: xtables-lock
EOF

kubectl apply -f kube-flannel.yml

kubectl get cm -n kube-system coredns -o yaml > coredns.yaml

sed -i '/ready/i \ \ \ \ \ \ \ \ rewrite stop {\n\ \ \ \ \ \ \ \ \ \ \ name substring iwplatform.local cluster.local answer auto\n\ \ \ \ \ \ \ \ }' coredns.yaml

sed -i 's/kubernetes/kubernetes cluster.local/' coredns.yaml

kubectl replace -n kube-system -f coredns.yaml
kubectl -n kube-system rollout restart deployment coredns

kubectl taint nodes $(hostname) node-role.kubernetes.io/control-plane:NoSchedule-

kubectl get pods -A

export TMPDIR=/var/tmp
 
mkdir -p /var/lib/pgsql/data/backups_events
chown postgres:postgres /var/lib/pgsql/data/backups_events
chmod 700 /var/lib/pgsql/data/backups_events
mkdir -p /var/lib/pgsql/data/backups_facts
chown postgres:postgres /var/lib/pgsql/data/backups_facts
chmod 700 /var/lib/pgsql/data/backups_facts
mkdir -p /var/lib/pgsql/data/backups_ds
chown postgres:postgres /var/lib/pgsql/data/backups_ds
chmod 700 /var/lib/pgsql/data/backups_ds

echo "Вариант основго файла конфигурации для сервера с 8ГБ ОЗУ выделенной под БД"

cat << 'EOF' > /var/lib/pgsql/data/postgresql.conf
# --- Подключение, сеть и порты ---
listen_addresses = '*'
port = 5432
max_connections = 100
password_encryption = 'scram-sha-256'

# --- Настройки TCP Keepalives (для стабильности долгих сессий) ---
tcp_keepalives_idle = 60              # TCP_KEEPIDLE, в секундах
tcp_keepalives_interval = 20          # TCP_KEEPINTVL, в секундах
tcp_keepalives_count = 2              # TCP_KEEPCNT

# --- Распределение памяти и ресурсы ---
shared_buffers = '2GB'                # 25% от RAM для БД
effective_cache_size = '4GB'          # 50% от RAM для БД. Ориентир общего кэша для планировщика
work_mem = '4MB'                      # Память на одну операцию сортировки/соединения
maintenance_work_mem = '512MB'        # Память для индексов и VACUUM
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
log_timezone = 'UTC'	              # Важно чтобы это значение соответствовало lc_time
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
host	all		all		127.0.0.1/32		scram-sha-256
# IPv6 local connections:
host	all		all		::1/128			scram-sha-256
# Allow replication connections from localhost, by a user with the
# replication privilege.
#local   replication     all                                     trust
#host    replication     all             127.0.0.1/32            trust
#host    replication     all             ::1/128                 trust
host	all		all		all			md5
EOF

systemctl daemon-reload
systemctl enable --now postgresql
systemctl restart postgresql

su - postgres -s /bin/bash -c "psql" <<< "ALTER USER postgres PASSWORD '${postgres_pass}';"

cat << EOF > /etc/containers/containers.conf
[engine]
runtime = "runc"
EOF

echo "Скрипт закончил работу"
