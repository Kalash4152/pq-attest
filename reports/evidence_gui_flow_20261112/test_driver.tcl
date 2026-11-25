open_project [file join [pwd] NOC_PQATTEST.xpr]
source C:/vivado_verilog_proj/NOC_PQATTEST/scripts/merged_gui_runs.tcl
puts "T_ACTIVE: [current_run -synthesis] [current_run -implementation]"
source C:/vivado_verilog_proj/NOC_PQATTEST/scripts/merged_gui_runs.tcl
puts "T_RESOURCE_OK"
gui_merged_build
wait_on_run impl_merged
puts "T_SYNTH: [get_property STATUS [get_runs synth_merged]] | T_IMPL: [get_property STATUS [get_runs impl_merged]] progress [get_property PROGRESS [get_runs impl_merged]]"
puts "T_WNS: [get_property STATS.WNS [get_runs impl_merged]] T_WHS: [get_property STATS.WHS [get_runs impl_merged]]"
close_project
