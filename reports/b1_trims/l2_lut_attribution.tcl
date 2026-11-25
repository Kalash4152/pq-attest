# DIAGNOSTIC ONLY (not evidence): attribute noc_l2_auth top-level LUTs to register groups by fan-in cone.
# Input: synth.dcp of b1_ooc_noc_l2_auth (run dual_lane_10_20261020_200142_eb49e57d). Read-only on the checkpoint.
set dcp [lindex $argv 0]; set outf [lindex $argv 1]
open_checkpoint $dcp
# top-level LUTs only (exclude the kmac/ni children)
# get_cells without -hierarchical returns top-level cells only
set top_luts {}; foreach c [get_cells -filter {REF_NAME =~ LUT*}] { lappend top_luts [get_property NAME $c] }
array set istop {}; foreach c $top_luts { set istop($c) 1 }
set fh [open $outf w]
puts $fh "TOP_LEVEL_LUTS [llength $top_luts]"
# endpoint groups: name -> pin list (D/CE/R/S of registers, or input pins of child instances)
proc regpins {pat} { return [get_pins -quiet -of [get_cells -quiet -filter "IS_SEQUENTIAL && NAME =~ $pat"] -filter {DIRECTION == IN && REF_PIN_NAME != C}] }
set groups [list \
  tx_key_q      [regpins {tx_key_q_reg*}] \
  rx_key_q      [regpins {rx_key_q_reg*}] \
  tx_transcript [regpins {tx_transcript_reg*}] \
  rx_transcript [regpins {rx_transcript_reg*}] \
  rb_quarantine [regpins {rb_reg*}] \
  tp_payload    [regpins {tp_reg*}] \
  tx_seq_and_seq_q [concat [regpins {tx_seq_reg*}] [regpins {seq_q_reg*}]] \
  rx_seq        [regpins {rx_seq_reg*}] \
  rx_control_counters [concat [regpins {rs_reg*}] [regpins {FSM*rs*}] [regpins {rejected_count_reg*}] [regpins {accepted_count_reg*}] [regpins {reject_reason_reg*}] [regpins {rc_reg*}] [regpins {rn_reg*}] [regpins {play_reg*}] [regpins {frame_bad_reg*}]] \
  tx_control    [concat [regpins {ts_reg*}] [regpins {FSM*ts*}] [regpins {pn_reg*}] [regpins {fill_reg*}] [regpins {send_fill_reg*}] [regpins {extension_reg*}] [regpins {head_q_reg*}] [regpins {dest_q_reg*}] [regpins {msg_q_reg*}] [regpins {ctl_q_reg*}] [regpins {epoch_q_reg*}] [regpins {tx_msg_len_reg*}] [regpins {rx_msg_len_reg*}]] \
  ni_inputs     [get_pins -quiet -filter {DIRECTION == IN && NAME =~ ni/*}] \
  kmac_inputs   [get_pins -quiet -filter {DIRECTION == IN && (NAME =~ tx_kmac/* || NAME =~ rx_kmac/*)}] \
  output_ports  [get_ports -quiet -filter {DIRECTION == OUT}] ]
array set member {}
foreach {g pins} $groups {
  if {![llength $pins]} { puts $fh "GROUP $g endpoints 0"; continue }
  set cone [get_cells -quiet -filter {REF_NAME =~ LUT*} [all_fanin -quiet -flat -only_cells $pins]]
  set n 0
  foreach c $cone { set c [get_property NAME $c]; if {[info exists istop($c)]} { lappend member($c) $g; incr n } }
  puts $fh "GROUP $g endpoints [llength $pins] cone_luts $n"
}
array set excl {}; set shared 0; set none 0
foreach c $top_luts {
  if {![info exists member($c)]} { incr none; continue }
  set gs [lsort -unique $member($c)]
  if {[llength $gs] == 1} { incr excl([lindex $gs 0]) } else { incr shared }
}
foreach g [lsort [array names excl]] { puts $fh "EXCLUSIVE $g $excl($g)" }
puts $fh "SHARED_BY_2PLUS $shared"
puts $fh "UNATTRIBUTED $none"
close $fh
