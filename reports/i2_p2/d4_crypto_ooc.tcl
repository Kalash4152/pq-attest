# d4_crypto_ooc.tcl - PQ-3 (D4) crypto out-of-context synthesis.
#
# Prepared in I-2 prep track P2 and staged under reports/i2_p2/, because the
# installed scripts/d4_crypto_ooc.tcl is hash-pinned by
# automation/dual_lane_payload/update_manifest.json; install options are in
# reports/i2_p2/P2_OOC_PREP.md. Install this file under scripts/ (the
# launcher mode below sources scripts/dual_lane_common.tcl next to it).
#
# Three modes, chosen from how the file is entered:
#   1. Launcher (no job-file argument, e.g. `source scripts/d4_crypto_ooc.tcl`
#      in a Vivado Tcl console). Same as the installed two-line script: it
#      starts the Python scheduler with --select ooc. It NEVER synthesises in
#      the GUI or in any open project.
#   2. Child. Only the scheduler starts it, as
#        vivado -mode batch -source d4_crypto_ooc.tcl -tclargs <out>/job.tcl
#      when a job carries "child_script": this file. job.tcl defines
#      KIND OUT PART TOP SOURCES INCLUDES GENERICS XDC (dual_lane.py execute()).
#   3. Library (::d4ooc_library_only set before sourcing). Defines procedures
#      only, for the no-Vivado parser self-test in reports/i2_p2/.
#
# Child flow: fresh in-memory project, part from job.tcl (xc7a100tcsg324-1),
# read_xdc BEFORE synth (20 ns clock, 5 ns in/out budgets, as ni_ooc),
# synth_design -mode out_of_context -flatten_hierarchy none, then reports and
# metrics.txt in the KEY=VALUE format dual_lane.py parses (LATCHES WNS WHS
# CELLS are read by the scheduler; the other keys are recorded as observed).
#
# Fail-closed rules inside the child (Vivado exits non-zero -> job INVALID):
#   - wrong Vivado version, open project, KIND != ooc, unknown TOP, no XDC;
#   - clock clk missing or period != 20.000 ns after synthesis;
#   - any expected child engine instance missing, of the wrong module, or
#     with zero leaf cells (hierarchy trimmed);
#   - check_timing reports any unconstrained endpoint/port, or the report
#     cannot be parsed (a WNS from a partly constrained design proves nothing).
# A negative WNS/WHS or a latch is NOT an error here: metrics.txt is written
# and the scheduler records FAIL (GateFailure), as PQ-3 requires.
#
# Latency is NOT measured here. MEASURED_LATENCY_CYCLES is a placeholder that
# names the simulation that will supply it; synthesis never fills it.

namespace eval d4ooc {
  # Expected engine instances per top: {hierarchical_path module_prefix}.
  # Paths verified against the RTL instance names (P2_OOC_PREP.md section 2).
  # Only engines that contain logic are gated; pure-wiring sub-steps of a
  # Keccak round (u_rho, u_pi) may legally hold zero cells and are listed
  # in `informational` instead.
  variable keccak_kmac {
    {u_kmac kmac128}
    {u_kmac/u_kmac_absorb kmac_absorb}
    {u_kmac/u_kmac_encode kmac_encode}
    {u_kmac/u_keccak keccak_f1600}
    {u_kmac/u_keccak/u_keccak_round keccak_round}
  }
  variable keccak_sha3 {
    {u_sha3 sha3_256}
    {u_sha3/u_sha3_pad sha3_pad}
    {u_sha3/u_sha3_absorb sha3_absorb}
    {u_sha3/u_keccak_f1600 keccak_f1600}
    {u_sha3/u_keccak_f1600/u_keccak_round keccak_round}
  }
  variable round_steps {u_theta u_rho u_pi u_chi u_iota}

  proc prefixed {prefix rows} {
    set out {}
    foreach r $rows { lappend out [list "$prefix[lindex $r 0]" [lindex $r 1]] }
    return $out
  }

  proc controller_rows {prefix} {
    variable keccak_kmac
    variable keccak_sha3
    set rows [list [list "${prefix}u_pq_kdf" pq_kdf]]
    set rows [concat $rows [prefixed "${prefix}u_pq_kdf/" $keccak_kmac]]
    lappend rows [list "${prefix}u_pq_measurement" pq_measurement]
    set rows [concat $rows [prefixed "${prefix}u_pq_measurement/" $keccak_sha3]]
    lappend rows [list "${prefix}u_pq_attestation_tag" pq_attestation_tag]
    set rows [concat $rows [prefixed "${prefix}u_pq_attestation_tag/" $keccak_kmac]]
    return $rows
  }

  proc expected_children {top} {
    variable keccak_kmac
    variable keccak_sha3
    switch -exact -- $top {
      pq_kdf                    { return $keccak_kmac }
      pq_attestation_tag        { return $keccak_kmac }
      pq_measurement            { return $keccak_sha3 }
      pq_attestation_controller { return [controller_rows ""] }
      pq_attest_endpoint        {
        # PROVISIONAL until PQ-2 freezes rtl/dual_lane/pq_attest_endpoint.sv
        # (instance name `controller` at its line 60 today).
        return [concat [list {controller pq_attestation_controller}] [controller_rows "controller/"]]
      }
      default { error "d4_crypto_ooc: no child-instance expectation for top '$top'" }
    }
  }

  # Keccak round paths, reported but not gated.
  proc informational {top} {
    variable round_steps
    set rounds {}
    foreach r [expected_children $top] {
      if {[lindex $r 1] eq "keccak_round"} { lappend rounds [lindex $r 0] }
    }
    set out {}
    foreach p $rounds { foreach s $round_steps { lappend out "$p/$s" } }
    return $out
  }

  # Where the measured latency will come from. Simulation only.
  proc latency_source {top} {
    switch -exact -- $top {
      pq_attestation_controller {
        return "s8_golden simulate.log lines 'LATENCY Gnn cycles=N' (tb_stg_8_golden await_done; counted from the posedge after start falls, so start-to-done = N+1 edges)"
      }
      pq_kdf - pq_measurement - pq_attestation_tag {
        return "not yet a registered dual-lane job: needs a sim job that prints start-to-done cycles for this engine (pq_kdf_tb / pq_measurement_tb / pqattest_tb count cycles but print them only on timeout)"
      }
      pq_attest_endpoint {
        return "PQ-2 pq_endpoint job (tb to be frozen in PQ-2)"
      }
      default { return "unknown" }
    }
  }

  # ---- Report parsers (pure Tcl; self-tested without Vivado) ----

  # Post-synthesis report_utilization row, e.g. "| Slice LUTs*  |  412 | ...".
  proc util_row {s label} {
    set re "\\|\\s*[string map {( \\( ) \\) . \\. * \\*} $label]\\*?\\s*\\|\\s*(\[0-9.\]+)\\s*\\|"
    if {[regexp $re $s -> n]} { return $n }
    return NA
  }

  # Design Timing Summary row (same parser as n25_gate.tcl, proven in I-1).
  proc parse_dts {s} {
    set lines [split $s "\n"]
    set i [lsearch -regexp $lines {^\s*WNS\(ns\)}]
    if {$i < 0} { error "Design Timing Summary not found" }
    set l ""
    for {set k [expr {$i+1}]} {$k < [llength $lines]} {incr k} {
      set l [string trim [lindex $lines $k]]
      if {[regexp {^-?[0-9]} $l]} { break }
    }
    set v [regexp -all -inline {\S+} $l]
    if {[llength $v] < 12} { error "DTS row malformed: $l" }
    return [dict create WNS [lindex $v 0] TNS [lindex $v 1] TNS_FAIL [lindex $v 2] TNS_TOT [lindex $v 3] \
                        WHS [lindex $v 4] THS [lindex $v 5] THS_FAIL [lindex $v 6] THS_TOT [lindex $v 7] \
                        WPWS [lindex $v 8] TPWS [lindex $v 9] TPWS_FAIL [lindex $v 10]]
  }

  # "N. checking <name> (<count>)" lines of check_timing (verbose summary).
  proc parse_check_timing {s} {
    set d [dict create]
    foreach {all name n} [regexp -all -inline {[0-9]+\. checking (\w+) \(([0-9]+)\)} $s] {
      dict set d $name $n
    }
    if {![dict size $d]} { error "check_timing section not found" }
    return $d
  }

  # Checks that leave an endpoint or port untimed. Their sum is the
  # unconstrained count; each must be 0 for WNS/WHS to mean anything.
  variable unconstrained_checks {no_clock unconstrained_internal_endpoints no_input_delay
                                 no_output_delay partial_input_delay partial_output_delay}

  proc unconstrained_total {ct} {
    variable unconstrained_checks
    set total 0
    foreach k $unconstrained_checks {
      if {[dict exists $ct $k]} { incr total [dict get $ct $k] }
    }
    return $total
  }

  # report_methodology summary: "Violations found: N" plus the rule table.
  proc parse_methodology {s} {
    set total NA
    regexp {Violations found:\s*([0-9]+)} $s -> total
    set rules {}
    foreach {all id sev n} [regexp -all -line -inline {^\|\s*([A-Z][A-Z0-9]*-[0-9]+)\s*\|\s*([A-Za-z ]+?)\s*\|[^|\n]*\|\s*([0-9]+)\s*\|\s*$} $s] {
      lappend rules "$id/$sev:$n"
    }
    if {![llength $rules]} { set rules none }
    return [list $total [join $rules ,]]
  }

  proc kv {fh key value} {
    if {[string first "\n" $value] >= 0} { error "metrics value for $key spans lines" }
    puts $fh "$key=$value"
  }
}

# ---------------------------------------------------------------------------
# Child body
# ---------------------------------------------------------------------------
proc d4ooc::count {filter} { return [llength [get_cells -quiet -hier -filter $filter]] }

proc d4ooc::check_children {top out} {
  set rows {}
  set fails {}
  foreach r [expected_children $top] {
    lassign $r path module
    set c [get_cells -quiet $path]
    if {[llength $c] != 1} {
      lappend fails "missing $path"
      lappend rows [list $path $module MISSING - - - -]
      continue
    }
    set ref [get_property REF_NAME $c]
    set orig ""
    catch { set orig [get_property ORIG_REF_NAME $c] }
    set prim [get_property IS_PRIMITIVE $c]
    set inside "NAME =~ \"$path/*\""
    set leaf [count "IS_PRIMITIVE && $inside"]
    set lut  [count "IS_PRIMITIVE && REF_NAME =~ LUT* && $inside"]
    set ff   [count "IS_PRIMITIVE && REF_NAME =~ FD* && $inside"]
    set dsp  [count "IS_PRIMITIVE && REF_NAME =~ DSP48* && $inside"]
    set state PRESENT
    if {$prim} {
      set state NOT_HIERARCHICAL; lappend fails "$path is a primitive"
    } elseif {![string match "${module}*" $ref] && ![string match "${module}*" $orig]} {
      set state WRONG_MODULE; lappend fails "$path ref $ref/$orig expected $module"
    } elseif {$leaf == 0} {
      set state EMPTY; lappend fails "$path has 0 leaf cells (trimmed)"
    }
    lappend rows [list $path $module $state $ref $leaf $lut $ff $dsp]
  }
  set info {}
  foreach p [informational $top] {
    set c [get_cells -quiet $p]
    lappend info [list $p [expr {[llength $c] ? [count "IS_PRIMITIVE && NAME =~ \"$p/*\""] : "absent"}]]
  }
  set fh [open [file join $out hier_check.rpt] w]
  puts $fh "# D4 child-engine check, top $top (gated rows)"
  puts $fh "# path module state ref leaf_cells luts ffs dsps"
  foreach r $rows { puts $fh [join $r " "] }
  puts $fh "# informational Keccak round sub-steps (not gated; wiring-only steps may be empty or absorbed)"
  foreach r $info { puts $fh [join $r " "] }
  puts $fh "HIER_CHECK=[expr {[llength $fails] ? "FAIL $fails" : "PASS"}]"
  close $fh
  return [list $rows $fails]
}

proc d4ooc::child {} {
  foreach v {KIND OUT PART TOP SOURCES GENERICS} {
    if {![info exists ::$v]} { error "d4_crypto_ooc: job.tcl did not define $v" }
  }
  set out $::OUT
  set top $::TOP
  if {![string match 2024.1* [version -short]]} { error "Wrong Vivado version [version -short]" }
  if {[llength [get_projects -quiet]]} { error "Child must start without a project" }
  if {$::KIND ne "ooc"} { error "d4_crypto_ooc child handles kind ooc only, got $::KIND" }
  if {$::PART ne "xc7a100tcsg324-1"} { error "Wrong part $::PART" }
  expected_children $top ;# errors for an unknown top before any tool work
  if {![info exists ::XDC] || ![file isfile $::XDC]} {
    error "d4_crypto_ooc: job has no constraints file (job field 'constraints')"
  }

  create_project -in_memory -part $::PART
  read_verilog -sv $::SOURCES
  read_xdc $::XDC
  set synth_opts [list -mode out_of_context -flatten_hierarchy none]
  synth_design -top $top -part $::PART {*}$synth_opts {*}$::GENERICS

  set clk [get_clocks -quiet clk]
  if {[llength $clk] != 1} { error "Clock clk not defined after synthesis" }
  set period [get_property PERIOD $clk]
  if {$period != 20.000} { error "Wrong clock target $period ns" }

  # Reports (same set as the ni_ooc pattern, plus hierarchy depth and DRC count).
  set us [report_utilization -return_string]
  set fh [open [file join $out utilization.rpt] w]; puts $fh $us; close $fh
  report_utilization -hierarchical -hierarchical_depth 8 -file [file join $out util_hier.rpt]
  set ts [report_timing_summary -check_timing_verbose -report_unconstrained -max_paths 20 -return_string]
  set fh [open [file join $out timing_summary.rpt] w]; puts $fh $ts; close $fh
  report_timing -max_paths 10 -nworst 1 -file [file join $out worst_paths.rpt]
  report_timing -hold -max_paths 10 -nworst 1 -file [file join $out worst_hold_paths.rpt]
  report_timing -from [all_inputs] -to [all_outputs] -max_paths 10 -file [file join $out in_to_out.rpt]
  set ms [report_methodology -return_string]
  set fh [open [file join $out methodology.rpt] w]; puts $fh $ms; close $fh
  set drc_err NA
  if {![catch {report_drc -name d4_drc -file [file join $out drc.rpt]}]} {
    if {[catch {set drc_err [llength [get_drc_violations -quiet -name d4_drc -filter {SEVERITY == Error}]]}]} { set drc_err NA }
  }
  write_checkpoint -force [file join $out synth.dcp]

  set dts [parse_dts $ts]
  set ct  [parse_check_timing $ts]
  set unc [unconstrained_total $ct]
  lassign [parse_methodology $ms] meth_total meth_rules
  lassign [check_children $top $out] child_rows child_fails

  set wp [lindex [get_timing_paths -setup -max_paths 1 -nworst 1] 0]
  set hp [lindex [get_timing_paths -hold -max_paths 1 -nworst 1] 0]
  if {![llength $wp] || ![llength $hp]} { error "No timed setup/hold path in $top: nothing to report" }
  set wns   [get_property SLACK $wp]
  set whs   [get_property SLACK $hp]
  set wfrom [get_property NAME [get_property STARTPOINT_PIN $wp]]
  set wto   [get_property NAME [get_property ENDPOINT_PIN $wp]]
  set wlev  [get_property LOGIC_LEVELS $wp]
  set wdata [get_property DATAPATH_DELAY $wp]

  set ct_list {}
  dict for {k n} $ct { lappend ct_list "$k:$n" }

  set fh [open [file join $out metrics.txt] w]
  # --- identical leading block to ni_ooc (scheduler-parsed keys included) ---
  puts $fh "SCOPE=OOC\nCLOCK_NS=[format %g $period]\nINPUT_BUDGET_NS=5\nOUTPUT_BUDGET_NS=5"
  kv $fh LATCHES [count {IS_PRIMITIVE && REF_NAME =~ LD*}]
  kv $fh WNS $wns
  kv $fh WHS $whs
  kv $fh CELLS [llength [get_cells -hier]]
  # --- provenance ---
  kv $fh TOP $top
  kv $fh PART $::PART
  kv $fh VIVADO [version -short]
  kv $fh SYNTH_OPTIONS [join [concat $synth_opts $::GENERICS] " "]
  kv $fh CONSTRAINTS [file tail $::XDC]
  # --- utilization (report_utilization rows; NA if a row is absent) ---
  kv $fh LUT       [util_row $us {Slice LUTs}]
  kv $fh LUT_LOGIC [util_row $us {LUT as Logic}]
  kv $fh LUTRAM    [util_row $us {LUT as Distributed RAM}]
  kv $fh SRL       [util_row $us {LUT as Shift Register}]
  kv $fh FF        [util_row $us {Slice Registers}]
  kv $fh BRAM      [util_row $us {Block RAM Tile}]
  kv $fh DSP       [util_row $us {DSPs}]
  # --- cross-check by primitive count ---
  kv $fh CELL_LUT    [count {IS_PRIMITIVE && REF_NAME =~ LUT*}]
  kv $fh CELL_FF     [count {IS_PRIMITIVE && REF_NAME =~ FD*}]
  kv $fh CELL_LUTRAM [count {IS_PRIMITIVE && REF_NAME =~ RAM* && REF_NAME !~ RAMB*}]
  kv $fh CELL_SRL    [count {IS_PRIMITIVE && REF_NAME =~ SRL*}]
  kv $fh CELL_RAMB36 [count {IS_PRIMITIVE && (REF_NAME =~ RAMB36* || REF_NAME =~ FIFO36*)}]
  kv $fh CELL_RAMB18 [count {IS_PRIMITIVE && (REF_NAME =~ RAMB18* || REF_NAME =~ FIFO18*)}]
  kv $fh CELL_DSP    [count {IS_PRIMITIVE && REF_NAME =~ DSP48*}]
  # --- timing ---
  kv $fh TNS [dict get $dts TNS]
  kv $fh TNS_FAILING_ENDPOINTS [dict get $dts TNS_FAIL]
  kv $fh TIMED_ENDPOINTS [dict get $dts TNS_TOT]
  kv $fh THS [dict get $dts THS]
  kv $fh THS_FAILING_ENDPOINTS [dict get $dts THS_FAIL]
  kv $fh WPWS [dict get $dts WPWS]
  kv $fh DTS_WNS [dict get $dts WNS]
  kv $fh DTS_WHS [dict get $dts WHS]
  kv $fh WNS_FROM $wfrom
  kv $fh WNS_TO $wto
  kv $fh WNS_LOGIC_LEVELS $wlev
  kv $fh WNS_DATAPATH_NS $wdata
  kv $fh CHECK_TIMING [join $ct_list ,]
  kv $fh UNCONSTRAINED_ENDPOINTS $unc
  # --- methodology / DRC ---
  kv $fh METHODOLOGY_VIOLATIONS $meth_total
  kv $fh METHODOLOGY_RULES $meth_rules
  kv $fh DRC_ERRORS $drc_err
  # --- child engines (see hier_check.rpt) ---
  kv $fh CHILD_ENGINES [llength $child_rows]
  foreach r $child_rows {
    lassign $r path module state ref leaf lut ff dsp
    kv $fh "CHILD:$path" "$state module:$module ref:$ref leaf:$leaf lut:$lut ff:$ff dsp:$dsp"
  }
  kv $fh HIER_CHECK [expr {[llength $child_fails] ? "FAIL" : "PASS"}]
  # --- latency: simulation only, never synthesis ---
  kv $fh MEASURED_LATENCY_CYCLES PENDING_SIMULATION
  kv $fh LATENCY_SOURCE [latency_source $top]
  close $fh

  set problems $child_fails
  if {$unc != 0} { lappend problems "unconstrained endpoints/ports: [join $ct_list ,]" }
  if {[llength $problems]} {
    error "D4 OOC evidence invalid for $top: [join $problems {; }] (metrics.txt and hier_check.rpt written)"
  }
  close_project
}

# ---------------------------------------------------------------------------
# Mode dispatch
# ---------------------------------------------------------------------------
if {[info exists ::d4ooc_library_only]} {
  return
} elseif {[info exists ::argv] && [llength $::argv] == 1 && [string match -nocase *job.tcl [lindex $::argv 0]]} {
  source [lindex $::argv 0]
  d4ooc::child
} else {
  source [file join [file dirname [file normalize [info script]]] dual_lane_common.tcl]
  dual_lane::run ooc
}
