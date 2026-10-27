#!/bin/bash
set -euo pipefail

# Only run inside Claude Code's remote (web) execution environment.
if [ "${CLAUDE_CODE_REMOTE:-}" != "true" ]; then
  exit 0
fi

GODOT_VERSION="4.7-stable"
GODOT_EXPECTED="4.7.stable.official"
GODOT_URL="https://github.com/godotengine/godot/releases/download/${GODOT_VERSION}/Godot_v${GODOT_VERSION}_linux.x86_64.zip"
GODOT_BIN="$HOME/bin/godot"

mkdir -p "$HOME/bin"

# Idempotent: skip download if the binary is already present and reports
# the expected version.
needs_install=true
if [ -x "$GODOT_BIN" ]; then
  if "$GODOT_BIN" --version 2>/dev/null | grep -q "^${GODOT_EXPECTED}"; then
    needs_install=false
  fi
fi

if $needs_install; then
  tmp_dir="$(mktemp -d)"
  trap 'rm -rf "$tmp_dir"' EXIT
  curl -fsSL -o "$tmp_dir/godot.zip" "$GODOT_URL"
  unzip -q -o "$tmp_dir/godot.zip" -d "$tmp_dir"
  mv "$tmp_dir/Godot_v${GODOT_VERSION}_linux.x86_64" "$GODOT_BIN"
  chmod +x "$GODOT_BIN"
fi

# Expose ~/bin on PATH for the session.
if [ -n "${CLAUDE_ENV_FILE:-}" ]; then
  echo 'export PATH="$HOME/bin:$PATH"' >> "$CLAUDE_ENV_FILE"
fi

# Pre-import the project so the first Godot invocation in the session
# doesn't pay the ~30s import cost. Safe to re-run.
cd "${CLAUDE_PROJECT_DIR:-.}"
"$GODOT_BIN" --headless --import >/dev/null 2>&1 || true
