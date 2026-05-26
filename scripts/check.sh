#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
if [[ -f Package.swift ]]; then swift test; fi
if [[ -f package.json ]]; then bun test || npm test; fi
