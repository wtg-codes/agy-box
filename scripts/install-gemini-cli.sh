#!/bin/bash
set -euo pipefail

# 5. Install AI Agent Dependencies
echo "Installing Gemini CLI..."
npm install -g --omit=dev --no-audit --no-fund @google/gemini-cli
