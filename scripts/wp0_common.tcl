# WP-0 shared code. Vivado 2024.1 / Windows PowerShell 5.1.
# Fresh temporary simulation filesets; no source-file swaps and no cached SDBs.
namespace eval wp0 {
    variable script_dir [file dirname [file normalize [info script]]]
    variable build_timeout 1200
    variable sim_timeout 600
}
proc wp0::read_text {path} {
    set f [open $path r]; set text [read $f]; close $f; return $text
}
proc wp0::write_text {path text} {
    set f [open $path w]; fconfigure $f -encoding utf-8 -translation lf
    puts -nonewline $f $text; close $f
}
proc wp0::read_binary {path} {
    set f [open $path rb]; set text [read $f]; close $f; return $text
}
proc wp0::write_binary {path text} {
    set f [open $path wb]; puts -nonewline $f $text; close $f
}
proc wp0::ps {args} {
    variable script_dir
    return [exec powershell.exe -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass \
        -File [file join $script_dir wp0_support.ps1] {*}$args]
}
proc wp0::sha256 {path} {
    set hash [string trim [ps -Mode Hash -Path $path]]
    if {![regexp {^[0-9a-f]{64}$} $hash]} { error "Invalid SHA256 response for $path" }
    return $hash
}
proc wp0::unique_replace {text old new} {
    set at [string first $old $text]
    if {$at < 0 || [string first $old $text [expr {$at + [string length $old]}]] >= 0} {
        error "Mutation anchor must appear exactly once: $old"
    }
    return [string replace $text $at [expr {$at + [string length $old] - 1}] $new]
}
proc wp0::make_mutant {baseline kind} {
    if {[regexp {MUT[-_]N6} $baseline]} { error "Baseline already contains an N-6 mutation marker" }
    switch -- $kind {
        a {
            return [unique_replace $baseline \
                {assign eject_rd = out_valid_local & out_ready_local;} \
                {assign eject_rd = out_valid_local; // MUT-N6A: ignores LOCAL ready}]
        }
        b {
            return [unique_replace $baseline \
                {assign credit_out[PORT_WEST ] = {credit_west_vc2,  credit_west_vc1,  credit_west_vc0 };} \
                {assign credit_out[PORT_WEST ] = {credit_west_vc2,  credit_west_vc1,  1'b0 }; // MUT-N6B: loses WEST VC0 credit}]
        }
        c {
            set nl [expr {[string first "\r\n" $baseline] >= 0 ? "\r\n" : "\n"}]
            set old {else                                     in_ready_local = 1'b1;}
            return [unique_replace $baseline $old \
                "$old${nl}        in_ready_local = 1'b1; // MUT-N6C: ignores LOCAL FIFO full"]
        }
        default { error "Unknown mutation $kind" }
    }
}
proc wp0::numbers {text name} {
    set pattern [format {(?in)^\s*%s\s*[:=]\s*([0-9]+)\s*$} $name]
    set matches [regexp -all -inline $pattern $text]
    if {[llength $matches] != 2} { error "Expected exactly one $name count" }
    return [lindex $matches 1]
}
proc wp0::result {text} {
    set matches [regexp -all -inline {(?in)^\s*RESULT\s*[:=]\s*(PASS|FAIL)([^\r\n]*)$} $text]
    if {[llength $matches] != 3} { error "Expected exactly one RESULT banner" }
    return [string toupper [lindex $matches 1]]
}
proc wp0::bad_diagnostics {text} {
    return [regexp -nocase -line \
        {^\s*(ERROR:|Error:|FATAL:|Fatal:|\[FAIL\]|\[FATAL\])|assertion[^\r\n]*(failed|failure)|RESULT\s*[:=]\s*FAIL|global timeout} $text]
}
proc wp0::judge_pass {text count negative {config {}}} {
    if {[bad_diagnostics $text]} { error "Unexpected error/assertion/failure/timeout in simulation" }
    if {[result $text] ne "PASS"} { error "RESULT is not PASS" }
    # Validate the compiled configuration BEFORE the configuration-dependent count.
    if {[dict size $config]} {
        set lines [regexp -all -inline {(?n)^CONFIG\s*:\s*([^\r\n]+)$} $text]
        if {[llength $lines] != 2} { error "Expected one CONFIG banner" }
        set got [lindex $lines 1]
        dict for {key value} $config {
            set pattern [format {(^|\s)%s=%s(\s|$)} $key $value]
            if {![regexp $pattern $got]} { error "Wrong compiled configuration: expected $key=$value; got={$got}" }
        }
    }
    if {[numbers $text CHECKS] != $count || [numbers $text ERRORS] != 0} {
        error "Expected $count checks and 0 errors"
    }
    set marker {(?n)^N0 EXPECTED-FAIL CONFIRMED \(deterministic: locks held, competitors blocked\)\s*$}
    set found [regexp -all $marker $text]
    if {$negative && $found != 1} { error "N0 requires exactly one EXPECTED-FAIL CONFIRMED marker" }
    if {!$negative && $found != 0} { error "Unexpected N0 marker in watchdog-enabled run" }
    return PASS
}
proc wp0::judge_mutant {text kind} {
    # Compile/elaborate/process failures have already been rejected. A timeout
    # by itself is never a mutation kill: require the mutation's directed oracle.
    if {[result $text] ne "FAIL"} { error "Mutant $kind survived (or has no valid FAIL result)" }
    switch -- $kind {
        a { set oracle {(?n)^\[FAIL\] T11 (head flit held stable|no R1 LOCAL dequeue while ready=0)} }
        b { set oracle {(?n)^\[FAIL\] T5 (credit propagates back to R0 EAST|R0 EAST has credit again)} }
        c { set oracle {(?n)^\[FAIL\] T13 (in_ready_local=0|13th flit NOT taken while full)} }
        default { error "Unknown mutation $kind" }
    }
    if {![regexp $oracle $text]} { error "Mutant $kind failed without its targeted oracle; INVALID, not killed" }
    if {[regexp -nocase {global timeout|N-6 STRESS TIMEOUT} $text] && $kind ne "b"} {
        error "Unexpected TB timeout for mutant $kind"
    }
    return KILLED
}
proc wp0::walk {root suffix} {
    set out {}
    foreach p [glob -nocomplain -directory $root *] {
        if {[file isdirectory $p]} { set out [concat $out [walk $p $suffix]] } \
        elseif {[string match "*$suffix" [file tail $p]]} { lappend out $p }
    }
    return $out
}
proc wp0::prepare {kind} {
    variable script_dir
    if {$::tcl_platform(platform) ne "windows"} { error "Run this package in Windows Vivado 2024.1" }
    if {[llength [current_sim -quiet]]} { error "A simulation is open. Close it before starting WP-0." }
    set project [current_project]
    if {$project eq ""} { error "Open NOC_PQATTEST.xpr first" }
    if {![string match "2024.1*" [version -short]]} { error "Reference runner requires Vivado 2024.1" }
    set root [file normalize [get_property DIRECTORY $project]]
    if {![file isfile [file join $root NOC_PQATTEST.xpr]]} { error "Unexpected project root: $root" }
    set sim [get_filesets sim_1]
    if {[llength $sim] != 1} { error "Expected sim_1" }
    set opts [get_property xsim.compile.xvlog.more_options $sim]
    foreach setobj [list $sim [get_filesets sources_1]] {
        set defs [get_property verilog_define $setobj]
        if {[regexp {\m(PQ_MAC_ON|N81_W|N81_WDE|N81_RUNS)\M} "$opts $defs"]} {
            error "Clear inherited N81/PQ_MAC_ON defines before running the matrix"
        }
    }
    if {[string trim [get_property generic $sim]] ne "" || \
        [string trim [get_property xsim.elaborate.xelab.more_options $sim]] ne ""} {
        error "Clear inherited generic/elaboration overrides first; record them in the baseline"
    }
    set id "[clock format [clock seconds] -format %Y%m%d_%H%M%S]_[pid]_[format %08x [expr {[clock clicks] & 0x7fffffff}]]"
    set out [file join $root logs "wp0_${kind}_$id"]
    if {[file exists $out]} { error "Evidence directory already exists" }
    file mkdir $out
    set router [file join $root NOC_PQATTEST.srcs sources_1 new noc_router.sv]
    set ctx [dict create root $root project $project sim $sim id $id out $out router $router \
        router_hash [sha256 $router] opts $opts active_sim [current_fileset -simset] \
        target [get_property target_simulator $project] enabled {}]
    write_text [file join $out session.txt] "STATE=INCOMPLETE\nKIND=$kind\nVIVADO=[version -short]\nROOT=$root\nROUTER_SHA256=[dict get $ctx router_hash]\n"
    # Obtain a complete Git/source baseline, including XPR and script backups.
    write_text [file join $out baseline_location.txt] "[ps -Mode Baseline -ProjectRoot $root]\n"
    puts "WP-0 evidence: $out"
    return $ctx
}
proc wp0::enable_sources {ctx} {
    set saved {}
    set code [catch {
        foreach leaf {noc_network_interface.sv noc_addr_decoder.sv} {
            set path [file join [dict get $ctx root] NOC_PQATTEST.srcs sources_1 new $leaf]
            set objs [get_files -quiet $path]
            if {[llength $objs] != 1} { error "Expected one project source object for $leaf" }
            set obj [lindex $objs 0]
            dict set saved $obj [get_property is_enabled $obj]
            set_property is_enabled true $obj
        }
        set_property target_simulator XSim [dict get $ctx project]
    } msg options]
    if {$code} {
        dict for {obj value} $saved { set_property is_enabled $value $obj }
        set_property target_simulator [dict get $ctx target] [dict get $ctx project]
        return -options $options $msg
    }
    dict set ctx enabled $saved
    return $ctx
}
proc wp0::restore {ctx} {
    set failures {}
    dict for {obj value} [dict get $ctx enabled] {
        if {[catch {set_property is_enabled $value $obj} e]} { lappend failures $e }
    }
    if {[catch {current_fileset -simset [dict get $ctx active_sim]} e]} { lappend failures $e }
    if {[catch {set_property target_simulator [dict get $ctx target] [dict get $ctx project]} e]} { lappend failures $e }
    if {[catch {set now [sha256 [dict get $ctx router]]} e]} { lappend failures $e } \
    elseif {$now ne [dict get $ctx router_hash]} { lappend failures "LIVE ROUTER CHANGED; inspect concurrent edits, no source file was replaced by this runner" }
    if {[llength $failures]} { error "RESTORATION/BASELINE CHECK FAILED: $failures" }
}
proc wp0::router_required_for_top {top} {
    # NI-only unit/integration tops do not elaborate the router, so Vivado may
    # legitimately omit noc_router.sv from their generated *_vlog.prj files.
    # The N-6 and full-system tops instantiate the router and must include it.
    return [expr {[lsearch -exact {tb_n6_two_tile_stress tb_noc_n81} $top] >= 0}]
}
proc wp0::compile_sources {dir router replacement require_router} {
    set files {}; set replaced 0
    set prjs [glob -nocomplain -directory $dir *_vlog.prj]
    if {![llength $prjs]} { error "Missing generated Verilog compile project" }
    foreach prj $prjs {
        set text [read_text $prj]
        if {$replacement ne "" && [string first "\"$router\"" $text] >= 0} {
            set text [unique_replace $text "\"$router\"" "\"$replacement\""]
            write_text $prj $text
            incr replaced
        }
        foreach {whole path} [regexp -all -inline {"([^"\r\n]+)"} $text] {
            if {[file isfile $path]} {
                if {[file pathtype $path] ne "absolute"} { error "Source is not absolute: $path" }
                if {[file size $path] == 0} { error "Zero-byte source in compile project: $path" }
                lappend files [file normalize $path]
            } elseif {[regexp -nocase {\.(sv|v|svh|vh)$} $path]} { error "Missing generated source: $path" }
        }
        lappend files $prj
    }
    if {$replacement ne "" && $replaced != 1} { error "Router redirection must replace exactly one compile entry" }
    set actual [expr {$replacement eq "" ? $router : $replacement}]
    if {($require_router || $replacement ne "") && [lsearch -exact $files $actual] < 0} {
        error "Required router missing from compile project"
    }
    return [lsort -unique $files]
}
proc wp0::manifest {files dest} {
    write_text "${dest}.paths" "[join $files \n]\n"
    ps -Mode Manifest -InputList "${dest}.paths" -OutputPath $dest
    if {![file isfile $dest] || [file size $dest] == 0} { error "Missing manifest: $dest" }
    return [read_text $dest]
}
proc wp0::run_bat {dir step timeout} {
    set bat [file join $dir "$step.bat"]
    if {![file isfile $bat]} { error "Missing $step.bat" }
    ps -Mode RunBat -Path $bat -WorkingDirectory $dir \
        -LogPrefix [file join $dir "process_$step"] -TimeoutSeconds $timeout
}
proc wp0::process_diagnostics {dir step} {
    set text ""
    foreach suffix {stdout stderr} {
        set path [file join $dir "process_${step}.${suffix}.log"]
        if {![file isfile $path]} { error "Missing captured $step $suffix" }
        append text [read_text $path] "\n"
    }
    return $text
}
proc wp0::inject_defines {dir defs} {
    # Insert -d "NAME[=VAL]" into the single generated 'call xvlog' line, then read back.
    set bat [file join $dir compile.bat]
    set text [read_binary $bat]
    if {[regexp {N81_|PQ_MAC_ON} $text]} { error "Generated compile.bat already carries a matrix define; INVALID" }
    foreach prj [glob -nocomplain -directory $dir *.prj] {
        if {[regexp {N81_|PQ_MAC_ON} [read_text $prj]]} { error "Generated prj already carries a matrix define; INVALID" }
    }
    set n [regexp -all -line {^call xvlog\s[^\r\n]*\s-prj\s} $text]
    if {$n != 1} { error "Expected exactly one 'call xvlog ... -prj' line in compile.bat, found $n" }
    set ins ""
    foreach def $defs {
        if {![regexp {^[A-Za-z_][A-Za-z0-9_]*(=[A-Za-z0-9_]+)?$} $def]} { error "Unsafe define token: $def" }
        append ins " -d \"$def\""
    }
    if {$ins ne ""} {
        regsub -line {^(call xvlog\s[^\r\n]*?)(\s-prj\s)} $text "\\1$ins\\2" text
        write_binary $bat $text
    }
    set line [lindex [regexp -inline -line {^call xvlog\s[^\r\n]*} [read_binary $bat]] 0]
    set applied {}
    foreach {all d} [regexp -all -inline {\s-d\s+"([^"]+)"} $line] { lappend applied $d }
    if {[lsort $applied] ne [lsort $defs]} { error "Define injection mismatch: requested={$defs} applied={$applied}" }
    return $applied
}
proc wp0::run_job {ctx ordinal top tag defs count negative config {mutant ""}} {
    variable build_timeout; variable sim_timeout; variable script_dir
    set fs "wp0_[dict get $ctx id]_j$ordinal"
    set root [dict get $ctx root]
    set dir [file join $root "[get_property NAME [dict get $ctx project]].sim" $fs behav xsim]
    set evidence [file join [dict get $ctx out] $tag]
    file mkdir $evidence
    if {[file exists $dir] || [llength [get_filesets -quiet $fs]]} { error "Run workspace already exists; refusing stale evidence" }
    set made 0
    set code [catch {
        create_fileset -simset -clone_properties [dict get $ctx sim] $fs
        set made 1
        # Clone file membership and explicit per-file enable/type/library policy.
        foreach old [get_files -of_objects [dict get $ctx sim]] {
            set path [get_property NAME $old]
            add_files -fileset $fs -norecurse $path
            set new [get_files -of_objects [get_filesets $fs] $path]
            foreach prop {file_type library is_enabled used_in_simulation} {
                set_property $prop [get_property $prop $old] $new
            }
        }
        foreach relative {sim_1/new/tb_ni_n81.sv sim_1/new/tb_noc_n81.sv sim_1/new/ni_tb.sv sources_1/new/tb6_1.sv} {
            set path [file join $root NOC_PQATTEST.srcs $relative]
            if {![file isfile $path]} { error "Missing required TB $path" }
            set obj [get_files -quiet -of_objects [get_filesets $fs] $path]
            if {![llength $obj]} { add_files -fileset $fs -norecurse $path; set obj [get_files -of_objects [get_filesets $fs] $path] }
            set_property is_enabled true $obj
        }
        set_property top $top [get_filesets $fs]
        set_property top_lib xil_defaultlib [get_filesets $fs]
        # Macro transport (2026-10-01, proven on this PC): Vivado's -scripts_only export of
        # the cloned simset emitted NEITHER xsim.compile.xvlog.more_options NOR verilog_define
        # (runs 194105, 200154: compile.bat/prj carried no define). So per-job macros are
        # injected into the generated compile.bat below, QUOTED: cmd.exe splits an unquoted
        # NAME=VAL at '=' -> empty macro (xvlog VRFC 10-4982 at tb_ni_n81.sv:30).
        set opts [dict get $ctx opts]
        set_property -name {xsim.compile.xvlog.more_options} -value [string trim $opts] \
            -objects [get_filesets $fs]
        update_compile_order -fileset $fs
        puts "WP-0 $tag: fresh export, defines={$defs}"
        launch_simulation -simset $fs -mode behavioral -scripts_only -absolute_path
        if {![file isdirectory $dir]} { error "Vivado did not generate the expected run directory: $dir" }
        if {[llength [walk $dir .sdb]]} { error "Cached SDBs exist before compilation; INVALID" }
        set appliedDefs [inject_defines $dir $defs]
        set batch [file join $dir "${top}.tcl"]
        if {![file isfile $batch]} { error "Missing generated simulation Tcl batch" }
        set simulateBat [read_text [file join $dir simulate.bat]]
        set batchPattern [format {(?n)^call\s+xsim\s+[^\r\n]*-tclbatch\s+"?%s\.tcl"?(\s|$)} $top]
        if {![regexp $batchPattern $simulateBat]} {
            error "Generated simulator command does not use the expected bounded Tcl batch"
        }
        # Bound simulation time and exit after run returns. No GUI run-all hang.
        write_text $batch "run 25ms\nquit\n"
        set routerRequired [router_required_for_top $top]
        if {$mutant ne "" && !$routerRequired} { error "Mutation job uses a top that does not require noc_router" }
        set files [compile_sources $dir [dict get $ctx router] $mutant $routerRequired]
        set files [concat $files [list $batch [file join $script_dir wp0_common.tcl] \
            [file join $script_dir wp0_support.ps1]]]
        foreach step {compile elaborate simulate} { lappend files [file join $dir "$step.bat"] }
        set before [manifest $files [file join $evidence sources_before.tsv]]
        write_text [file join $evidence config.txt] "TOP=$top\nDEFINES_REQUESTED=$defs\nDEFINES_APPLIED=$appliedDefs\nCOMPILE_OPTIONS=$opts\nSIMULATION_LIMIT=25ms\nWORKSPACE=$dir\n"
        set t0 [clock seconds]
        run_bat $dir compile $build_timeout
        if {[bad_diagnostics [process_diagnostics $dir compile]]} { error "Compile process reports an error" }
        set compileLog [file join $dir compile.log]
        if {![file isfile $compileLog] || [file size $compileLog] == 0} { error "Missing compile log" }
        if {[bad_diagnostics [read_text $compileLog]]} { error "Compile log contains errors" }
        set requiredSdbs [list $top noc_network_interface]
        if {$routerRequired} { lappend requiredSdbs noc_router }
        foreach module $requiredSdbs {
            set sdb [file join $dir xsim.dir xil_defaultlib "${module}.sdb"]
            if {![file isfile $sdb] || [file size $sdb] == 0 || [file mtime $sdb] < $t0} {
                error "Missing/stale $module.sdb; INVALID"
            }
        }
        run_bat $dir elaborate $build_timeout
        if {[bad_diagnostics [process_diagnostics $dir elaborate]]} { error "Elaboration process reports an error" }
        set elaborateLog [file join $dir elaborate.log]
        if {![file isfile $elaborateLog] || [file size $elaborateLog] == 0} { error "Missing elaboration log" }
        if {[bad_diagnostics [read_text $elaborateLog]]} { error "Elaboration log contains errors" }
        set kernel [file join $dir xsim.dir "${top}_behav" xsimk.exe]
        if {![file isfile $kernel] || [file size $kernel] == 0 || [file mtime $kernel] < $t0} {
            error "Missing/stale elaborated kernel; INVALID"
        }
        # Infra retry (2026-10-01): xsim.exe intermittently dies with EXCEPTION_ACCESS_VIOLATION
        # AFTER \$finish (1 crash, then 0/19 on the same snapshot). A crashed attempt NEVER counts:
        # its evidence is preserved and simulate.bat is re-run ONCE; only an exit-0 attempt is judged.
        set simAttempt 1
        if {[catch {run_bat $dir simulate $sim_timeout} simErr]} {
            set crash [glob -nocomplain -directory $dir hs_err*.log]
            set slog [file join $dir simulate.log]
            set finished [expr {[file isfile $slog] && [string match {*$finish called*} [read_text $slog]]}]
            if {![string match PROCESS_EXIT_* $simErr] || ![llength $crash] || !$finished} { error $simErr }
            set keep [file join $evidence sim_crash_attempt1]
            file mkdir $keep
            foreach f [concat $crash [glob -nocomplain -directory $dir hs_err*.dmp process_simulate.* simulate.log]] {
                file copy -force $f $keep
            }
            foreach f [glob -nocomplain -directory $dir hs_err*] { file delete -force $f }
            file delete -force $slog
            write_text [file join $keep reason.txt] "$simErr\nRETRY=1 (crash after \$finish; attempt 1 not counted)\n"
            puts "WP-0 $tag: xsim crashed after \$finish (attempt 1 preserved); re-running simulate once"
            set simAttempt 2
            run_bat $dir simulate $sim_timeout
            if {[llength [glob -nocomplain -directory $dir hs_err*.log]]} { error "xsim crashed again on retry; INVALID" }
        }
        set processText [process_diagnostics $dir simulate]
        if {$mutant eq "" && [bad_diagnostics $processText]} { error "Simulation process reports an unexpected error" }
        set log [file join $dir simulate.log]
        if {![file isfile $log] || [file size $log] == 0 || [file mtime $log] < $t0} { error "Missing/stale simulation log" }
        set after [manifest $files [file join $evidence sources_after.tsv]]
        if {$before ne $after} { error "Sources or generated scripts changed during the job; INVALID" }
        set text [read_text $log]
        if {$mutant eq ""} { set verdict [judge_pass $text $count $negative $config] } \
        else { set verdict [judge_mutant $text [string index $tag end]] }
        write_text [file join $evidence verdict.txt] "$verdict\nSIM_ATTEMPTS=$simAttempt\n"
    } message options]
    # Preserve compile/elaboration/process logs even when a step fails.
    set cleanupErrors {}
    if {[file isdirectory $dir]} {
        if {[catch {file copy $dir [file join $evidence generated]} e]} { lappend cleanupErrors "Evidence copy: $e" }
    }
    if {$made} {
        if {[catch {current_fileset -simset [dict get $ctx active_sim]} e]} { lappend cleanupErrors $e }
        if {[catch {delete_fileset $fs} e]} { lappend cleanupErrors $e }
    }
    if {$code} {
        write_text [file join $evidence verdict.txt] "INVALID_OR_FAIL\n$message\n"
        if {[llength $cleanupErrors]} { append message "\nCleanup: $cleanupErrors" }
        return -options $options $message
    }
    if {[llength $cleanupErrors]} { error "Job cleanup failed: $cleanupErrors" }
    puts "WP-0 $tag: $verdict (evidence: $evidence)"
    return $verdict
}
proc wp0::matrix {} {
    return {
        {tb_ni_n81 n81_ni_m0w16 {} 115 0 {W 16 MAC_FLITS 0}}
        {tb_ni_n81 n81_ni_m0w1 {N81_W=1} 114 0 {W 1 MAC_FLITS 0}}
        {tb_ni_n81 n81_ni_m1w16 {PQ_MAC_ON} 113 0 {W 16 MAC_FLITS 4}}
        {tb_ni_n81 n81_ni_m1w1 {PQ_MAC_ON N81_W=1} 112 0 {W 1 MAC_FLITS 4}}
        {tb_noc_ni n81_nitb {} 161 0 {}}
        {tb_n6_two_tile_stress n81_n6 {} 126 0 {}}
        {tb_noc_n81 n81_sys_m0w16 {} 97 0 {W 16 WDE 1 RUNS 7 MAC_FLITS 0}}
        {tb_noc_n81 n81_sys_m0w64 {N81_W=64 N81_RUNS=1} 43 0 {W 64 WDE 1 RUNS 1 MAC_FLITS 0}}
        {tb_noc_n81 n81_sys_m0n0 {N81_WDE=0 N81_RUNS=8} 19 1 {W 16 WDE 0 RUNS 8 MAC_FLITS 0}}
        {tb_noc_n81 n81_sys_m1w16 {PQ_MAC_ON N81_RUNS=1} 43 0 {W 16 WDE 1 RUNS 1 MAC_FLITS 4}}
        {tb_noc_n81 n81_sys_m1n0 {PQ_MAC_ON N81_WDE=0 N81_RUNS=8} 19 1 {W 16 WDE 0 RUNS 8 MAC_FLITS 4}}
    }
}
proc wp0::n81_main {} {
    set ctx [prepare n81]
    set passed 0
    set code [catch {
        set ctx [enable_sources $ctx]
        foreach row [matrix] {
            lassign $row top tag defs count negative config
            run_job $ctx [expr {$passed+1}] $top $tag $defs $count $negative $config
            incr passed
        }
    } message options]
    set restoreCode [catch {restore $ctx} restoreMessage]
    set summary "JOBS_PASSED=$passed/11\nLIVE_ROUTER_ORIGINAL_SHA256=[dict get $ctx router_hash]\n"
    if {$code || $restoreCode} {
        append summary "SESSION=FAIL_OR_INCOMPLETE\nERROR=$message\nRESTORE_ERROR=$restoreMessage\n"
        write_text [file join [dict get $ctx out] summary.txt] $summary
        error "N-8.1 NOT CLOSED. $passed/11 valid passes. $message $restoreMessage"
    }
    append summary "SESSION=PASS\nLIVE_ROUTER_UNCHANGED=YES\n"
    write_text [file join [dict get $ctx out] summary.txt] $summary
    puts "N-8.1 XSim: 11/11 valid PASS. Evidence: [dict get $ctx out]"
}
proc wp0::n6_main {} {
    set ctx [prepare n6_mutation]
    set baseline [read_binary [dict get $ctx router]]
    set snapshot [file join [dict get $ctx out] current_router_snapshot.sv]
    write_binary $snapshot $baseline
    if {[sha256 $snapshot] ne [dict get $ctx router_hash]} { error "Snapshot hash mismatch" }
    set killed 0
    set code [catch {
        set ctx [enable_sources $ctx]
        # A campaign cannot be trusted without a passing current-baseline control.
        run_job $ctx 0 tb_n6_two_tile_stress n6_control_before {} 126 0 {}
        foreach kind {a b c} {
            set path [file join [dict get $ctx out] "noc_router_mut_${kind}.sv"]
            write_binary $path [make_mutant $baseline $kind]
            run_job $ctx [expr {$killed+1}] tb_n6_two_tile_stress "n6_mut_$kind" {} 0 0 {} $path
            incr killed
        }
        run_job $ctx 4 tb_n6_two_tile_stress n6_control_after {} 126 0 {}
    } message options]
    set restoreCode [catch {restore $ctx} restoreMessage]
    if {$code || $restoreCode} {
        write_text [file join [dict get $ctx out] summary.txt] "SESSION=FAIL_OR_INCOMPLETE\nKILLED=$killed/3\nERROR=$message\nRESTORE_ERROR=$restoreMessage\n"
        error "N-6 mutation campaign NOT ACCEPTED. $message $restoreMessage"
    }
    write_text [file join [dict get $ctx out] summary.txt] "SESSION=PASS\nKILLED=3/3\nCONTROLS=2/2\nLIVE_ROUTER_UNCHANGED=YES\nROUTER_SHA256=[dict get $ctx router_hash]\n"
    puts "N-6 mutations: 3/3 targeted kills, both controls PASS, live router unchanged. Evidence: [dict get $ctx out]"
}
