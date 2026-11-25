# Revision 10 execution checkpoint

Baseline: 97526015, branch noc/credit-integration. All ten handoff baseline hashes matched.
Approval recorded before design changes in commit 7ada59d1 (Kalash's 13 Nov chat instruction).
HARDWARE_VALIDATED=NO, SOC_INTEGRATION_COMPLETE=NO, FORMAL_PROOF=NO.

## Order and current state

1. Phase 0: R10-P0 explicitly re-registers the existing closure (14), inflight (6), contention (8),
   and their two existing scoped controls (6 / 8). Historical records and counts are unchanged.
   This is necessary because the I-26 active allow-list excludes I-23; selecting i23 alone skips it.
2. Harness self-tests freshly PASS: 150 tests (`r10_harness_selftest_20261113.txt`).
3. Preflight PASS: 620 source lists, 253 guarded updates (`r10_phase0_preflight_20261113.txt`).
4. `python -E scripts/dual_lane.py run --select r10p0`: PASS 5/5 fresh, no reuse.
   Gate `reports/R10_P0_GATE_20261113.md`, commit 4f840c9c.
5. Coverage measurement and fetch-scope diagnostic registered at de84e090 as R10-COV;
   running via `python -E scripts/dual_lane.py run --select r10cov`.
   Evidence: `reports/dual_lane_10_20261113_202552_c706f236/`.
6. **Security-scope stop resolved by Kalash on 2026-11-14:** diagnostic PASS_FRESH confirms real CPU executes MMIO BUILD_ID
   as C.ADDI4SPN, both on current decoder and on a copied decoder with the planned DMEM-only guard.
   Finding `reports/R10_FETCH_SCOPE_FINDING_20261113.md`, committed at 972590a7.
   Kalash was asked to approve IMEM-only local instruction fetches, or retain DMEM-only with a narrower claim.
   Kalash selected "Approve IMEM-only instruction fetch (recommended)". Contract amended before trial RTL in baed09d2.
   R10-COV completed 2/2 PASS_FRESH; per-module coverage CSVs and gate report R10_COV_GATE_20261114.md committed.
7. Unit trial vs hashlib (three images), trial implementation <=47,550 LUT and setup/hold >=0.
8. Then implementation, I-27, release, GUI copy test, owner board validation, RC2 as blueprint orders.

## Phase 1 in progress (14 Nov)

Scratch copy: `C:/vivado_verilog_proj/_r10t` (1,155 original input hashes in REPLAY_INPUT_MANIFEST.json).
Only scratch design changes: new meas_imem_hasher; CPU3 hasher selection (CPU0 legacy); padded firmware v3;
IMEM-only local fetch guard; trial source list/top firmware filename. Production design remains unchanged.
Scratch unit test: 9/9 PASS against hashlib for v3/zero/random images; metadata/address/read count, held valid,
restart-while-busy and reset/restart pass. `trial_unit/reference.json`, `simulate.log`, `result.json`.
Scripts: `trial_prepare.py`, `trial_run.py`, `trial_build.py`; bench `trial_unit_tb.sv`.

Full release-recipe scratch implementation is running alone: Python PID 35196, Vivado PID 41636 at launch;
check live PIDs before relying on them. Codex execution session 42182.
Log `trial_build_stdout.txt`; result `trial_build_result.json`; reports `NOC_PQATTEST.runs_merged/merged_board/`.
Driver holds Windows idle-sleep inhibition for its lifetime. Lid closure/manual sleep still suspend the laptop.
Timing/area gate must satisfy <=47,550 LUT, setup/hold >=0; any failure needing design/contract change is a hard stop.
The trial uses old provisioned measurement constants; this is area/timing feasibility, NOT a functional release.
Trial flow deliberately does not write a bitstream. Do not copy trial scripts or trial constants over the release.
Do not modify trial design inputs while Vivado is running. No other EDA job may run concurrently.

Next after trial PASS: preserve gate/hash evidence, implement approved profile 10 in production, register I-27 once
with all frozen counts, run full regression/mutations/attack/IMEM-only fetch tests, then release/GUI gates.
If trial FAIL: retain all results and ask Kalash before changing the design or contract.
Coverage probe exists at `C:/vivado_verilog_proj/_r10_covprobe` (infrastructure only).
No protected files or production RTL changed.

## Overnight continuity (Kalash's instructions, 14 Nov)

- One scheduled return to this same chat: **06:30 IST**, automation id `resume-revision-10-at-6-30-am`, COUNT=1.
  Keep the app running. Quota must be available; this does not detect resets or wake a sleeping computer.
- Temporary Windows SYSTEM_REQUIRED request accepted through **2026-11-14 11:30 IST**.
  Helper `C:/vivado_verilog_proj/_r10t/overnight_awake.py`, status `overnight_awake_status.json`.
  PID at latest launch: 6704. Verify live before acting. No power settings changed; display sleep remains permitted.
  `overnight_awake.stop` is its cooperative stop marker; it also releases the request automatically at deadline.
- The trial driver additionally holds its own sleep request while the implementation runs.
- Laptop must stay plugged in with lid open. Manual Sleep, lid closure, shutdown and critical battery override this.
- User authorizes autonomous routine decisions using VLSI guidance and computer control for GUI checks if needed.
  Original project hard stops remain in force. No finish-by-11 guarantee was made.

## Post-trial implementation notes (not implemented)

- Preserve v9 reference files; create explicitly versioned v10 includes/JSON instead of overwriting historical vectors.
- In production, use explicit reader-selection parameter propagation so legacy standalone profiles can remain legacy;
  the qualified board/profile-10 benches must select full IMEM for CPU A and the small reader for CPU B.
- Unit trial checks=9; freeze final job counts before their first registered run. Expected digests come from hashlib.
- Decoder acceptance must cover IMEM allowed, DMEM boundaries denied, every MMIO target denied, data accesses unchanged,
  and a mutation removing the guard. The existing diagnostic confirms a gap and must not be relabelled after correction.
- Contention firmware differs from demo v3; its full-IMEM golden measurement must be generated for its own padded image.
- Existing merged benches wait only ~60 boot cycles before checking measurement. Profile-10 variants must wait for
  meas_valid with a bounded watchdog appropriate to the new reader, retaining every existing behavioral assertion.
- Fix V-01 with DUT-observed behavior; V-02 must prove actual flit acceptance. Do not touch deferred NI/crypto issues.

## Current continuation: phase 2 integrated, I-27 registration prepared (14 Nov)

This entry supersedes the earlier in-progress scratch notes. G1 completed PASS, report R10_G1_TRIAL_GATE_20261114.md.
Commit c951e876 integrated full IMEM measurement, fetch guard, firmware v3 and independent profile-10 references.
Board/source/release integration and versioned benches now prepared. Static controls: release 23/23, board profile
10 conditions plus 11 negative controls, mutation adapter 2 tests, harness 150 tests PASS.
No production profile-10 simulation or final implementation is claimed yet. I-27 expected counts are being frozen
before first execution. Existing 622 job definitions preserved in scripts/dual_lane_pre_i27.json.
Next: one payload regeneration, preflight, commit frozen registry, run --select I-27.
No EDA job was running at continuation. Only overnight_awake.py PID 6704 was live; do not assume PID later.
HARDWARE_VALIDATED=NO, SOC_INTEGRATION_COMPLETE=NO, FORMAL_PROOF=NO.
## I-27 live execution (14 Nov, 07:43 IST)

Frozen baseline abc90d1d. Command: Python313/python.exe -E scripts/dual_lane.py run --select I-27.
Execution session 90600; scheduler PID 8132 (verify live); evidence reports/dual_lane_10_20261114_073825_0fc50ad4.
Console reports/i27_run1_20261114.txt. Preflight PASS 281 guarded files / 652 lists.
First seven jobs PASS_FRESH: profile, board profile, release controls, mutation adapter controls,
hasher (9), decoder (19), real-CPU MMIO guard (3). Hasher mutation control currently running.
Do not edit any design, registry, reference or harness input during this batch. No final release is qualified yet.
On resume inspect scheduler lock/process and result files; never start a duplicate run.
## Integrated closure result (14 Nov, 07:54 IST)

I-27 first eleven jobs PASS_FRESH. i27_closure completed 14/14, zero errors at 5.215060 ms simulated time.
Includes actual DUT measurement/response, both CPU outcomes, exact memory value/count, revoke/refusal,
re-attestation/recovery and both UART streams. Hash/decoder/MMIO mutants all KILLED with scoped expected failures.
Separate i27_lifecycle replay currently running. All remaining jobs and final release remain unqualified.
## Lifecycle replay result (14 Nov, 08:02 IST)

I-27 12/30 PASS_FRESH so far, none reused. i27_lifecycle independently repeated all 14 checks,
zero errors, identical 5.215060 ms simulated completion. i27_error is now running.
Gate/closure still pending all remaining jobs. Tool-source identity supplement saved in
reports/i27_tool_source_identity_20261114.json; compare again at end. Partial diagnostic review in
reports/I27_DIAGNOSTICS_20261114.md. Isolated GUI test driver prepared only at C:/vivado_verilog_proj/_r10g/test.tcl;
not executed and must wait for I-27 plus fresh release PASS.
## I-27 completed, not passed — supersedes earlier live status

Run dual_lane_10_20261114_073825_0fc50ad4 completed: 27 PASS_FRESH, 1 INVALID (six checks / one error),
2 BLOCKED (physical build and gate controls). No EDA process or scheduler lock remains.
See reports/I27_GATE_20261114_NOT_PASSED.md. Failed approved-image check samples local authorization at the
RoT send handshake; production RTL/reference changes are not indicated. Versioned bench with unchanged 6 checks
and unchanged 100000-cycle bound prepared, plus dropped-GRANT mutation. Requalification planned as I-27-R2,
31 new job IDs, preserving the entire first run and all 652 earlier frozen definitions.
Night helper's 11:30 request expired. New scheduler wrapper will hold a request only for its own job lifetime.
## I-27-R2 running (14 Nov, 11:41 IST)

Frozen baseline 1db787bb, raw original evidence retained in fd6079f0. Preflight PASS 287 guarded files / 683 lists.
Current evidence reports/dual_lane_10_20261114_114143_ce2c2eba; console reports/i27r2_run1_20261114.txt.
Execution session 34074; wrapper PID 5180, scheduler PID 31832 (verify live before acting).
First job i27r2_attack_approve_changed is compiling. 31 fresh jobs required; original six assertions/bounds unchanged.
No RTL/reference change. All 652 prior definitions preserved byte-for-byte in the new registry prefix.
Wrapper C:/vivado_verilog_proj/_r10g/run_i27r2.py holds SYSTEM_REQUIRED only for scheduler lifetime; status
C:/vivado_verilog_proj/_r10g/i27r2_awake_status.json. Old night helper has expired. No permanent power setting changed.
Do not edit qualified inputs or regenerate payload during the batch. Inspect lock/process before any restart.
## Corrected approved-image control PASS (14 Nov, 11:43 IST)

First R2 job i27r2_attack_approve_changed PASS_FRESH, 6/6 assertions, zero errors, 179040 ns final time.
This supports the documented test-sampling cause: same RTL/reference/assertions, wait stops on actual authorization.
Dropped-GRANT control still running. No overall R2 gate or physical build is claimed yet.
Diagnostic trace note: authorization_cycle=-1 at the print is not an authorization failure or measured latency.
The posedge monitor samples pre-NBA authorization, while the test observes the newly asserted signal at negedge;
it can print before that monitor's next posedge update. The unchanged actual authorized[3] assertion passed.
Do not derive grant-arrival latency from that diagnostic field. Final memory commit / authorization assertions passed.
## R2 grant-control pair accepted (14 Nov, 11:50 IST)

First six jobs PASS_FRESH. Corrected approved-image control 6/6, zero errors; dropped-GRANT control six checks,
two scoped errors, KILLED (no timeout). See reports/I27_R2_GRANT_CONTROL_20261114.md.
The originally observed failure is resolved as test synchronization, without design/contract/reference changes.
All remaining R2 jobs continue automatically; current i27r2_hasher. Full gate remains pending, no final build yet.
## R2 unit and mutation subgate complete (14 Nov)

First twelve jobs PASS_FRESH, zero reused/failures. Includes positive approved-image control, dropped-GRANT kill,
profile/release/board-profile/mutation controls, hasher9/decoder19/CPU-MMIO3 and all three scoped fault controls.
Current i27r2_closure; integrated regressions, physical build, release and GUI gates remain pending.
## R2 integrated positive regressions accepted through phase sweep (14 Nov, 12:07 IST)

18/31 PASS_FRESH, none reused or failed. Closure14 + lifecycle14, remote-error6, in-flight6, contention8,
phase-sweep56 all passed. Phase sweep completed at 5.756620 ms, zero errors.
Current i27r2_inflight_control; remaining controls/attack reject/I9/project/matched workloads then physical gates.
Prepared-only release continuation driver: C:/vivado_verilog_proj/_r10g/reproduce_release.py (requires 31 fresh jobs
and reports/I27_R2_GATE_20261114.md; holds SYSTEM_REQUIRED for two sequential builds; not executed).
## G3 PASS — live readback 14 Nov, 16:37 IST

All 31 R2 jobs PASS_FRESH; scheduler ended 13:22 IST, exit 0. No EDA process remains.
Measured integrated build: LUT39962 FF29187 BRAM20 WNS+0.182 WHS+0.007, TNS/THS0, route/DRC0, timing clean.
Gate reports/I27_R2_GATE_20261114.md; hashes I27_R2_BINARY_HASHES_20261114.json. 156 inputs match frozen source commit.
Next: commit G3 text evidence, execute C:/vivado_verilog_proj/_r10g/reproduce_release.py (two builds), inspect results.
Then prepare/test GUI-copy project using _r10g/prepare_gui_copy.py and _r10g/test.tcl. Main XPR remains untouched.
Hardware/formal/SOC flags remain NO. No RC2 tag until owner validation. Old I-27 failed record remains unchanged.

## G4 release reproduction started (14 Nov, 16:38 IST)

G3 gate + text evidence committed e35b446a. Driver C:/vivado_verilog_proj/_r10g/reproduce_release.py runs TWO sequential
fresh release builds; execution session12967, driverPID19720, first workerPID14676, first VivadoPID35752 (verify live).
Console reports/r10_release_reproduce_20261114.txt; lock NOC_PQATTEST.runs_merged/merged_release.lock.
Driver holds SYSTEM_REQUIRED for its lifetime and validates each result; records each source manifest/hash in
reports/r10_release_{1,2}_result_20261114.json and combined R10_RELEASE_REPRODUCTION_20261114.json.
Do not invoke start again. Existing accepted/failed images remain in timestamped previous directories.
Current Vivado phase mesh OOC synthesis, license acquired. No physical gate or release PASS yet for G4.
STATUS rev23 and NEXT_STEP updated on disk; commit with next logical group. No canonical source change.
## Low-usage autonomous continuation (14 Nov, 16:53 IST)

Kalash requests minimal narration, updates near completion. Full authorized G4/G5 continuation is now queued:
C:/vivado_verilog_proj/_r10g/finalize_r10.py, session54661, PID36888 (verify live). Status finalize_status.json,
console reports/r10_finalize_20261114.txt. It waits for EXISTING G4 driver19720; never starts duplicate release jobs.
On two validated fresh release builds: writes/commits G4 gate, waits for no other EDA, creates isolated GUI project,
runs/test-gates actual GUI synthesis/implementation/bitstream, opens implemented top, checks diagnostic logs,
validates mesh/hash/source closure, writes owner handoff, refreshes comment/status/payload with registry/config
byte equality, harness selftests and preflight, commits G5 evidence. No hardware programming or RC2 tag.
Both scripts hold temporary SYSTEM_REQUIRED; no permanent power change. No production RTL/reference edits.
On any error it stops and records STOPPED_NEEDS_REVIEW with the reason; do not call an unrun gate PASS.
Success state READY_FOR_OWNER means automated build/copy checks completed; owner MAIN GUI and board validation
plus final freeze/tag/report/website phase remain. Read reports/R10_READY_FOR_OWNER_20261114.md only after success.
GUI copy test also explicitly rejects ERROR/CRITICAL WARNING in parent and both child run logs.

## G4 PASS (automatic validated continuation)
Two fresh builds accepted; see R10_G4_RELEASE_GATE_20261114.md. GUI test starts next; no hardware action.

## G5 GUI copy running
C:/vivado_verilog_proj/_r10g/test.tcl; main XPR untouched. Read finalize_status.json before any restart.

## GUI-copy attempt1 interrupted; recovery at21:40 IST
G4 both PASS, exact programmed payload identical; five differing bytes only in time header. G4 comparison report updated.
Old GUI attempt not complete, no bit/no success marker, all owned EDA/finalizer processes absent. Modern Standby lid18:59 to21:26 observed; no claim of exact termination cause.
Old helper lock36888 verified dead and removed; partial logs preserved in r10_gui_attempt1_interrupted_20261114.
Recovery uses NEW isolated C:/vivado_verilog_proj/_r10g2/finalize_r10.py; it validates G4, reruns ONLY GUI-copy stage, no duplicate release job, no RTL change.
Read _r10g2/finalize_status.json for live progress. Main XPR unchanged.

## G5 GUI copy running
C:/vivado_verilog_proj/_r10g/test.tcl; main XPR untouched. Read finalize_status.json before any restart.

## Automated G4/G5 continuation COMPLETE
See R10_READY_FOR_OWNER_20261114.md. G4 two accepted builds; isolated GUI-copy gate PASS. Owner main GUI/board and freeze/tag remain. No hardware claim.

## Final readback: READY_FOR_OWNER,14 Nov22:06 IST
Helper recovery completed G5; commit90f57570. Three accepted physical builds all39962LUT/29187FF/20BRAM/WNS+0.182/WHS+0.007.
GUI bit SHA f633b14c02173066fc38689bd5b4e7cdcda53e3a63e473ccfe5b4a295f6a52a2; payload identical to bothG4.
Final selftests150 and preflight683/287 PASS. Updated CLAUDE/full quota handoff to84% whole-plan estimate.
No more agent builds needed before owner mainGUI and board record. Pending final freeze/tag/report/site AFTER board only.
Read R10_READY_FOR_OWNER_20261114.md; no hardware/formal/SOC PASS and no RC2tag.

## Main-project build authorized by continue,14 Nov22:09
Actual MAIN NOC_PQATTEST.xpr is now being synchronized and rebuilt, using the copy-qualified script.
Runner C:/vivado_verilog_proj/_r10main/run.py; status _r10main/status.json. Preserve .xpr uncommitted.
Previous main image/checkpoint preserved in _r10main/previous_main_build with hashes. Do not duplicate builds.
Only board and final freeze/site remain after actual main gate PASS. No hardware programming.


## Actual MAIN gate PASS
Main image 8d951af86feb9085aee7f7316e231ba091d6969cb6f4b2133f8d7a96b7e1f92d; payload identical to G4/copy. See R10_MAIN_PROJECT_GATE_20261114.md.
No more unattended builds needed; owner board record required. Full handoff updated.


## Scheduled continuation verification15 Nov2026
Actual main build verified from live image hash and gated reports; PID12728 ended, no active EDA.
Commitc8fb7504 holds MAIN gate/evidence. Canonical STATUS corrected to mainPASS, not owner-GUI-pending.
No further executable build step remains. Owner exact-image board record is required before phase7/tag/site.
One-time scheduled continuation will be removed as fulfilled; quota percentage remains unavailable.

## Owner GUI main build verified15 Nov12:49
Actual new image generated12:26, gatePASS39962LUT/WNS+0.182/WHS+0.007,0 errors/critical warnings,4 warnings.
SHA256 7a81ddf2c8f6c10bf5410f04dc5f55fc0fe2748575b3a85fc30f56c345fdd20e; payload unchanged. See R10_OWNER_GUI_BUILD_20261115.md. Owner board record is next.
