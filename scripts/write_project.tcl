# write_project.tcl — generate a Vivado GUI project from the P1 sources.
# The .xpr is disposable (git-ignored); this script is too. Regenerate any time:
#   scripts/open.sh    (creates it if missing, then opens the GUI)
set origin  [file normalize [file join [file dirname [info script]] ..]]
set prj_dir [file join $origin vivado_prj]
set part    xc7a100tcsg324-1

create_project -force p1_vwap $prj_dir -part $part

# RTL (update_compile_order resolves the package dependency order)
add_files [glob $origin/rtl/*.sv]
set_property top vwap_top [current_fileset]

# simulation
add_files -fileset sim_1 [glob $origin/tb/*.sv]
set_property top tb_vwap [get_filesets sim_1]

set_property file_type SystemVerilog [get_files *.sv]
update_compile_order -fileset sources_1
update_compile_order -fileset sim_1

puts "PROJECT CREATED: [file join $prj_dir p1_vwap.xpr]"
