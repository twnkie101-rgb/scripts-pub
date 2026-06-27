#!/bin/bash

cat << 'EOF' >> /etc/sysctl.conf
fs.inotify.max_user_instances = 16384
fs.inotify.max_user_watches = 32768
fs.inotify.max_queued_events = 262144
fs.file-max = 500000
EOF

sysctl -p

apt-get install sudo conntrack-tools socat podman unzip python3 python3-module-yaml python3-modules-sqlite3 postgresql15-server postgresql15-contrib kubernetes-kubeadm kubernetes-kubelet kubernetes-crio cri-tools -y

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


