# Overnight run: I-2 `pfc_synth` (pfc_ni_ooc + pfc_mesh_gate)

These two post_format_compat jobs need about 5 GB free RAM. They run alone with
`set_param general.maxThreads 1` (child wrappers `scripts/dual_lane_lowmem_export.tcl` and
`scripts/dual_lane_lowmem_impl.tcl`; recorded as `max_threads=1` in each job's identity).
`pfc_mesh_gate` uses `launch_runs`; its synth_1/impl_1 subprocesses may not inherit the thread limit.

## Preconditions (check all; if any fails, do not run)

1. Fresh restart, with the Claude app, Claude Code, ChatGPT, WhatsApp and browsers closed.
2. Free RAM ≥ 5 GB:
   `[math]::Round((Get-CimInstance Win32_OperatingSystem).FreePhysicalMemory/1MB,2)`
3. No scheduler lock: `Test-Path C:\vivado_verilog_proj\NOC_PQATTEST\automation\dual_lane.lock` → False.
4. No Vivado/XSim running: `Get-Process vivado,xsim*,xelab -ErrorAction SilentlyContinue` → nothing.
5. Preflight passes:
   `& 'C:\Users\kalas\AppData\Local\Programs\Python\Python313\python.exe' scripts\dual_lane.py preflight`
   → `PREFLIGHT: PASS (...)`.

## Command (PowerShell)

```powershell
cd C:\vivado_verilog_proj\NOC_PQATTEST
& 'C:\Users\kalas\AppData\Local\Programs\Python\Python313\python.exe' -u scripts\dual_lane.py run --select pfc_synth
```

It runs `pfc_ni_ooc` (about 5–10 min), then `pfc_mesh_gate` (synthesis + Performance_ExplorePostRoutePhysOpt
implementation, up to 2 h). Do not open the Vivado GUI while it runs, and do not interrupt it. An interrupted job
is INTERRUPTED, never PASS, and must be rerun.

## Reading the result

- The console ends with `EVIDENCE_DIR=...`, `ACTIVE_INCREMENT=I-2`, `INCREMENT_STATUS=...`.
  `INCREMENT_STATUS` stays `NOT_RUN` in a `pfc_synth`-only run, because the other I-2 jobs are "not selected" there.
  Read the two job lines instead.
- `pfc_ni_ooc: PASS_FRESH`: `<EVIDENCE_DIR>\pfc_ni_ooc\metrics.txt` has `LATCHES=0`, `WNS ≥ 0`, `WHS ≥ 0`, and
  `CELLS > 0`. Compare it with I-1 `ni_ooc` (WNS +4.464, WHS +0.263).
- `pfc_mesh_gate: PASS_FRESH`: `<EVIDENCE_DIR>\pfc_mesh_gate\gate_summary.txt` has `VERDICT PASS` and
  `clock period 20.000 ns`. Compare it with I-1 `mesh_gate` (WNS +0.202, WHS +0.047).
- `FAIL` means a timing, latch or route gate failed, and that is a real result. `INVALID` means the evidence is
  unusable (crash, timeout, changed source); rerun it after reading the `reason`.
- Check that each job's `vivado.log` contains `DUAL_LANE_LOWMEM maxThreads=1`.

## Next morning

Open Claude Code and say: "adjudicate the pfc_synth run and finish the I-2 report".

Optional single-identity closeout: every I-2 result was produced under slightly different registry hashes
(each registry regeneration changes every job identity). To have all 36 I-2 jobs on one identity, run
`... dual_lane.py run --select all` instead (about 2–2.5 h, same preconditions). The two synth jobs then run
after the XSim jobs, and only `policy_layer` (Python, no Vivado) follows them.
