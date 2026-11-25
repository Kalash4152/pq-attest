# Pre-implementation hook of run impl_merged (scripts/merged_gui_runs.tcl): one thread as in the release flow.
set_param general.maxThreads 1
puts "GUI_IMPL_PRE maxThreads=[get_param general.maxThreads]"
