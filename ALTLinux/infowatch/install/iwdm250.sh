#!/bin/bash

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

apt-get install sudo conntrack-tools socat podman unzip python3 python3-module-yaml python3-modules-sqlite3 postgresql15-server postgresql15-contrib kubernetes1.31-kubeadm kubernetes1.31-kubelet kubernetes1.31-crio cri-tools1.31 -y

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

systemctl enable --now crio kubelet

unset http_proxy
unset https_proxy

cat << EOF > init.yml
apiVersion: kubeadm.k8s.io/v1beta4
bootstrapTokens:
- groups:
  - system:bootstrappers:kubeadm:default-node-tokenttl: "0s"
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

sed -i '/ready/i \ \ \ \ \ \ \ \ rewrite stop {\n\
   name substring iwplatform.local cluster.local answer
   auto\n\        }' coredns.yaml

sed -i 's/kubernetes/kubernetes cluster.local/' coredns.yaml
