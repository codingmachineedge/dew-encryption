#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BIN_DIR="${HOME}/.local/bin"
APP_DIR="${HOME}/.local/share/applications"
ICON_DIR="${HOME}/.local/share/icons/hicolor/512x512/apps"
NAUTILUS_DIR="${HOME}/.local/share/nautilus/scripts/Dew Encryption"

need() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Missing dependency: $1" >&2
    exit 1
  fi
}

need python3
need git
need 7z

python3 -m pip install --user -e "${ROOT}"

mkdir -p "${BIN_DIR}" "${APP_DIR}" "${ICON_DIR}" "${NAUTILUS_DIR}"
cp "${ROOT}/assets/icons/dew-main.png" "${ICON_DIR}/dew-encryption.png"
cp "${ROOT}/linux/dew-encryption.desktop" "${APP_DIR}/dew-encryption.desktop"
chmod +x "${APP_DIR}/dew-encryption.desktop"

cp "${ROOT}/linux/nautilus-scripts/"* "${NAUTILUS_DIR}/"
chmod +x "${NAUTILUS_DIR}/"*

if command -v update-desktop-database >/dev/null 2>&1; then
  update-desktop-database "${APP_DIR}" || true
fi

if command -v gtk-update-icon-cache >/dev/null 2>&1; then
  gtk-update-icon-cache "${HOME}/.local/share/icons/hicolor" || true
fi

cat <<'MSG'
Dew Encryption installed for Linux.

CLI:
  dew-encryption --help

GUI:
  dew-encryption-gui

Nautilus scripts:
  Right-click files or folders, then choose Scripts > Dew Encryption.
MSG
