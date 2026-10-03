#!/bin/bash
# Runs once as root on first boot. Log: /var/log/cloud-init-output.log
set -euxo pipefail

export DEBIAN_FRONTEND=noninteractive
apt-get update -y
apt-get install -y ca-certificates curl git unzip openjdk-17-jdk maven docker.io

# Docker
systemctl enable --now docker
usermod -aG docker ubuntu

# Kubernetes (k3s single node). kubeconfig readable by the ubuntu user.
curl -sfL https://get.k3s.io | INSTALL_K3S_EXEC="--write-kubeconfig-mode 644" sh -

# Helm
curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash

# Make kubectl/helm work for the ubuntu user
echo 'export KUBECONFIG=/etc/rancher/k3s/k3s.yaml' >> /home/ubuntu/.bashrc

touch /home/ubuntu/BOOTSTRAP_DONE
