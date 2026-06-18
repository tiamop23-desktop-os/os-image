#!/usr/bin/env bash
set -euo pipefail

mkdir -p /etc/skel/.vscode/extensions
mkdir -p /etc/skel/.config/Code

HOME=/etc/skel code \
  --user-data-dir /etc/skel/.config/Code \
  --extensions-dir /etc/skel/.vscode/extensions \
  --install-extension ms-vscode-remote.remote-containers \
  --force