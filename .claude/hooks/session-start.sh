#!/usr/bin/env bash
# SessionStart hook — run once when a Claude Code web session opens.
# Verifies the Swift toolchain is available and the package resolves cleanly
# so the AI has early feedback if the build environment is broken.
set -euo pipefail

echo "=== ClickMorph session-start ==="

# 1. Swift toolchain check
if ! command -v swift &>/dev/null; then
  echo "WARNING: swift not found on PATH — builds will fail."
  exit 0
fi
echo "Swift: $(swift --version 2>&1 | head -1)"

# 2. Resolve package graph (downloads nothing if already cached)
echo "Resolving Swift package..."
swift package resolve 2>&1 | tail -5

echo "=== Ready ==="
