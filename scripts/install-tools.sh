#!/bin/bash
set -euo pipefail

echo "Installing CNCF tools..."

# 4. Install CNCF Tooling
# Install kubectl
KUBECTL_VERSION="v1.36.1"
KUBECTL_SHA256="629d3f410e09bf49b64ae7079f7f0bda1191efed311f7d37fdbab0ad5b0ec2b7"
curl -LO --http1.1 --connect-timeout 5 --retry 5 --retry-delay 2 "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/amd64/kubectl"
echo "${KUBECTL_SHA256}  kubectl" | sha256sum -c -
install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl
rm kubectl

# Install k9s
K9S_VERSION="v0.50.18"
curl -sSLO --http1.1 --connect-timeout 5 --retry 5 --retry-delay 2 "https://github.com/derailed/k9s/releases/download/${K9S_VERSION}/k9s_Linux_amd64.tar.gz"
curl -sSLO --http1.1 --connect-timeout 5 --retry 5 --retry-delay 2 "https://github.com/derailed/k9s/releases/download/${K9S_VERSION}/checksums.sha256"
grep "k9s_Linux_amd64.tar.gz$" checksums.sha256 | sha256sum -c -
tar -xzf k9s_Linux_amd64.tar.gz k9s
install -o root -g root -m 0755 k9s /usr/local/bin/k9s
rm k9s_Linux_amd64.tar.gz checksums.sha256 k9s

# Install helm
HELM_VERSION="v3.21.0"
HELM_SHA256="0e3c20f221b74285e0db235e1837af340dd0957528dc701cffc26b2f8cc42fdd"
curl -sSLO --http1.1 --connect-timeout 5 --retry 5 --retry-delay 2 "https://get.helm.sh/helm-${HELM_VERSION}-linux-amd64.tar.gz"
echo "${HELM_SHA256}  helm-${HELM_VERSION}-linux-amd64.tar.gz" | sha256sum -c -
tar -xzf "helm-${HELM_VERSION}-linux-amd64.tar.gz" linux-amd64/helm
install -o root -g root -m 0755 linux-amd64/helm /usr/local/bin/helm
rm -rf "helm-${HELM_VERSION}-linux-amd64.tar.gz" linux-amd64
