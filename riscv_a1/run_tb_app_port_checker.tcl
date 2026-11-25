# run_tb_app_port_checker.tcl - runs the B5 bench tb_app_port_checker in XSim (batch, non-project; NOT registered evidence).
# Vivado Tcl console (any project open or none):
#   source C:/vivado_verilog_proj/NOC_PQATTEST/riscv_a1/run_tb_app_port_checker.tcl
# Expected end of the log:
#   CHECKS : 10
#   ERRORS : 0
#   RESULT : PASS
# The negative cases print 8 expected "[FAIL] B5_<PROPERTY> t=..." lines from the checker itself; the bench's own verdict is
# the "[PASS] B5_NEG_..." line after each. The log is written to riscv_a1/run/tb_app_port_checker_run.log.
set here [file normalize [file dirname [info script]]]
set bin  [file join $::env(XILINX_VIVADO) bin]
if {![file isdirectory $bin]} { set bin C:/xilinx_vivado/Vivado/2024.1/bin }
set root [file normalize [file join $here ..]]
set srcs {}
foreach p [list [file join $root rtl dual_lane NOC_PKG.sv] [file join $root rtl riscv tmem_app_bridge.sv] \
                [file join $root sim_riscv app_port_checker.sv] [file join $root sim_riscv tb_app_port_checker.sv]] {
  if {![file isfile $p]} { error "missing $p" }
  lappend srcs [file nativename $p]
}
set run [file join $here run]
file mkdir $run
set old [pwd]
cd $run
set log [file join $run tb_app_port_checker_run.log]
puts "compiling ([llength $srcs] files) ..."
if {[catch {exec cmd.exe /c [file nativename [file join $bin xvlog.bat]] -sv {*}$srcs > [file join $run xvlog_b5.txt] 2>@1} e]} {
  cd $old; error "xvlog failed, see [file join $run xvlog_b5.txt]"
}
if {[catch {exec cmd.exe /c [file nativename [file join $bin xelab.bat]] -s b5_app_port_checker work.tb_app_port_checker > [file join $run xelab_b5.txt] 2>@1} e]} {
  cd $old; error "xelab failed, see [file join $run xelab_b5.txt]"
}
puts "simulating (log $log) ..."
catch {exec cmd.exe /c [file nativename [file join $bin xsim.bat]] b5_app_port_checker -R > $log 2>@1}
cd $old
set f [open $log r]; set t [read $f]; close $f
foreach l [split $t \n] {
  if {[regexp {^(\[PASS\]|\[FAIL\] B5_(CLEAN|NEG)|CONFIG|CHECKS|ERRORS|RESULT)} $l]} { puts $l }
}
if {[regexp -line {^RESULT : PASS$} $t]} {
  puts "B5 app_port_checker: PASS (bench ended by itself)"
} elseif {[regexp -line {^RESULT : FAIL$} $t]} {
  puts "B5 app_port_checker: FAIL (see $log)"
} else {
  puts "B5 app_port_checker: NO RESULT - the simulator did not start or was stopped (XSim start stall: just source this file again). Log: $log"
}
