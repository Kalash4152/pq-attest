# run_tb_tile_top.tcl - runs the fixed RISC-V A1 bench tb_tile_top in XSim (batch, non-project; NOT registered evidence).
# Vivado Tcl console (any project open or none):
#   source C:/vivado_verilog_proj/NOC_PQATTEST/riscv_a1/run_tb_tile_top.tcl
# Expected end of the log (about 1-2 minutes):
#   A1 FINAL: pc=00000148 max_pc=00000148 end_loop=1 run_cycles=40469 core_transfers=6229 adapter_captures=6229 adapter_responses=6229 ...
#   RESULT : PASS
# The log is written to riscv_a1/run/tb_tile_top_run.log. The bench ends by itself ($finish) on every path.
set here [file normalize [file dirname [info script]]]
set bin  [file join $::env(XILINX_VIVADO) bin]
if {![file isdirectory $bin]} { set bin C:/xilinx_vivado/Vivado/2024.1/bin }
# Single source of truth since 2026-11-06: the imported tile in rtl/riscv/, benches in sim_riscv/, firmware in sw/riscv/
# (docs/riscv_lane/IMPORT_MANIFEST.json). The run happens in riscv_a1/run/ (not committed).
set root [file normalize [file join $here ..]]
set srcs {}
foreach f {picorv32.v picorv32_adapter.sv addr_decode.sv tile_status.sv uart_tx.sv uart_mmio.sv tile_top.sv mem_bram.sv gpio.sv tile_mem_wrapper.sv} {
  set p [file join $root rtl riscv $f]
  if {![file isfile $p]} { error "missing $p" }
  lappend srcs [file nativename $p]
}
lappend srcs [file nativename [file join $root sim_riscv tb_tile_top.sv]]
set run [file join $here run]
file mkdir [file join $run sw]
file copy -force [file join $root sw riscv hello_words.hex] [file join $run sw hello_words.hex]
set old [pwd]
cd $run    ;# the bench loads sw/hello_words.hex relative to the run folder
set log [file join $run tb_tile_top_run.log]
puts "compiling ([llength $srcs] files) ..."
if {[catch {exec cmd.exe /c [file nativename [file join $bin xvlog.bat]] -sv {*}$srcs > [file join $run xvlog_a1.txt] 2>@1} e]} {
  cd $old; error "xvlog failed, see [file join $run xvlog_a1.txt]"
}
if {[catch {exec cmd.exe /c [file nativename [file join $bin xelab.bat]] -s a1_tile_top work.tb_tile_top > [file join $run xelab_a1.txt] 2>@1} e]} {
  cd $old; error "xelab failed, see [file join $run xelab_a1.txt]"
}
puts "simulating (log $log) ..."
catch {exec cmd.exe /c [file nativename [file join $bin xsim.bat]] a1_tile_top -R > $log 2>@1}
cd $old
set f [open $log r]; set t [read $f]; close $f
foreach l [split $t \n] {
  if {[regexp {A1 FINAL.*} $l m]} { puts $m } elseif {[regexp {^(PASS|FAIL|RESULT|  )} $l]} { puts $l }
}
if {[regexp -line {^RESULT : PASS$} $t]} {
  puts "A1 tile_top: PASS (bench ended by itself)"
} elseif {[regexp -line {^RESULT : FAIL$} $t]} {
  puts "A1 tile_top: FAIL (see $log)"
} else {
  puts "A1 tile_top: NO RESULT - the simulator did not start or was stopped (XSim start stall: just source this file again). Log: $log"
}
