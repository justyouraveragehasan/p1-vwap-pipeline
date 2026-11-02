#!/usr/bin/env bash
# Run the VWAP testbench in Vivado xsim inside the 'vivado' distrobox.
#   usage: scripts/sim.sh [tb_vwap]
set -euo pipefail
TB="${1:-tb_vwap}"
PROJ_DIR="$(cd "$(dirname "$0")/.." && pwd)"

distrobox enter vivado -- bash -lc "
  set -e
  source ~/.local/Xilinx/2026.1/Vivado/settings64.sh >/dev/null
  cd '$PROJ_DIR'
  rm -rf build && mkdir -p build && cd build
  # package MUST compile before the modules that import it
  xvlog -sv ../rtl/vwap_pkg.sv \
            ../rtl/mult_stage.sv ../rtl/window_accum.sv ../rtl/divider.sv \
            ../rtl/vwap_top.sv ../tb/${TB}.sv
  xelab -debug typical ${TB} -s ${TB}_sim
  xsim ${TB}_sim -runall
"
