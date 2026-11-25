# run_tb_tmem_app_bridge.tcl - runs the B1 bench tb_tmem_app_bridge in XSim (batch, non-project; NOT registered evidence).
# Vivado Tcl console (any project open or none):
#   source C:/vivado_verilog_proj/NOC_PQATTEST/riscv_a1/run_tb_tmem_app_bridge.tcl
# Expected end of the log (well under a minute of simulation):
#   CHECKS : 19
#   ERRORS : 0
#   RESULT : PASS
# The log is written to riscv_a1/run/tb_tmem_app_bridge_run.log. The bench ends by itself ($finish) on every path.
set here [file normalize [file dirname [info script]]]
set bin  [file join $::env(XILINX_VIVADO) bin]
if {![file isdirectory $bin]} { set bin C:/xilinx_vivado/Vivado/2024.1/bin }
set root [file normalize [file join $here ..]]
set srcs {}
foreach p [list [file join $root rtl dual_lane NOC_PKG.sv] [file join $root rtl riscv tmem_app_bridge.sv] \
                [file join $root sim_riscv tb_tmem_app_bridge.sv]] {
  if {![file isfile $p]} { error "missing $p" }
  lappend srcs [file nativename $p]
}
set run [file join $here run]
file mkdir $run
set old [pwd]
cd $run
set log [file join $run tb_tmem_app_bridge_run.log]
puts "compiling ([llength $srcs] files) ..."
if {[catch {exec cmd.exe /c [file nativename [file join $bin xvlog.bat]] -sv {*}$srcs > [file join $run xvlog_b1.txt] 2>@1} e]} {
  cd $old; error "xvlog failed, see [file join $run xvlog_b1.txt]"
}
if {[catch {exec cmd.exe /c [file nativename [file join $bin xelab.bat]] -s b1_tmem_app_bridge work.tb_tmem_app_bridge > [file join $run xelab_b1.txt] 2>@1} e]} {
  cd $old; error "xelab failed, see [file join $run xelab_b1.txt]"
}
puts "simulating (log $log) ..."
catch {exec cmd.exe /c [file nativename [file join $bin xsim.bat]] b1_tmem_app_bridge -R > $log 2>@1}
cd $old
set f [open $log r]; set t [read $f]; close $f
foreach l [split $t \n] {
  if {[regexp {^(\[FAIL\]|CONFIG|CHECKS|ERRORS|RESULT)} $l]} { puts $l }
}
if {[regexp -line {^RESULT : PASS$} $t]} {
  puts "B1 tmem_app_bridge: PASS (bench ended by itself)"
} elseif {[regexp -line {^RESULT : FAIL$} $t]} {
  puts "B1 tmem_app_bridge: FAIL (see $log)"
} else {
  puts "B1 tmem_app_bridge: NO RESULT - the simulator did not start or was stopped (XSim start stall: just source this file again). Log: $log"
}
