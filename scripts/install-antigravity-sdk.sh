#!/bin/bash
set -euo pipefail

# Install Antigravity SDK (google-antigravity)
echo "Installing Antigravity SDK..."
pip3 install --root-user-action=ignore --no-cache-dir --break-system-packages --retries 10 google-antigravity==0.1.0
