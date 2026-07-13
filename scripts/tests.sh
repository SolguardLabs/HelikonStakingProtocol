#!/usr/bin/env bash
set -euo pipefail
python scripts/compile_sources.py
python -m pytest "$@"
