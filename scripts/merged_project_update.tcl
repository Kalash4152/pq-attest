# merged_project_update.tcl - add the MERGED SoC to NOC_PQATTEST.xpr and (optionally) build its bitstream.
#
# Status 2026-11-07: steps 1-3 below are DONE in the repo (real cpu_tile_noc, sw/riscv/demo_fw.hex, APPROVED_MEAS under
# REAL_CPU_TILE). Only the Vivado part is left.
# Before sourcing (once the RISC-V package is in the repo):
#   1. Fill the FILL IN block of scripts/make_merged_sources.py (RISC-V files, CPU_TILE_MODULE = cpu_tile_noc, mem files).
#   2. python scripts/make_merged_sources.py        -> scripts/merged_bitstream_sources.tcl (preflight must say PASS)
#   3. python scripts/merged_provision.py --words <firmware imem hex> -> paste CPU_A_IMAGE / APPROVED_MEAS into
#      synth/merged/pq_merged_board_top.sv (the real first 64 IMEM bytes; K3_IMEM_LEN = 64).
# Then, Vivado Tcl console with NOC_PQATTEST.xpr open:
#   source C:/vivado_verilog_proj/NOC_PQATTEST/scripts/merged_project_update.tcl
#   merged_sim [set]    ;# optional: run a bench in the GUI simulator (dl_merged_real, dl_i9_integ, dl_i10_d2). It makes the set ACTIVE
#                       ;# simset first: Vivado applies the include dirs / defines of the active set only (without it the
#                       ;# vectors/*.svh includes are not found; seen in the 2026-11-06 project-copy test)
#   merged_build        ;# starts the merged bitstream build in a hidden worker (S4 flow, ~1 h); the GUI stays free
#   merged_result       ;# any time: still running, or (when done) prints the validated image hash and LUT / WNS / WHS (or refuses the result)
#
# What it changes in the project (nothing else):
#   - backup NOC_PQATTEST.xpr.bak_merged_<timestamp> first;
#   - source set dl_merged_src (merged design list: I-9 variants INSTEAD of their originals, merged core, CPU tiles,
#     board top), constraint set dl_merged_xdc, simulation set dl_merged_real (tb_merged_real; dl_merged_smoke is removed);
#   - sources_1, sim_1, constrs_1, the release runs and the dl_* release simsets are NOT touched (the release bitstreams
#     stay reproducible). Re-sourcing updates the dl_merged_* sets in place (never deletes a set).
# Not registered evidence. Registered merged results come from scripts/dual_lane.py jobs (contract sec. 11).
set P [current_project -quiet]
if {$P eq ""} { error "Open NOC_PQATTEST.xpr first, then source this file." }
if {[get_property NAME $P] ne "NOC_PQATTEST"} { error "Current project is [get_property NAME $P], not NOC_PQATTEST." }
set ::mg_root [get_property DIRECTORY $P]
if {[info exists ::env(MG_ROOT)]} { set ::mg_root $::env(MG_ROOT) }   ;# test copies only: repo root when the .xpr copy lives elsewhere
set gen [file join $::mg_root scripts merged_bitstream_sources.tcl]
if {![file isfile $gen]} { error "run: python scripts/make_merged_sources.py (creates $gen)" }
source $gen
set b [dict get $::merged_bit merged_board]

# backup first
set xpr [file join [get_property DIRECTORY $P] NOC_PQATTEST.xpr]   ;# back up the OPEN project file
set bak "$xpr.bak_merged_[clock format [clock seconds] -format %Y%m%d_%H%M%S]"
file copy -force $xpr $bak
puts "backup: $bak"

# Our own sets are created when missing and UPDATED IN PLACE when present. Nothing is ever deleted: on 2026-11-07 a re-source
# deleted the sets right after a GUI simulation of dl_merged_real and Vivado's GUI crashed (EXCEPTION_ACCESS_VIOLATION in
# FileSet_getName). Re-sourcing is therefore safe at any time; an old dl_merged_smoke set (stub era) is left alone.
proc mg_fileset {kind name} {
  set fs [get_filesets -quiet $name]
  if {$fs eq ""} { set fs [create_fileset $kind $name] }
  return $fs
}
proc mg_norm {f} { return [string tolower [file normalize $f]] }
proc mg_sync_files {fs want} {
  # add the missing files, remove the files of this set that are no longer wanted (own files only, never a whole set)
  set have [get_files -quiet -norecurse -of_objects $fs]
  set hn [lmap f $have {mg_norm $f}]
  set wn [lmap f $want {mg_norm $f}]
  set add {}; foreach f $want n $wn { if {[lsearch -exact $hn $n] < 0} { lappend add $f } }
  set rm  {}; foreach f $have n $hn { if {[lsearch -exact $wn $n] < 0} { lappend rm $f } }
  if {[llength $add]} { add_files -norecurse -fileset $fs $add }
  if {[llength $rm]}  { remove_files -fileset $fs $rm }
  return [list [llength $add] [llength $rm]]
}

set srcs [lmap s [dict get $b sources] {file join $::mg_root $s}]
foreach s $srcs { if {![file isfile $s]} { error "missing source $s (re-run make_merged_sources.py)" } }
set mems [lmap m [dict get $b mem_init] {file join $::mg_root $m}]
set defs [dict get $b defines]
set inc  [list [file join $::mg_root vectors] [file join $::mg_root sim_riscv include]]

set ss [mg_fileset -srcset dl_merged_src]
set d_src [mg_sync_files $ss [concat $srcs $mems]]
set_property verilog_define $defs $ss
set_property include_dirs $inc $ss
set_property top [dict get $b top] $ss

set cs [mg_fileset -constrset dl_merged_xdc]
mg_sync_files $cs [list [file join $::mg_root [dict get $b xdc]]]

# Revision 9: the source set holds the REAL cpu_tile_noc; tb_merged_closure has 14 lifecycle checks:
# qualified measurement, grant, exact firmware v2 UART, real post-revoke refusal and re-attestation recovery; plus registered
# integration benches on the same merged source set (I-9 integration, I-10 64-byte K-3).
foreach {fs tb} [list dl_merged_real [file join $::mg_root rtl dual_lane merged tb_merged_closure_v10.sv] \
                     dl_i9_integ    [file join $::mg_root NOC_PQATTEST.srcs sim_1 new tb_i9_integ.sv] \
                     dl_i10_d2      [file join $::mg_root NOC_PQATTEST.srcs sim_1 new tb_i10_d2.sv]] {
  set s [mg_fileset -simset $fs]
  set_property SOURCE_SET dl_merged_src $s
  mg_sync_files $s [list $tb]
  set_property top [file rootname [file tail $tb]] $s
  set_property top_lib xil_defaultlib $s
  set_property verilog_define $defs $s
  set_property include_dirs $inc $s
  set_property -name {xsim.simulate.runtime} -value {all} -objects $s
}
puts "merged sets ready: dl_merged_src ([llength $srcs] sources + [llength $mems] firmware image; files added/removed now: $d_src), top [dict get $b top]; dl_merged_xdc; dl_merged_real, dl_i9_integ, dl_i10_d2"

proc merged_sim {{set dl_merged_real}} {
  # set: dl_merged_real (14 checks), dl_i9_integ (13), dl_i10_d2 (12). Makes the set ACTIVE first (include dirs / defines).
  current_fileset -simset [get_filesets $set]
  # xsim.simulate.runtime = all: launch_simulation itself runs the bench to its $finish (RESULT line). No extra "run all":
  # in the GUI simulator a second run after $finish restarts the free-running clock / UART receivers and sim time keeps
  # growing until the 80 ms watchdog (seen 2026-11-07: 10/10 PASS at 1.13 ms, then the extra run had to be interrupted).
  launch_simulation -simset $set
  puts "merged_sim: $set finished (see the RESULT line above; expected RESULT : PASS)"
}

proc merged_build {} {
  set py C:/Users/kalas/AppData/Local/Programs/Python/Python313/python.exe
  puts [exec $py -E [file join $::mg_root scripts merged_release.py] start 2>@1]
}
proc merged_result {} {
  set py C:/Users/kalas/AppData/Local/Programs/Python/Python313/python.exe
  puts [exec $py -E [file join $::mg_root scripts merged_release.py] result 2>@1]
}
