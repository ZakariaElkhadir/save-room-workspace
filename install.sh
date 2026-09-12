#!/usr/bin/env bash
#
#  install.sh — installer for start-environment
#  Creates symlinks, default config, and desktop entry.
#

set -euo pipefail

PREFIX="${PREFIX:-$HOME/.local}"
BIN_DIR="$PREFIX/bin"
APP_DIR="$PREFIX/share/applications"
CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/start-environment"
SCRIPT_SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/start-environment.sh"

echo "Installing start-environment to $PREFIX..."

mkdir -p "$BIN_DIR" "$APP_DIR" "$CONFIG_DIR"

# Link executable
ln -sf "$SCRIPT_SRC" "$BIN_DIR/start-environment"
ln -sf "$SCRIPT_SRC" "$BIN_DIR/start-environement"
chmod +x "$SCRIPT_SRC"

# Default config if not already created
if [[ ! -f "$CONFIG_DIR/config.env" ]]; then
  cp "$(dirname "$SCRIPT_SRC")/config.example.env" "$CONFIG_DIR/config.env"
  echo "✓ Created configuration file: $CONFIG_DIR/config.env"
else
  echo "· Preserved existing configuration at $CONFIG_DIR/config.env"
fi

# Create Desktop Entry for GNOME / Application Launcher
cat > "$APP_DIR/start-environment.desktop" <<EOF
[Desktop Entry]
Name=Start Work Environment
Comment=Boot ambient multi-monitor development workspace with Save Room soundtrack
Exec=$BIN_DIR/start-environment
Icon=utilities-terminal
Terminal=true
Type=Application
Categories=Development;Utility;
Keywords=workspace;environment;ide;ghostty;soundtrack;saveroom;
EOF

chmod +x "$APP_DIR/start-environment.desktop"
command -v update-desktop-database >/dev/null 2>&1 && update-desktop-database "$APP_DIR" 2>/dev/null || true

echo "✓ Installation complete!"
echo "  • Executable: $BIN_DIR/start-environment"
echo "  • Config:     $CONFIG_DIR/config.env"
echo "  • Launcher:   Super key -> 'Start Work Environment'"
