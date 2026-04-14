#!/bin/bash
set -e

KIND_VERSION="v0.27.0"

# Install additional tools for debugging (idempotent via apt-get install -y)
sudo apt-get update
sudo apt-get install -y \
    jq \
    net-tools \
    iputils-ping \
    dnsutils \
    netcat-openbsd \
    tcpdump \
    traceroute \
    curl \
    wget \
    vim \
    htop \
    strace \
    openssl

# Skip KIND install if already at correct version
if command -v kind &>/dev/null; then
  INSTALLED_VERSION=$(kind version | grep -oP 'v[\d.]+' | head -1)
  if [ "$INSTALLED_VERSION" = "$KIND_VERSION" ]; then
    echo "KIND ${KIND_VERSION} is already installed, skipping"
    exit 0
  fi
  echo "Upgrading KIND from ${INSTALLED_VERSION} to ${KIND_VERSION}"
fi

# Install KIND (Kubernetes in Docker)
curl -Lo ./kind "https://kind.sigs.k8s.io/dl/${KIND_VERSION}/kind-linux-amd64"
chmod +x ./kind
sudo mv ./kind /usr/local/bin/kind

# Verify KIND installation
echo "KIND version:"
kind version

echo "KIND environment setup completed successfully"
