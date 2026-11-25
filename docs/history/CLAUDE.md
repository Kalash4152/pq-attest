# NOC_PQATTEST — rules for Claude Code

Owner: Kalash Bheda. Address the owner as Kalash. Be concise and conclusion-first. Open every
reply with a one-line pre-output check (what was read live).

## Ground truth
- Repo C:\vivado_verilog_proj\NOC_PQATTEST, branch noc/credit-integration.
- Tools: Vivado/XSim 2024.1 at C:/xilinx_vivado/Vivado/2024.1 (reference simulator),
  Python C:/Users/kalas/AppData/Local/Programs/Python/Python313/python.exe, PowerShell, git.
  No Verilator on Windows. No board/hardware access.
- Part xc7a100tcsg324-1, single clock, 20 ns. No clock, pin or CDC changes.
- Authoritative docs: docs/CODEX_INSTRUCTIONS_R4_FINAL_2026-10-08.md (plan),
  docs/DECISION_REGISTER.md, docs/decisions/*.md, docs/STATUS.md, reports/I1_COMPLETION_20261009.md,
  docs/CLAUDE_CODE_RESUME_2026-10-19.md (review, parallel setup, remaining work).
- Teammate Python reference (governs PQ semantics): Pq_Attest_final.zip
  SHA-256 047bb5a981050f11a572a60e850f7c7511ff5d636f7903c6a8d239891003c6a0,
  extracted read-only at software/pq_attest_final/. TILE_KEY_BYTES=32 is the system profile.

## Never
- Write the protected files: sources_1/new/{noc_router.sv, noc_network_interface.sv, NOC_PKG.sv,
  pqattest_stg7.sv, pq_attest_protocol.sv, allocator.sv, noc_mesh_3x2.sv, SHA3_*.sv, pq_kdf.sv,
  pq_measurement.sv}, sim_1/new/{tb_ni_n81.sv, tb_noc_n81.sv}, software/pq_attest_final/**, the ZIP.
  Secure changes go only in rtl/dual_lane/ variants with explicit source lists.
- Put a variant and its production original in one source list (duplicate-name preflight).
- Change an expected count, weaken a check, edit a reference vector, or count a timeout as a kill/pass.
- Claim a simulation, synthesis or timing result that was not run. Separate: implemented /
  XSim-simulated / reference-checked / mutation-tested. Formal and hardware are always NO.
- git reset --hard, git clean, force-push, or restore from zip snapshots.
- Kill a running Vivado/XSim job you did not start.

## Always
- Evidence only through: python scripts/dual_lane.py run --select <increment>  (or the Tcl
  launcher scripts/run_dual_lane_10.tcl). States: PASS_FRESH or identity-matched PASS_REUSED.
- Freeze each new job's expected counts in scripts/dual_lane_jobs.json BEFORE its first run.
- Wire/format changes only via a new M-F1 revision doc written BEFORE the dependent RTL.
- Run scripts/test_dual_lane.py (it includes the controlled-diagnostics tests) before any
  registry change.
- Commit per logical group: git -c user.name="Kalash Bheda" -c user.email="kkalash.bheda@gmail.com"
  with the trailer lines the session provides.
- Evidence directories are committed text-only (logs, json, txt, rpt, tsv, csv, md, tcl, bat, prj, sv);
  binary build products (.dcp, .exe, .obj, .sdb, .wdb, ...) stay on disk with their recorded hashes.
- At most 2 concurrent Vivado/XSim processes (16 GB RAM). Synthesis/implementation jobs run alone.
- At every increment boundary write the gate report and commit; if the gate is PASS, continue automatically
  (I-n+1 starts only after I-n PASS). Gate reports start with: commit, accepted/fresh/reused counts, measured LUT/WNS,
  open blockers, next dependency; HARDWARE_VALIDATED=NO, SOC_INTEGRATION_COMPLETE=NO, FORMAL_PROOF=NO.
- HARD STOP and wait for Kalash on: any FAIL needing a design or contract change; measured full-subsystem LUT > 47,550;
  any new security-scope question; any change to a signed bound, wire format, device, clock or budget; the N-13 timing FAIL.
- Batch registry/identity changes: at most one regeneration per logical group, never mid-batch.
- Judge/automation hardening needs negative tests; historical runs are re-evaluated only by explicit re-adjudication
  into new records, never by relabelling. (Kalash addendum 2026-10-21, DECISION_REGISTER "Stopping rules".)


## Revision-10 checkpoint - 14 Nov 2026

Read docs/handoff/REV10_QUOTA_HANDOFF_20261114.md and reports/R10_EXECUTION_CHECKPOINT_20261113.md before resuming.
G3:31/31 fresh; G4:two accepted builds39962LUT/29187FF/WNS+0.182/WHS+0.007. Configuration payloads identical;
whole-file hashes differ only at five timestamp-header bytes (comparison report proves this).
At22:01: GUI-copy recovery _r10g2 still running, not yet PASS. Finalizer PID12828 is only a launch-time pointer;
read _r10g2/finalize_status.json and actual PIDs before acting. Do not duplicate release/GUI jobs.
Conservative whole-plan estimate80%: GUI-copy/main GUI, board and final freeze/tag/reports/site remain.
Later READY_FOR_OWNER/gate records supersede this in-progress snapshot. Main XPR and CRLF-only docs remain uncommitted.
Hardware/formal/SOC flags NO; no RC2 tag before owner board record.
User prefers very brief updates and a pre-output check only about one in five replies. Agent cannot see weeklyquota
percentage or detect2%; this checkpoint is proactive. Full evidence/rules/remaining actions are in the handoff.

## Latest checkpoint superseding the running-GUI snapshot above

G3/G4/isolated-G5 ALL PASS as of14 Nov22:06 IST, G5 commit90f57570. No new unattended build required.
31 fresh qualification jobs; two release builds and GUI copy all39962LUT/29187FF/WNS+0.182/WHS+0.007.
GUI-copy payload identical to both releases; complete bitfile timestamp hashes intentionally differ.
Read reports/R10_READY_FOR_OWNER_20261114.md and docs/handoff/REV10_QUOTA_HANDOFF_20261114.md.
Estimated whole-plan84%: owner MAIN-project GUI4%, board7%, final freeze/tag/reports/site5% remain. Not95%/not hardwarePASS.
Next is Kalash's main Vivado command/Generate Bitstream and exact-image board observations; only afterward phase7.
Hardware/formal/SOC remainNO. Do not tagRC2 or update site as hardware-validated before the owner record.

## Actual MAIN build now RUNNING (latest continue,14 Nov22:10)
Supersedes the earlier no-build-needed pointer: owner asked continue, so the agent is completing the main build too.
Read _r10main/status.json and reports/NEXT_STEP.md. PID12728/session83647 are launch-time pointers; verify live.
Do not duplicate the run or commit the main .xpr. Prior image/checkpoint backed up under _r10main/previous_main_build.
After MAIN PASS, only owner board observations and phase7 remain; hardware/formal/SOC flags stayNO.

## MAIN-project gate now PASS
The actual main project was updated and built, not just the copy. Read reports/R10_MAIN_PROJECT_GATE_20261114.md.
Main bit SHA256 8d951af86feb9085aee7f7316e231ba091d6969cb6f4b2133f8d7a96b7e1f92d.
Estimated88% whole plan: only owner board7% and final freeze/tag/report/site5% remain. No new build required.
Hardware/formal/SOC NO; no RC2 tag until owner evidence. Main .xpr stays uncommitted.

## Latest owner GUI build15 Nov2026
Owner rebuilt main project; PASS12:26. Read reports/R10_OWNER_GUI_BUILD_20261115.md.
Current imageSHA256 7a81ddf2c8f6c10bf5410f04dc5f55fc0fe2748575b3a85fc30f56c345fdd20e. Same payload/metrics as four previous qualified builds.
No more build required. Board observations still pending; no hardware/formal/SOC PASS, noRC2tag.

## Website ownership handoff15 Nov2026
Kalash assigned website edits/build/deployment to teammate Arnav. Do not modify/publish site unless asked again.
Verified revision10 changes/evidence are packaged at _export/Arnav_Website_Revision10_Handoff_20261115.zip.
Read docs/handoff/ARNAV_WEBSITE_REV10_20261115.md. Package contains50 files, public-safe reference facts, current
inclusive hierarchy CSV, exact stale-text/file map, limits and acceptance checklist. Site itself was read only.
Arnav must integrate and run site validation/build/tests; those are not claimed complete by this package.
Current image hardware validation stillNO; noRC2tag; final freeze awaits owner board record.
