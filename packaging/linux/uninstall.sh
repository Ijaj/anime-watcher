#!/usr/bin/env bash
# Removes what install.sh put in place. Use --system to match a --system install.
set -euo pipefail

LAUNCHER_NAME=anime-watcher
SYSTEM_INSTALL=0
[ "${1:-}" = "--system" ] && SYSTEM_INSTALL=1

if [ "$SYSTEM_INSTALL" = 1 ]; then
  INSTALL_ROOT=/opt/anime-watcher
  BIN_DIR=/usr/local/bin
  DESKTOP_DIR=/usr/share/applications
  ICON_DIR=/usr/share/icons/hicolor/192x192/apps
  SUDO=sudo
  [ "$(id -u)" = 0 ] && SUDO=
else
  INSTALL_ROOT="$HOME/.local/share/anime-watcher"
  BIN_DIR="$HOME/.local/bin"
  DESKTOP_DIR="$HOME/.local/share/applications"
  ICON_DIR="$HOME/.local/share/icons/hicolor/192x192/apps"
  SUDO=
fi

$SUDO rm -rf "$INSTALL_ROOT"
$SUDO rm -f "$BIN_DIR/$LAUNCHER_NAME" "$DESKTOP_DIR/$LAUNCHER_NAME.desktop" "$ICON_DIR/$LAUNCHER_NAME.png"
echo "Removed anime_watcher (kept ~/.local/share/anime_watcher app data / database, if any)."
