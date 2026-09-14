#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

python3 "$SCRIPT_DIR/collect.py"
python3 "$SCRIPT_DIR/probe_mbl_headless.py"
python3 "$SCRIPT_DIR/process.py"
python3 "$SCRIPT_DIR/validate.py"

echo "Core pilot complete. Write or update the quality-report README, then run build_manifest.py once."
