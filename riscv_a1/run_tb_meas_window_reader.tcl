# run_tb_meas_window_reader.tcl - runs the B3 bench tb_meas_window_reader in XSim (batch, non-project; NOT registered evidence).
# Vivado Tcl console (any project open or none):
#   source C:/vivado_verilog_proj/NOC_PQATTEST/riscv_a1/run_tb_meas_window_reader.tcl
# Expected end of the log (a few seconds of simulation):
#   CHECKS : 10
#   ERRORS : 0
#   RESULT : PASS
# The log is written to riscv_a1/run/tb_meas_window_reader_run.log. The bench ends by itself ($finish) on every path.
set here [file normalize [file dirname [info script]]]
set bin  [file join $::env(XILINX_VIVADO) bin]
if {![file isdirectory $bin]} { set bin C:/xilinx_vivado/Vivado/2024.1/bin }
set root [file normalize [file join $here ..]]
set srcs {}
foreach p [list [file join $root rtl riscv meas_window_reader.sv] [file join $root sim_riscv tb_meas_window_reader.sv]] {
  if {![file isfile $p]} { error "missing $p" }
  lappend srcs [file nativename $p]
}
set inc [file nativename [file join $root vectors]]   ;# d2_k3_64.svh (read-only include)
set run [file join $here run]
file mkdir $run
set old [pwd]
cd $run
set log [file join $run tb_meas_window_reader_run.log]
puts "compiling ([llength $srcs] files) ..."
if {[catch {exec cmd.exe /c [file nativename [file join $bin xvlog.bat]] -sv -i $inc {*}$srcs > [file join $run xvlog_b3.txt] 2>@1} e]} {
  cd $old; error "xvlog failed, see [file join $run xvlog_b3.txt]"
}
if {[catch {exec cmd.exe /c [file nativename [file join $bin xelab.bat]] -s b3_meas_window_reader work.tb_meas_window_reader > [file join $run xelab_b3.txt] 2>@1} e]} {
  cd $old; error "xelab failed, see [file join $run xelab_b3.txt]"
}
puts "simulating (log $log) ..."
catch {exec cmd.exe /c [file nativename [file join $bin xsim.bat]] b3_meas_window_reader -R > $log 2>@1}
cd $old
set f [open $log r]; set t [read $f]; close $f
foreach l [split $t \n] {
  if {[regexp {^(\[FAIL\]|\[PASS\]|CONFIG|CHECKS|ERRORS|RESULT)} $l]} { puts $l }
}
if {[regexp -line {^RESULT : PASS$} $t]} {
  puts "B3 meas_window_reader: PASS (bench ended by itself)"
} elseif {[regexp -line {^RESULT : FAIL$} $t]} {
  puts "B3 meas_window_reader: FAIL (see $log)"
} else {
  puts "B3 meas_window_reader: NO RESULT - the simulator did not start or was stopped (XSim start stall: just source this file again). Log: $log"
}
