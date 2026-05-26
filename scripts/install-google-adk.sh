#!/bin/bash
set -euo pipefail

# Google ADK (Agent Development Kit)
# Using --ignore-installed to resolve PyYAML conflict observed in CI
echo "Installing Google ADK..."
pipx install google-adk --pip-args="--no-cache-dir --retries 10"

