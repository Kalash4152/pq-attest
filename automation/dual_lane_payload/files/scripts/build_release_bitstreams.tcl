# build_release_bitstreams.tcl - builds the three P7 bitstreams of NOC_PQATTEST from scratch, one after the other, with the
# REGISTERED S4 flow (docs/decisions/S4_AREA_CONTRACT.md sec. 6): the protected mesh synthesized alone with the release
# settings (S4-F3), the rest with -flatten_hierarchy rebuilt -directive AreaOptimized_high (S4-F1 / F2, A5 KMAC variants),
# then the S1-PNR-DIR implementation and write_bitstream. Each bitstream runs as a batch Vivado child
# (scripts/p7_bitstream_flow.tcl) because project synthesis runs cannot reproduce the mesh split.
#   p7_soc   : SoC-profile accurate area (area of record): pq_p7_soc_core (observation-only exports unconnected), every input
#              from a run-time shift chain, every kept output into a MISR (nothing constant-folds), board MMCM 100 -> 50 MHz.
#   p7_area  : all-exports accurate area: the N-13 secure top (every output incl. debug counters into the MISR), same MMCM.
#   p7_board : demo: board wrapper with fixed demo secrets (attestation on the LEDs); constants trim logic, so its area is
#              LOWER than the real design. Use it to watch the system work, not to quote area.
# Outputs: NOC_PQATTEST.runs_s4/<name>/<top>.bit plus utilization / timing reports; a summary table at the end.
# Usage, Vivado Tcl console (project open or not):  source C:/vivado_verilog_proj/NOC_PQATTEST/scripts/build_release_bitstreams.tcl
#    or batch:  vivado -mode batch -source C:/vivado_verilog_proj/NOC_PQATTEST/scripts/build_release_bitstreams.tcl
# The console is busy until all three finish (about 1.5-2 h). Not registered evidence (scripts/dual_lane.py is).
set root [file normalize [file join [file dirname [info script]] ..]]
foreach f {scripts/p7_bitstream_flow.tcl scripts/p7_bitstream_sources.tcl scripts/s4_mesh_split.tcl synth/s4/noc_mesh_3x2_bb.sv} {
  if {![file isfile [file join $root $f]]} { error "$f missing: install the S4 project update first" }
}
set viv [file join $::env(XILINX_VIVADO) bin vivado.bat]
if {![file isfile $viv]} { set viv C:/xilinx_vivado/Vivado/2024.1/bin/vivado.bat }
set summary {}; set bad 0
foreach n {p7_soc p7_area p7_board} {
  set d [file join $root NOC_PQATTEST.runs_s4 $n]
  file delete -force $d; file mkdir $d
  set log [file join $d vivado.log]
  puts "\n=== bitstream $n (batch Vivado; log $log) ==="
  set here [pwd]; cd $d
  set rc [catch {exec cmd.exe /c [file nativename $viv] -mode batch -nojournal -log [file nativename $log] \
                   -source [file nativename [file join $root scripts p7_bitstream_flow.tcl]] -tclargs $n > [file join $d stdout.txt] 2>@1} e]
  cd $here
  set res [file join $d result.txt]
  if {![file exists $res]} { lappend summary "$n: FAILED (no result; see $log)"; incr bad; continue }
  set f [open $res r]; set line [string trim [read $f]]; close $f
  set wns NA; set whs NA
  regexp {WNS (\S+) ns} $line -> wns; regexp {WHS (\S+) ns} $line -> whs
  if {![string is double -strict $wns] || ![string is double -strict $whs] || $wns < 0 || $whs < 0} {
    append line "   <<< TIMING NOT MET"; incr bad
  }
  lappend summary $line
}
puts "\n==================== NOC_PQATTEST P7 bitstreams (S4 flow) ===================="
foreach l $summary { puts $l }
puts "p7_soc = SoC-profile accurate area (area of record); p7_area = all exports built; p7_board = demo (constants trim area)"
puts [expr {$bad ? "BITSTREAMS: $bad NOT OK (see above)" : "BITSTREAMS: ALL BUILT, TIMING MET"}]
puts "==============================================================================="
set f [open [file join $root reports release_bitstreams_s4.txt] w]; foreach l $summary { puts $f $l }; close $f
