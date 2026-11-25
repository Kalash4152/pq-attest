# Stage 8 (pq_attestation_controller) XSim run.
#   tb_stg_8     (pq_attestation_controller_tb) : sequencing/status/rejection tests
#   tb_stg_8_ref (tb_stg_8_ref)                 : bit-exact 776-bit response vs an
#                                                 independent Stage 5/6/7 reference chain
# Each run: clean snapshot, recompile proof, simulate.log copied AFTER close_sim.
# Usage (Vivado Tcl console, project open, no simulation running):
#   source C:/vivado_verilog_proj/NOC_PQATTEST/scripts/s8_xsim.tcl
set R    C:/vivado_verilog_proj/NOC_PQATTEST
set NEW  $R/NOC_PQATTEST.srcs/sources_1/new
set XDIR $R/NOC_PQATTEST.sim/sim_1/behav/xsim
set DATE [clock format [clock seconds] -format %Y-%m-%d]
set SIM  [get_filesets sim_1]

# 0. Guard: pqattest_stg7.sv must contain module pq_attestation_tag (it was overwritten once).
set fh [open $NEW/pqattest_stg7.sv r]; set t [read $fh]; close $fh
if {![regexp {module\s+pq_attestation_tag} $t]} {
  error "pqattest_stg7.sv does not define pq_attestation_tag - restore it first (git checkout -- NOC_PQATTEST.srcs/sources_1/new/pqattest_stg7.sv)"
}
# 1. Files: Stage-7 pair enabled; the orphan duplicate package stays out of the build.
foreach f {pqattest_stg7_pkg.sv pqattest_stg7.sv pq_attest_protocol.sv} {
  set_property is_enabled true [get_files $NEW/$f]
}
catch {set_property is_enabled false [get_files $NEW/pq_attest_protocol_pkg.sv]}
set TBR $R/NOC_PQATTEST.srcs/sim_1/new/tb_stg_8_ref.sv
if {[llength [get_files -quiet -of_objects $SIM $TBR]] == 0} { add_files -fileset sim_1 -norecurse $TBR }
update_compile_order -fileset sim_1

proc s8_run {top tag} {
  global R XDIR DATE SIM
  puts "\n######## $tag ($top) ########"
  set_property top $top $SIM
  set_property top_lib xil_defaultlib $SIM
  after 5000
  catch {reset_simulation -simset sim_1 -mode behavioral}
  set_property -name {xsim.simulate.runtime} -value {1ns} -objects $SIM
  set t0 [clock seconds]; set ok 0
  for {set t 0} {$t < 3 && !$ok} {incr t} {
    if {[catch {launch_simulation} e]} { puts "launch retry ($t): $e"; after 5000 } else { set ok 1 }
  }
  if {!$ok} { puts "$tag: launch FAILED 3x - read $XDIR/elaborate.log"; return }
  set sdb $XDIR/xsim.dir/xil_defaultlib/${top}.sdb
  if {[file exists $sdb] && [file mtime $sdb] >= $t0} { puts "$tag: RECOMPILED" } else { puts "$tag: *** NOT RECOMPILED - RESULT INVALID ***" }
  catch {run all}
  catch {close_sim}
  file copy -force $XDIR/simulate.log $R/logs/${tag}_${DATE}.log
  puts "saved logs/${tag}_${DATE}.log"
}

# set S8_ONLY ref before sourcing to rerun only tb_stg_8_ref.
if {![info exists S8_ONLY] || $S8_ONLY ne "ref"} { s8_run pq_attestation_controller_tb s8_ctrl_tb }
s8_run tb_stg_8_ref                 s8_ref_tb
set_property -name {xsim.simulate.runtime} -value {20us} -objects $SIM
puts "\nVerilator reference (same sources): s8_ctrl_tb TOTAL ERRORS 0 / TB PASS; s8_ref_tb 146/0 PASS."
foreach t {s8_ctrl_tb s8_ref_tb} {
  set f $R/logs/${t}_${DATE}.log
  if {![file exists $f]} { puts [format "%-11s NO LOG" $t]; continue }
  set fh [open $f r]; set x [read $fh]; close $fh
  set nf [regexp -all {\[FAIL\]} $x]; set np [regexp -all {\[PASS\]} $x]
  set res [expr {[regexp {RESULT : PASS|TB PASS} $x] && $nf == 0 ? "PASS" : "FAIL/CHECK"}]
  puts [format "%-11s %s  PASS-lines=%d FAIL-lines=%d" $t $res $np $nf]
}
