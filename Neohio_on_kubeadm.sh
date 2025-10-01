#!/bin/bash
# =============================================================================
# Script Name   : k8s-nephio-setup.sh
# Author        : Rehan Fazal
# Date          : 2025-10-01
# Description   : 
#   This script automates the deployment of Nephio on a real kubeadm-based
#   Kubernetes cluster running on baremetal. 
#   Unlike Kind (Docker container-based clusters), this setup creates
#   a genuine Kubernetes control plane with optional worker nodes.
#
#   Features:
#     - System preparation (swap off, kernel modules, sysctl params)
#     - Container runtime installation (containerd and Docker)
#     - Kubernetes components installation (kubeadm, kubelet, kubectl)
#     - Flannel CNI setup
#     - Local-path storage provisioner installation
#     - Metal3 Baremetal Operator deployment
#     - Nephio bootstrap installation
#
# Usage:
#   Run this script on a fresh Ubuntu system as a user with sudo privileges:
#     bash k8s-nephio-setup.sh
#
# Note:
#   Ensure that the inotify parameters are set correctly:
#     fs.inotify.max_user_watches=524288
#     fs.inotify.max_user_instances=512
#   to avoid WebUI pod crashes during deployment.
# =============================================================================
set -euo pipefail

LOG_FILE="$HOME/k8s-setup.log"
echo "Logging setup to $LOG_FILE"
exec > >(tee -a "$LOG_FILE") 2>&1

retry() {
    local n=1
    local max=5
    local delay=5
    while true; do
        "$@" && break || {
            if [[ $n -lt $max ]]; then
                ((n++))
                echo "Command failed. Attempt $n/$max:"
                sleep $delay;
            else
                echo "The command has failed after $n attempts."
                exit 1
            fi
        }
    done
}

install_if_missing() {
    for pkg in "$@"; do
        if ! dpkg -s $pkg >/dev/null 2>&1; then
            echo "Package $pkg not found. Installing..."
            sudo apt-get install -y $pkg
        else
            echo "Package $pkg is already installed."
        fi
    done
}

echo "=== Kubernetes Control Plane + Nephio Setup Started ==="

# Pre-requisite check
echo "=== Checking dependencies ==="
sudo apt-get update -y
install_if_missing apt-transport-https ca-certificates curl gpg iptables iproute2 wget lsb-release

# 1. System Basics
echo "=== 1. Updating system ==="
sudo apt-get upgrade -y

# 2. Disable Swap
echo "=== 2. Disabling swap ==="
sudo swapoff -a
# sudo sed -i '/ swap / s/^\(.*\)$/#\1/g' /etc/fstab
sudo sed -i '/\bswap\b/ s/^/#/' /etc/fstab
sudo swapon --show

# 3. Load Required Kernel Modules
echo "=== 3. Loading kernel modules ==="
cat <<EOF | sudo tee /etc/modules-load.d/k8s.conf
overlay
br_netfilter
EOF
sudo modprobe overlay
sudo modprobe br_netfilter

# 4. Set Sysctl Parameters 
echo "=== 4. Setting sysctl params ==="
cat <<EOF | sudo tee /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-ip6tables = 1
net.bridge.bridge-nf-call-iptables = 1
net.ipv4.ip_forward = 1
EOF
sudo sysctl --system
sudo sysctl -w net.ipv4.ip_forward=1

# 5. Install Container Runtime (containerd)
echo "=== 5. Installing containerd ==="
sudo apt-get install -y containerd
sudo mkdir -p /etc/containerd
sudo containerd config default | sudo tee /etc/containerd/config.toml
sudo sed -i 's/SystemdCgroup = false/SystemdCgroup = true/g' /etc/containerd/config.toml

retry sudo systemctl restart containerd
sudo systemctl enable containerd
containerd config dump | grep SystemdCgroup

# 6. Add Kubernetes Repository
echo "=== 6. Adding Kubernetes repository ==="
sudo mkdir -p /etc/apt/keyrings
curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.34/deb/Release.key | sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
echo "deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.34/deb/ /" | sudo tee /etc/apt/sources.list.d/kubernetes.list

# 7. Install kubelet, kubeadm, kubectl
echo "=== 7. Installing kubelet, kubeadm, kubectl ==="
sudo apt-get update
sudo apt-get install -y kubelet kubeadm kubectl
sudo apt-mark hold kubelet kubeadm kubectl
sudo systemctl enable --now kubelet

# Configure kubelet to use systemd cgroup driver
echo "=== Configuring kubelet cgroup driver ==="
sudo mkdir -p /etc/systemd/system/kubelet.service.d
sudo tee /etc/systemd/system/kubelet.service.d/20-extra-args.conf <<EOF
[Service]
Environment="KUBELET_EXTRA_ARGS=--cgroup-driver=systemd"
EOF
sudo systemctl daemon-reload
retry sudo systemctl restart kubelet
# 8. Detect internal IP automatically
echo "=== 8. Detecting internal IP ==="
INTERNAL_IP=$(hostname -I | awk '{print $1}')
echo "Detected internal IP: $INTERNAL_IP"

# 9. Initialize Kubernetes Control Plane
echo "=== 9. Initializing Kubernetes control plane ==="
retry sudo kubeadm init --apiserver-advertise-address=$INTERNAL_IP --pod-network-cidr=10.244.0.0/16 | tee kubeadm-init.out

# Save kubeadm join command for worker nodes
grep "kubeadm join" kubeadm-init.out > kubeadm-join-command.sh
chmod +x kubeadm-join-command.sh
echo "Kubeadm join command saved to kubeadm-join-command.sh"

# 10. Configure kubectl
echo "=== 10. Configuring kubectl ==="
mkdir -p $HOME/.kube
sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
sudo chown $(id -u):$(id -g) $HOME/.kube/config

# 11. Remove control-plane taint (for single-node cluster)
echo "=== 11. Removing control-plane taint for single-node setup ==="
kubectl taint nodes --all node-role.kubernetes.io/control-plane- || true

# 12. Deploy Flannel CNI
echo "=== 12. Deploying Flannel CNI ==="
retry kubectl apply -f https://raw.githubusercontent.com/flannel-io/flannel/master/Documentation/kube-flannel.yml
# 13. Wait for Flannel pods to be Running
echo "=== 13. Waiting for Flannel pods to be Running ==="
sleep 30
until kubectl get pods -n kube-flannel --no-headers 2>/dev/null | grep -q "Running"; do
  echo "Waiting for Flannel pods to start..."
  sleep 10
done

kubectl wait --for=condition=ready pod -l app=flannel -n kube-flannel --timeout=300s


# 14. Install Storage Provisioner (Required for Nephio)
echo "=== 14. Installing local-path storage provisioner ==="
STORAGE_URL="https://raw.githubusercontent.com/rancher/local-path-provisioner/v0.0.24/deploy/local-path-storage.yaml"
retry kubectl apply -f $STORAGE_URL

# Wait for deployment rollout instead of pods
echo "Waiting for local-path-provisioner deployment to be ready..."
kubectl rollout status deployment/local-path-provisioner -n local-path-storage --timeout=300s

# Patch storageclass as default
echo "Patching local-path storageclass as default..."
kubectl patch storageclass local-path -p '{"metadata": {"annotations":{"storageclass.kubernetes.io/is-default-class":"true"}}}'



# 15. Install Docker (Latest Stable)
echo "=== 15. Installing latest Docker ==="
if ! command -v docker &> /dev/null; then
    echo "Docker not found. Installing latest Docker..."
    export DEBIAN_FRONTEND=noninteractive

    retry sudo apt-get update
    sudo apt-get remove -y docker docker-engine docker.io containerd runc || true

    install_if_missing ca-certificates curl gnupg lsb-release

    sudo mkdir -p /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg

    echo \
    "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
    $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

    retry sudo apt-get update
    retry sudo apt-get install -y -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" \
        docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

    sudo usermod -aG docker $USER || true
    echo "✅ Docker installed successfully. Log out and log back in to apply group changes."
else
    echo "Docker is already installed: $(docker --version)"
fi


# 16. Enable kubectl bash completion
echo "=== 16. Setting up kubectl completion ==="
echo "source <(kubectl completion bash)" >> ~/.bashrc
kubectl completion bash | sudo tee /etc/bash_completion.d/kubectl > /dev/null
# 17. Final verification
echo "=== 17. Final verification ==="
echo "Waiting for all system pods to be ready..."
kubectl wait --for=condition=ready pod --all -n kube-system --timeout=300s
kubectl wait --for=condition=ready pod --all -n kube-flannel --timeout=300s
kubectl wait --for=condition=ready pod --all -n local-path-storage --timeout=300s

# 18. Install Metal3 Baremetal Operator v0.11.0 (Required for Nephio CAPM3)
echo "=== 18. Installing Metal3 Baremetal Operator v0.11.0 ==="

# Retry function (if not already defined)
retry() {
  local n=0
  local max=5
  local delay=5
  until "$@"; do
    n=$((n+1))
    if [ $n -lt $max ]; then
      echo "Command failed. Retry $n/$max in $delay seconds..."
      sleep $delay
    else
      echo "The command has failed after $n attempts."
      return 1
    fi
  done
}

# Install all CRDs
echo "Installing Metal3 CRDs..."
retry kubectl apply -f https://raw.githubusercontent.com/metal3-io/baremetal-operator/v0.11.0/config/base/crds/bases/metal3.io_baremetalhosts.yaml
retry kubectl apply -f https://raw.githubusercontent.com/metal3-io/baremetal-operator/v0.11.0/config/base/crds/bases/metal3.io_firmwareschemas.yaml
retry kubectl apply -f https://raw.githubusercontent.com/metal3-io/baremetal-operator/v0.11.0/config/base/crds/bases/metal3.io_hostfirmwaresettings.yaml

# Create the required namespace
echo "Creating namespace baremetal-operator-system if not exists..."
kubectl get ns baremetal-operator-system >/dev/null 2>&1 || kubectl create namespace baremetal-operator-system

# Install cert-manager (required for operator)
echo "Installing cert-manager..."
retry kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.16.2/cert-manager.yaml

# Wait for cert-manager pods to be ready
echo "Waiting for cert-manager to be ready..."
kubectl wait --for=condition=Ready --timeout=300s pods -n cert-manager --all

# Install the pre-rendered Baremetal Operator manifest
echo "Installing Baremetal Operator..."
retry kubectl apply -f https://raw.githubusercontent.com/metal3-io/baremetal-operator/v0.11.0/config/render/capm3.yaml

# Wait for operator to be ready
echo "Waiting for baremetal-operator to be ready..."
kubectl wait --for=condition=available --timeout=300s \
  deployment/baremetal-operator-controller-manager \
  -n baremetal-operator-system 2>/dev/null || \
  kubectl rollout status deployment/baremetal-operator-controller-manager \
  -n baremetal-operator-system --timeout=300s

# Verify installation
echo "Verifying Metal3 Baremetal Operator installation..."
echo "CRDs installed:"
kubectl get crds | grep metal3.io
kubectl get pods -n baremetal-operator-system



echo ""
echo "Operator pods:"
kubectl get pods -n baremetal-operator-system

echo ""
echo "Metal3 Baremetal Operator v0.11.0 installation complete!"

echo ""
echo "=== Final Status Check ==="
kubectl get nodes -o wide
echo ""
kubectl get pods -A
echo ""
kubectl get storageclass
echo ""
docker --version

echo ""
echo "=== Kubernetes Control Plane Setup Completed Successfully! ==="
echo "=== Ready for Nephio Installation! ==="
echo ""
echo "IMPORTANT: Log out and log back in to apply Docker group membership"
echo ""
echo "Then run the following command to install Nephio:"
#paste the nephio install command here
echo ""
echo "IMPORTANT: Log out and log back in to apply Docker group membership"
echo ""
echo "Installing Nephio..."
echo ""

wget -O - https://raw.githubusercontent.com/nephio-project/test-infra/main/e2e/provision/init.sh | \
sudo NEPHIO_DEBUG=false \
NEPHIO_BRANCH=main \
NEPHIO_USER=$(whoami) \
DOCKERHUB_USERNAME=rehanfazal47 \
DOCKERHUB_TOKEN=819734qwertyuiop \
K8S_CONTEXT=$(kubectl config current-context) \
bash

echo ""
echo "Nephio installation complete. All logs saved in $LOG_FILE"
