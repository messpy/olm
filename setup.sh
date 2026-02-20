#!/usr/bin/env bash
set -Eeuo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENTRY="$REPO_ROOT/bin/olm"

[ -f "$ENTRY" ] || { echo "ERROR: entry not found: $ENTRY" >&2; exit 1; }

BIN_DIR="$HOME/bin"
BIN_LINK="$BIN_DIR/olm"
CFG_DIR="$HOME/.config/olm"
CFG_FILE="$CFG_DIR/config.env"

mkdir -p "$BIN_DIR" "$CFG_DIR"

# 既存が実ファイルなら退避（symlinkは張り替え）
if [ -e "$BIN_LINK" ] && [ ! -L "$BIN_LINK" ]; then
  mv "$BIN_LINK" "${BIN_LINK}.old.$(date +%Y%m%d%H%M%S)"
fi

rm -f "$BIN_LINK"
ln -s "$ENTRY" "$BIN_LINK"
chmod +x "$ENTRY"

# config 初期化（既存は保持）
if [ ! -f "$CFG_FILE" ]; then
  cp -a "$REPO_ROOT/config/config.env.example" "$CFG_FILE"
  echo "Created: $CFG_FILE"
else
  echo "Keep: $CFG_FILE"
fi

# PATH
if ! grep -q 'export PATH="$HOME/bin:$PATH"' "$HOME/.profile" 2>/dev/null; then
  printf '\nexport PATH="$HOME/bin:$PATH"\n' >> "$HOME/.profile"
  echo "Updated: ~/.profile"
fi

echo "OK: installed olm -> $BIN_LINK"
echo "Next: source ~/.profile"
