# DIAGNOSTIC ONLY (not evidence): split noc_l2_auth top-level LUTs by the startpoints that feed them.
set dcp [lindex $argv 0]; set outf [lindex $argv 1]
open_checkpoint $dcp
array set istop {}; foreach c [get_cells -filter {REF_NAME =~ LUT*}] { set istop([get_property NAME $c]) 1 }
proc qpins {pat} { return [get_pins -quiet -of [get_cells -quiet -filter "IS_SEQUENTIAL && NAME =~ $pat"] -filter {DIRECTION == OUT}] }
proc fo {pins} { global istop; set s {}; if {![llength $pins]} {return $s}
  foreach c [get_cells -quiet -filter {REF_NAME =~ LUT*} [all_fanout -quiet -flat -only_cells $pins]] {
    set n [get_property NAME $c]; if {[info exists istop($n)]} { lappend s $n } }
  return [lsort -unique $s] }
proc fi {pins} { global istop; set s {}; if {![llength $pins]} {return $s}
  foreach c [get_cells -quiet -filter {REF_NAME =~ LUT*} [all_fanin -quiet -flat -only_cells $pins]] {
    set n [get_property NAME $c]; if {[info exists istop($n)]} { lappend s $n } }
  return [lsort -unique $s] }
proc inter {a b} { set r {}; array set h {}; foreach x $b { set h($x) 1 }; foreach x $a { if {[info exists h($x)]} { lappend r $x } }; return $r }
set fh [open $outf w]
set rb_q    [fo [qpins {rb_reg*}]]
set rn_q    [fo [qpins {rn_reg*}]]
set tag_o   [fo [get_pins -quiet -filter {DIRECTION == OUT && NAME =~ rx_kmac/tag_out*}]]
set rseq_q  [fo [qpins {rx_seq_reg*}]]
set epoch_p [fo [get_ports -quiet boot_epoch*]]
set play_q  [fo [qpins {play_reg*}]]
set ctl_in  [fi [get_pins -quiet -of [get_cells -quiet -filter {IS_SEQUENTIAL && (NAME =~ rs_reg* || NAME =~ FSM*rs* || NAME =~ rejected_count_reg* || NAME =~ accepted_count_reg* || NAME =~ reject_reason_reg* || NAME =~ rx_seq_reg*)}] -filter {DIRECTION == IN && REF_PIN_NAME != C}]]
puts $fh "RX_DECISION_CONE [llength $ctl_in]"
set mac_cmp [inter [inter $ctl_in $tag_o] $rb_q]
puts $fh "MAC_COMPARE (rx_tag vs rb\[rn-4+i\], in decision cone) [llength $mac_cmp]"
puts $fh "  of which also fed by rn (runtime index) [llength [inter $mac_cmp $rn_q]]"
set tagsel [inter [inter $ctl_in $rb_q] $rn_q]
puts $fh "SUPPLIED_TAG_SELECT (rb x rn in decision cone) [llength $tagsel]"
puts $fh "SEQ_COMPARE (rx_seq in decision cone) [llength [inter $ctl_in $rseq_q]]"
puts $fh "EPOCH_COMPARE (boot_epoch in decision cone) [llength [inter $ctl_in $epoch_p]]"
puts $fh "PLAY_READ (play -> ni) [llength [inter [fi [get_pins -quiet -filter {DIRECTION == IN && NAME =~ ni/noc_rx_flit*}]] $play_q]]"
close $fh
