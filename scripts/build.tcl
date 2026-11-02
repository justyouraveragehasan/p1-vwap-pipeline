# build.tcl — synth + implement the VWAP core to get Fmax / utilization.
# No board pins: this is a streaming core. We constrain only the clock and let
# Vivado place the stream ports on arbitrary IOBs — internal-path timing is what
# matters here.
set part xc7a100tcsg324-1
set top  vwap_top

file mkdir build

read_verilog -sv rtl/vwap_pkg.sv
read_verilog -sv rtl/mult_stage.sv rtl/window_accum.sv rtl/divider.sv rtl/vwap_top.sv

synth_design -top $top -part $part
create_clock -name clk -period 10.000 [get_ports clk]
opt_design
place_design
route_design

report_timing_summary -file build/timing.rpt
report_utilization    -file build/util.rpt

set wns [get_property SLACK [get_timing_paths -max_paths 1 -nworst 1 -setup]]
puts "RESULT wns=$wns ns  => Fmax ~ [expr {1000.0/(10.0-$wns)}] MHz"
puts "BUILD DONE"
