#!/usr/bin/env bash
set -euo pipefail

rm -f "${HOME}/.local/share/applications/dew-encryption.desktop"
rm -f "${HOME}/.local/share/icons/hicolor/512x512/apps/dew-encryption.png"
rm -rf "${HOME}/.local/share/nautilus/scripts/Dew Encryption"

python3 -m pip uninstall -y dew-encryption || true

echo "Dew Encryption Linux integration removed."
