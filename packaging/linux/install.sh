#!/usr/bin/env bash
# Installs the anime_watcher Linux build for the current user (default) or
# system-wide (--system), then installs the runtime libraries it needs
# (mpv, sqlite3, gtk3) with the host's package manager.
#
# Usage:
#   ./install.sh              # install to ~/.local/share/anime-watcher
#   ./install.sh --system     # install to /opt/anime-watcher (needs sudo)
#   ./install.sh --no-deps    # skip the package-manager step
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_NAME=anime_watcher
LAUNCHER_NAME=anime-watcher

SYSTEM_INSTALL=0
INSTALL_DEPS=1
for arg in "$@"; do
  case "$arg" in
    --system) SYSTEM_INSTALL=1 ;;
    --no-deps) INSTALL_DEPS=0 ;;
    -h|--help)
      sed -n '2,10p' "$0"
      exit 0
      ;;
    *)
      echo "Unknown option: $arg" >&2
      exit 1
      ;;
  esac
done

# Find the built bundle: next to this script (release tarball layout) or in
# the repo's build/ output (running straight from a checkout).
if [ -d "$SCRIPT_DIR/bundle" ]; then
  BUNDLE_DIR="$SCRIPT_DIR/bundle"
elif [ -d "$SCRIPT_DIR/../../build/linux/x64/release/bundle" ]; then
  BUNDLE_DIR="$SCRIPT_DIR/../../build/linux/x64/release/bundle"
else
  echo "error: can't find a built app bundle." >&2
  echo "Run 'flutter build linux --release' first, or use a release tarball that ships a bundle/ directory next to this script." >&2
  exit 1
fi

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

echo "Installing anime_watcher to $INSTALL_ROOT ..."
$SUDO mkdir -p "$INSTALL_ROOT" "$BIN_DIR" "$DESKTOP_DIR" "$ICON_DIR"
$SUDO rm -rf "$INSTALL_ROOT"/*
$SUDO cp -r "$BUNDLE_DIR"/. "$INSTALL_ROOT"/

$SUDO tee "$BIN_DIR/$LAUNCHER_NAME" >/dev/null <<EOF
#!/usr/bin/env bash
exec "$INSTALL_ROOT/$APP_NAME" "\$@"
EOF
$SUDO chmod +x "$BIN_DIR/$LAUNCHER_NAME"

if [ -f "$SCRIPT_DIR/../../assets/logo.png" ]; then
  $SUDO cp "$SCRIPT_DIR/../../assets/logo.png" "$ICON_DIR/$LAUNCHER_NAME.png"
fi

$SUDO sed "s/Exec=anime-watcher/Exec=$LAUNCHER_NAME/;s/Icon=anime-watcher/Icon=$LAUNCHER_NAME/" \
  "$SCRIPT_DIR/anime-watcher.desktop" | $SUDO tee "$DESKTOP_DIR/$LAUNCHER_NAME.desktop" >/dev/null

case ":$PATH:" in
  *":$BIN_DIR:"*) ;;
  *) echo "note: $BIN_DIR is not on your PATH — add it to run '$LAUNCHER_NAME' from a shell." ;;
esac

if [ "$INSTALL_DEPS" = 1 ]; then
  echo
  echo "Checking runtime dependencies (mpv, sqlite3, gtk3) ..."
  missing=0
  ldconfig -p 2>/dev/null | grep -q 'libmpv\.so' || missing=1
  ldconfig -p 2>/dev/null | grep -q 'libsqlite3\.so' || missing=1
  ldconfig -p 2>/dev/null | grep -q 'libgtk-3\.so' || missing=1

  if [ "$missing" = 0 ]; then
    echo "All runtime dependencies are already installed."
  else
    PM_SUDO=sudo
    [ "$(id -u)" = 0 ] && PM_SUDO=
    if command -v pacman >/dev/null 2>&1; then
      echo "Detected pacman (Arch) — installing mpv, sqlite, gtk3 ..."
      $PM_SUDO pacman -S --needed --noconfirm mpv sqlite gtk3
    elif command -v apt-get >/dev/null 2>&1; then
      echo "Detected apt (Debian/Ubuntu) — installing libmpv2, libsqlite3-0, libgtk-3-0 ..."
      $PM_SUDO apt-get update
      $PM_SUDO apt-get install -y libmpv2 libsqlite3-0 libgtk-3-0
    elif command -v dnf >/dev/null 2>&1; then
      echo "Detected dnf (Fedora) — installing mpv-libs, sqlite, gtk3 ..."
      $PM_SUDO dnf install -y mpv-libs sqlite gtk3
    elif command -v zypper >/dev/null 2>&1; then
      echo "Detected zypper (openSUSE) — installing libmpv2, libsqlite3-0, libgtk-3-0 ..."
      $PM_SUDO zypper install -y libmpv2 libsqlite3-0 libgtk-3-0
    else
      echo "warning: unrecognized package manager — install mpv, sqlite3 and gtk3 manually." >&2
    fi
  fi
fi

echo
echo "Done. Launch with '$LAUNCHER_NAME', or find \"Anime Watcher\" in your application menu."
