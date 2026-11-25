# D7 / N7 functional regression -- final XSim gate.
#
# Purpose:
#   Re-check the D7 LINK_PIPE change plus the legacy router/FIFO regressions.
#   N-7 pipe0 MUST be selected with a valueless xvlog -d compile-time define; do not use
#   xelab -generic_top for TB_LINK_PIPE in this project.
#
# Required results:
#   n7_pipe1 : TB_LINK_PIPE=1, Checks=1756, GuardChecks=111, Errors=0, RESULT=PASS
#   n7_pipe0 : TB_LINK_PIPE=0, Checks=1762, GuardChecks=111, Errors=0, RESULT=PASS
#   n35_m8   : Checks=47,   Errors=0, RESULT=PASS
#   n6       : Checks=126,  Errors=0, RESULT=PASS
#   n2_tb1   : OVERALL PASS (0 failures)
#
# Usage (Vivado Tcl console, NOC_PQATTEST.xpr open, no simulation running):
#   set RTAG n81
#   source C:/vivado_verilog_proj/NOC_PQATTEST/scripts/d7_regression.tcl

set R    C:/vivado_verilog_proj/NOC_PQATTEST
set XDIR $R/NOC_PQATTEST.sim/sim_1/behav/xsim
set DATE [clock format [clock seconds] -format %Y-%m-%d]

# Optional log tag supplied by caller; default keeps legacy naming.
if {![info exists RTAG]} { set RTAG d7 }

if {[llength [current_sim -quiet]]} {
    error "A simulation is already open. close_sim before starting D7/N7 regression."
}

set SIM [get_filesets sim_1]
if {[llength $SIM] != 1} { error "Expected exactly one sim_1 fileset" }

# Save every project property this script changes so no regression configuration
# leaks into later work.
set CO              {xsim.compile.xvlog.more_options}
set CO_SAVED        [get_property $CO $SIM]
if {[regexp {N7_PIPE0|N7_LINK_PIPE} $CO_SAVED]} {
    error "Baseline xvlog.more_options already contains an N7 matrix define; clean sim_1 before running"
}
set RUNTIME_SAVED   [get_property xsim.simulate.runtime $SIM]
set TOP_SAVED       [get_property top $SIM]
set TOP_LIB_SAVED   [get_property top_lib $SIM]

file mkdir $R/logs
update_compile_order -fileset sources_1
update_compile_order -fileset sim_1

proc d7_read_text {path} {
    set f [open $path r]
    set t [read $f]
    close $f
    return $t
}

proc d7_expect_count {text label expected tag} {
    set pattern [format {(?in)^\s*%s\s*=\s*([0-9]+)\s*$} $label]
    set m [regexp -all -inline $pattern $text]
    if {[llength $m] != 2} {
        error "$tag: expected exactly one '$label = <count>' line"
    }
    set got [lindex $m 1]
    if {$got != $expected} {
        error "$tag: $label mismatch: expected $expected, got $got"
    }
}

proc d7_expect_result_pass {text tag} {
    set m [regexp -all -inline {(?in)^\s*RESULT\s*=\s*(PASS|FAIL)\s*$} $text]
    if {[llength $m] != 2} {
        error "$tag: expected exactly one RESULT line"
    }
    if {[string toupper [lindex $m 1]] ne "PASS"} {
        error "$tag: RESULT is not PASS"
    }
}

proc d7_expect_n7_config {text expected tag} {
    set m [regexp -all -inline {(?in)^\s*N-7 CONFIG:\s*TB_LINK_PIPE\s*=\s*([01])[^\r\n]*$} $text]
    if {[llength $m] != 2} {
        error "$tag: expected exactly one N-7 CONFIG banner"
    }
    set got [lindex $m 1]
    if {$got != $expected} {
        error "$tag: wrong compiled N-7 configuration: expected TB_LINK_PIPE=$expected, got $got"
    }
}

proc d7_expect_tb1_pass {text tag} {
    if {![regexp -nocase -line {^\s*OVERALL\s*:\s*PASS\s*\(0 failures\)\s*$} $text]} {
        error "$tag: TB1 OVERALL PASS (0 failures) banner missing"
    }
}

proc d7_run {top tag defs judgeKind expectedChecks {expectedPipe {}}} {
    global R XDIR DATE SIM CO CO_SAVED RTAG

    puts "\n######## $tag ($top) defines={$defs} ########"

    set_property top $top $SIM
    set_property top_lib xil_defaultlib $SIM

    # Build this job's xvlog options from the untouched project baseline.
    # Define tokens are valueless identifiers. This deliberately avoids the
    # Windows/cmd.exe NAME=VALUE quoting failure seen in the prior pipe0 run.
    set opts $CO_SAVED
    foreach d $defs {
        if {![regexp {^[A-Za-z_][A-Za-z0-9_]*$} $d]} {
            error "$tag: unsafe define token: $d"
        }
        append opts " -d $d"
    }

    # Explicit -name/-value/-objects prevents a leading '-d' value from being
    # parsed as a Tcl set_property option when the saved baseline is empty.
    set_property -name $CO -value [string trim $opts] -objects $SIM
    puts "$tag: xvlog.more_options={[get_property $CO $SIM]}"

    # Force a fresh behavioral build after changing top/defines.
    catch {reset_simulation -simset sim_1 -mode behavioral}
    set_property -name {xsim.simulate.runtime} -value {1ns} -objects $SIM

    set t0 [clock seconds]
    if {[catch {launch_simulation} launchErr]} {
        error "$tag: launch_simulation failed: $launchErr"
    }

    # Define-transport proof. The historical failure mode was a requested -d
    # silently disappearing before xvlog. For any define-bearing job, refuse to
    # run unless the generated compiler script contains every requested token.
    if {[llength $defs]} {
        set cbat [file join $XDIR compile.bat]
        if {![file isfile $cbat]} {
            catch {close_sim}
            error "$tag: generated compile.bat missing"
        }
        set ctext [d7_read_text $cbat]
        foreach d $defs {
            if {[string first $d $ctext] < 0} {
                catch {close_sim}
                error "$tag: define '$d' missing from generated compile.bat; INVALID"
            }
        }
        puts "$tag: generated compile.bat contains requested defines"
    }

    # Recompile proof: top SDB must be fresh for this job.
    set sdb [file join $XDIR xsim.dir xil_defaultlib "${top}.sdb"]
    if {![file isfile $sdb] || [file mtime $sdb] < $t0} {
        catch {close_sim}
        error "$tag: ${top}.sdb missing/stale; RESULT INVALID"
    }
    puts "$tag: RECOMPILED ${top}.sdb @ [clock format [file mtime $sdb]]"

    if {[catch {run all} runErr]} {
        catch {close_sim}
        error "$tag: run all failed: $runErr"
    }

    catch {close_sim}

    set simlog [file join $XDIR simulate.log]
    if {![file isfile $simlog] || [file size $simlog] == 0} {
        error "$tag: simulate.log missing/empty"
    }

    set outlog [file join $R logs "${tag}_${RTAG}_${DATE}.log"]
    file copy -force $simlog $outlog
    puts "saved $outlog"

    set text [d7_read_text $outlog]

    switch -- $judgeKind {
        n7 {
            d7_expect_n7_config $text $expectedPipe $tag
            d7_expect_count $text Checks $expectedChecks $tag
            d7_expect_count $text GuardChecks 111 $tag
            d7_expect_count $text Errors 0 $tag
            d7_expect_count $text InjBlocked 0 $tag
            d7_expect_result_pass $text $tag
        }
        count {
            d7_expect_count $text Checks $expectedChecks $tag
            d7_expect_count $text Errors 0 $tag
            d7_expect_result_pass $text $tag
        }
        tb1 {
            d7_expect_tb1_pass $text $tag
        }
        default {
            error "$tag: unknown judge kind '$judgeKind'"
        }
    }

    puts "$tag: PASS"
}

set REG_CODE [catch {
    # Default/synthesized D7 path.
    d7_run tb_noc_mesh_n7          n7_pipe1 {}               n7    1756 1

    # Pre-D7 compatibility path. Compile-time define only; NO -generic_top.
    d7_run tb_noc_mesh_n7          n7_pipe0 {N7_PIPE0}        n7    1762 0

    d7_run tb_noc_router_m9_credit n35_m8   {}               count 47
    d7_run tb_n6_two_tile_stress   n6       {}               count 126
    d7_run tb_noc_stage2           n2_tb1   {}               tb1   0
} REG_MSG REG_OPTS]

# Always restore the original project simulation state.
set RESTORE_ERRORS {}
if {[llength [current_sim -quiet]]} {
    if {[catch {close_sim} e]} { lappend RESTORE_ERRORS "close_sim: $e" }
}
if {[catch {set_property -name $CO -value $CO_SAVED -objects $SIM} e]} {
    lappend RESTORE_ERRORS "compile options: $e"
}
if {[catch {set_property -name {xsim.simulate.runtime} -value $RUNTIME_SAVED -objects $SIM} e]} {
    lappend RESTORE_ERRORS "runtime: $e"
}
if {$TOP_SAVED ne ""} {
    if {[catch {set_property top $TOP_SAVED $SIM} e]} { lappend RESTORE_ERRORS "top: $e" }
}
if {$TOP_LIB_SAVED ne ""} {
    if {[catch {set_property top_lib $TOP_LIB_SAVED $SIM} e]} { lappend RESTORE_ERRORS "top_lib: $e" }
}

if {$REG_CODE} {
    puts "\nD7/N7 REGRESSION: FAIL/INCOMPLETE"
    puts "ERROR: $REG_MSG"
    if {[llength $RESTORE_ERRORS]} { puts "RESTORE_ERRORS: $RESTORE_ERRORS" }
    return -options $REG_OPTS $REG_MSG
}

if {[llength $RESTORE_ERRORS]} {
    error "D7/N7 regression tests passed but project-state restoration failed: $RESTORE_ERRORS"
}

puts "\n============================================================"
puts "D7/N7 REGRESSION: PASS"
puts "  n7_pipe1 : 1756 / 0, TB_LINK_PIPE=1"
puts "  n7_pipe0 : 1762 / 0, TB_LINK_PIPE=0 via -d N7_PIPE0"
puts "  M8       : 47 / 0"
puts "  N6       : 126 / 0"
puts "  TB1      : OVERALL PASS (0 failures)"
puts "============================================================"
