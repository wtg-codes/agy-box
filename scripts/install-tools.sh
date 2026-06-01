#!/bin/bash
set -euo pipefail

TARGETARCH="${1:-amd64}"
if [[ "$TARGETARCH" =~ arm ]]; then
    ARCH="arm64"
else
    ARCH="amd64"
fi

echo "Installing CNCF tools for ${ARCH}..."

# 4. Install CNCF Tooling
# Install kubectl
KUBECTL_VERSION="v1.36.1"
if [[ "$ARCH" = "amd64" ]]; then
    KUBECTL_SHA256="629d3f410e09bf49b64ae7079f7f0bda1191efed311f7d37fdbab0ad5b0ec2b7"
else
    KUBECTL_SHA256=$(curl -fsSL "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/${ARCH}/kubectl.sha256")
fi

curl -LO --http1.1 --connect-timeout 5 --retry 5 --retry-delay 2 "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/${ARCH}/kubectl"
echo "${KUBECTL_SHA256}  kubectl" | sha256sum -c -
install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl
rm kubectl

# Install k9s
K9S_VERSION="v0.50.18"
curl -sSLO --http1.1 --connect-timeout 5 --retry 5 --retry-delay 2 "https://github.com/derailed/k9s/releases/download/${K9S_VERSION}/k9s_Linux_${ARCH}.tar.gz"
curl -sSLO --http1.1 --connect-timeout 5 --retry 5 --retry-delay 2 "https://github.com/derailed/k9s/releases/download/${K9S_VERSION}/checksums.sha256"
grep "k9s_Linux_${ARCH}.tar.gz$" checksums.sha256 | sha256sum -c -
tar -xzf "k9s_Linux_${ARCH}.tar.gz" k9s
install -o root -g root -m 0755 k9s /usr/local/bin/k9s
rm "k9s_Linux_${ARCH}.tar.gz" checksums.sha256 k9s

# Install helm
HELM_VERSION="v3.21.0"
if [[ "$ARCH" = "amd64" ]]; then
    HELM_SHA256="0093eb572e3d2380f094df162ddb525e219249de88957afe24cfbb19632acd36"
else
    HELM_SHA256=$(curl -fsSL "https://get.helm.sh/helm-${HELM_VERSION}-linux-${ARCH}.tar.gz.sha256" | awk '{print $1}')
fi

curl -sSLO --http1.1 --connect-timeout 5 --retry 5 --retry-delay 2 "https://get.helm.sh/helm-${HELM_VERSION}-linux-${ARCH}.tar.gz"
echo "${HELM_SHA256}  helm-${HELM_VERSION}-linux-${ARCH}.tar.gz" | sha256sum -c -
tar -xzf "helm-${HELM_VERSION}-linux-${ARCH}.tar.gz" "linux-${ARCH}/helm"
install -o root -g root -m 0755 "linux-${ARCH}/helm" /usr/local/bin/helm
rm -rf "helm-${HELM_VERSION}-linux-${ARCH}.tar.gz" "linux-${ARCH}"
