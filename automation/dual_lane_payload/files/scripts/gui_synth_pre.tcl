# Pre-synthesis hook of run synth_merged (scripts/merged_gui_runs.tcl): one thread as in the release flow, and the firmware
# images next to the run so $readmemh("demo_fw_v2.hex") resolves exactly as in merged_bitstream_flow.tcl.
set_param general.maxThreads 1
set gui_root [file normalize [file join [file dirname [info script]] ..]]
source [file join $gui_root scripts merged_bitstream_sources.tcl]
foreach m [dict get [dict get $::merged_bit merged_board] mem_init] { file copy -force [file join $gui_root $m] [pwd] }
puts "GUI_SYNTH_PRE maxThreads=[get_param general.maxThreads] firmware copied to [pwd]"
