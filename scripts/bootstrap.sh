#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
if command -v swift >/dev/null 2>&1; then swift package resolve; fi
if [[ -f package.json ]]; then command -v bun >/dev/null 2>&1 && bun install || npm install; fi
echo "Bootstrap complete."
