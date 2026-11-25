#!/bin/bash
# Applies scripts/update_NOC_PQATTEST_xpr.tcl to NOC_PQATTEST.xpr in ONE write, without the GUI.
# Why: sourcing the update in the GUI rewrites the 0.5-0.8 MB xpr ~250 times and hit "Error writing the XML file"
# (Project 1-202) twice on 2026-11-01, leaving a half-updated project. This script:
#   1. refuses to run while any vivado.exe is running (the project must be closed);
#   2. backs up NOC_PQATTEST.xpr to NOC_PQATTEST.xpr.bak_<timestamp>;
#   3. builds the update on a copy under vivado_sim/_xprinstall (gitignored), with the runs' gen_run.xml copied so the
#      existing runs keep their state;
#   4. restores the two location-dependent lines (project Path, BoardPartRepoPaths) from the original;
#   5. checks that, outside dl_* filesets and the *_p7* runs, the result equals the original (else stops);
#   6. copies it over NOC_PQATTEST.xpr only if the original is unchanged since step 2.
# Usage (Git Bash, from the repo root, Vivado closed):  bash scripts/install_xpr_update.sh
set -euo pipefail
R=$(cd "$(dirname "$0")/.." && pwd); T=$R/vivado_sim/_xprinstall
PY=/c/Users/kalas/AppData/Local/Programs/Python/Python313/python.exe
VIV=/c/xilinx_vivado/Vivado/2024.1/bin
if tasklist | grep -qi "vivado.exe"; then echo "STOP: close Vivado first (vivado.exe is running)"; exit 1; fi
B=$R/NOC_PQATTEST.xpr.bak_$(date +%Y%m%d_%H%M%S); cp -p "$R/NOC_PQATTEST.xpr" "$B"; H0=$(sha256sum < "$R/NOC_PQATTEST.xpr")
echo "backup: $B"
rm -rf "$T"; mkdir -p "$T/proj/scripts" "$T/proj/NOC_PQATTEST.runs"
cp "$B" "$T/proj/NOC_PQATTEST.xpr"
cp -r "$R/NOC_PQATTEST.srcs" "$R/rtl" "$R/sim" "$R/vectors" "$R/synth" "$T/proj/"
cp "$R/scripts/update_NOC_PQATTEST_xpr.tcl" "$R/scripts/d4_crypto_ooc.xdc" "$T/proj/scripts/"
for d in "$R"/NOC_PQATTEST.runs/*/; do n=$(basename "$d"); mkdir -p "$T/proj/NOC_PQATTEST.runs/$n"; [ -f "$d/gen_run.xml" ] && cp "$d/gen_run.xml" "$T/proj/NOC_PQATTEST.runs/$n/"; done
cat > "$T/apply.tcl" <<'EOF'
open_project [lindex $argv 0]
source [file join [get_property DIRECTORY [current_project]] scripts update_NOC_PQATTEST_xpr.tcl]
puts "APPLIED runs=[get_runs] dl_sim=[llength [get_filesets -quiet -filter {FILESET_TYPE == SimulationSrcs} dl_*]]"
close_project
EOF
(cd "$T" && PATH="$VIV:$PATH" vivado.bat -mode batch -nojournal -nolog -source apply.tcl -tclargs "$(cygpath -m "$T/proj/NOC_PQATTEST.xpr")" > apply.out 2>&1)
grep -E "^(APPLIED|NOC_PQATTEST:|ERROR)|while executing" "$T/apply.out" || true
grep -q "^APPLIED" "$T/apply.out" || { echo "STOP: update did not complete (see $T/apply.out)"; exit 1; }
"$PY" - "$B" "$T/proj/NOC_PQATTEST.xpr" "$T/final.xpr" <<'EOF'
import sys, re, difflib
b = open(sys.argv[1], encoding='utf-8', newline='').read(); x = open(sys.argv[2], encoding='utf-8', newline='').read()
# location-dependent lines, plus the production runs' and the active simset's lines (a batch re-open rewrites their
# State / ActiveSimSet; the user's production runs and selection must stay exactly as they were)
for pat in [r'<Project Product="Vivado"[^\n]*', r'<Option Name="BoardPartRepoPaths"[^\n]*', r'<Option Name="ActiveSimSet"[^\n]*',
            r'<Run Id="synth_1"[^\n]*', r'<Run Id="impl_1"[^\n]*', r'<Run Id="impl_pe"[^\n]*']:
    ob, ox = re.search(pat, b), re.search(pat, x)
    if ob and ox: x = x.replace(ox.group(0), ob.group(0), 1)
if '_xprinstall' in x: sys.exit('STOP: copy path left in result')
def core(t):
    t = re.sub(r'<FileSet Name="dl_.*?</FileSet>', '', t, flags=re.S)
    t = re.sub(r'<Run Id="(synth|impl)_p7[a-z_]*".*?</Run>', '', t, flags=re.S)
    # auto incremental-synthesis checkpoints of the P7 runs (utils_1/imports/<run>/...dcp) go with their runs (S4: the P7
    # runs are deleted, not recreated); utils_1 entries of any other run are still compared
    t = re.sub(r'<File Path="\$PSRCDIR/utils_1/imports/(synth|impl)_p7[a-z_]*/[^"]*">.*?</File>', '', t, flags=re.S)
    return [l.strip() for l in t.splitlines() if l.strip()]
d = [l for l in difflib.unified_diff(core(b), core(x), lineterm='', n=0) if l[:1] in '+-' and not l.startswith(('+++', '---'))]
if d: print('\n'.join(d[:20])); sys.exit(f'STOP: {len(d)} differences outside the dl_*/p7 additions')
open(sys.argv[3], 'w', encoding='utf-8', newline='').write(x)
print('CHECK ok: only dl_* filesets and p7 runs differ')
EOF
if tasklist | grep -qi "vivado.exe"; then echo "STOP: Vivado was started meanwhile; result left in $T/final.xpr"; exit 1; fi
[ "$(sha256sum < "$R/NOC_PQATTEST.xpr")" = "$H0" ] || { echo "STOP: NOC_PQATTEST.xpr changed meanwhile; result left in $T/final.xpr"; exit 1; }
cp "$T/final.xpr" "$R/NOC_PQATTEST.xpr"
echo "INSTALLED: $(grep -c 'Type="SimulationSrcs"' "$R/NOC_PQATTEST.xpr") simsets; runs: $(grep -o '<Run Id="[a-z_0-9]*"' "$R/NOC_PQATTEST.xpr" | sed 's/<Run Id=//' | tr '\n' ' ')"
rm -rf "$T"
