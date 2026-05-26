#!/bin/bash
set -euo pipefail

echo "Installing CNCF tools..."

# 4. Install CNCF Tooling
# Install kubectl
KUBECTL_VERSION=$(curl -L -s --connect-timeout 5 --retry 5 --retry-delay 2 https://dl.k8s.io/release/stable.txt)
curl -LO --connect-timeout 5 --retry 5 --retry-delay 2 "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/amd64/kubectl"
curl -LO --connect-timeout 5 --retry 5 --retry-delay 2 "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/amd64/kubectl.sha256"
echo "$(cat kubectl.sha256)  kubectl" | sha256sum -c -
install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl
rm kubectl kubectl.sha256

# Install k9s
K9S_VERSION=$(curl -sS --connect-timeout 5 --retry 5 --retry-delay 2 https://api.github.com/repos/derailed/k9s/releases/latest | jq -r .tag_name)
curl -sSLO --connect-timeout 5 --retry 5 --retry-delay 2 "https://github.com/derailed/k9s/releases/download/${K9S_VERSION}/k9s_Linux_amd64.tar.gz"
curl -sSLO --connect-timeout 5 --retry 5 --retry-delay 2 "https://github.com/derailed/k9s/releases/download/${K9S_VERSION}/checksums.sha256"
grep "k9s_Linux_amd64.tar.gz$" checksums.sha256 | sha256sum -c -
tar -xzf k9s_Linux_amd64.tar.gz k9s
install -o root -g root -m 0755 k9s /usr/local/bin/k9s
rm k9s_Linux_amd64.tar.gz checksums.sha256 k9s

# Install helm
curl -fsSL --connect-timeout 5 --retry 5 --retry-delay 2 https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 -o get_helm.sh
chmod 700 get_helm.sh
./get_helm.sh
rm get_helm.sh
