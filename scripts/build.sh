#!/usr/bin/env bash
set -euo pipefail
PROJ_DIR="$(cd "$(dirname "$0")/.." && pwd)"
distrobox enter vivado -- bash -lc "
  set -e
  source ~/.local/Xilinx/2026.1/Vivado/settings64.sh >/dev/null
  cd '$PROJ_DIR'
  mkdir -p build
  vivado -mode batch -source scripts/build.tcl -nojournal -log build/vivado.log
"
