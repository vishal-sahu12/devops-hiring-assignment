#!/bin/bash
set -e

# Skip if kubectl is already installed
if command -v kubectl &>/dev/null; then
  echo "kubectl is already installed: $(kubectl version --client --short 2>/dev/null || kubectl version --client)"
  exit 0
fi

# Download the latest release of kubectl
KUBECTL_VERSION=$(curl -L -s https://dl.k8s.io/release/stable.txt)
curl -LO "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/amd64/kubectl"

# Install kubectl
sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl
rm -f kubectl

# Verify installation
echo "Kubectl version:"
kubectl version --client

# Install bash completion for kubectl
if [ -d /etc/bash_completion.d ]; then
  kubectl completion bash | sudo tee /etc/bash_completion.d/kubectl > /dev/null
fi

# Set up aliases (only if not already present)
grep -q 'alias k=kubectl' ~/.bashrc 2>/dev/null || echo 'alias k=kubectl' >> ~/.bashrc
grep -q 'source <(kubectl completion bash)' ~/.bashrc 2>/dev/null || echo 'source <(kubectl completion bash)' >> ~/.bashrc
grep -q 'complete -F __start_kubectl k' ~/.bashrc 2>/dev/null || echo 'complete -F __start_kubectl k' >> ~/.bashrc

echo "Kubectl installed successfully"
