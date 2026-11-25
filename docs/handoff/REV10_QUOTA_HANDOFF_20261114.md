## Latest: MAIN-project bitstream built and gated successfully

Image: C:\vivado_verilog_proj\NOC_PQATTEST\NOC_PQATTEST.runs\impl_merged\pq_merged_board_top.bit
SHA256: 8d951af86feb9085aee7f7316e231ba091d6969cb6f4b2133f8d7a96b7e1f92d
All four physical builds match39962LUT/29187FF/WNS+0.182/WHS+0.007; main payload equals both releases and GUI copy.
The source-sync and main Generate Bitstream flow have now actually run. Do not rebuild again merely to program
this exact accepted image. Open the main project to view its implemented design/schematics. Board observations
are the next required input; programming remains Kalash-only. Hardware/formal/SOC flags NO.

--- earlier instructions and historical gates ---

## Latest verified handoff - automated G3/G4/GUI-copy gates complete (14 Nov, 22:06 IST)

Supersedes the in-progress GUI snapshot below. G3:31/31 PASS_FRESH. G4:both release builds PASS. GUI-copy G5:PASS,
73 files synced idempotently, full implemented top opened, mesh hook linked17236 primitives, firmware v3 has4096 words.
All three physical builds match:39962 LUT,29187 FF,20 BRAM36,WNS+0.182 ns,WHS+0.007 ns,route/DRC0.
G5 commit90f57570. Final harness selftests150/150 and preflight683 lists /287 guarded files PASS.
GUI-copy whole bit SHA256:f633b14c02173066fc38689bd5b4e7cdcda53e3a63e473ccfe5b4a295f6a52a2.
Its configuration payload is byte-identical to BOTH G4 builds, SHA256:
54228bfc7b7536a48cb27e1538574199d7088fd4ff2f849664d141317204c3dd.

**Whole approved plan approximately84% complete**, using the same estimate below:80% completed through G4 plus
4% for automated GUI-copy qualification. Owner main GUI4%, board7%, final freeze/tag/reports/site5% remain.
This is an effort estimate, not measured correctness. Do not call the whole project95% or hardware-complete.
No further unattended build is running or required before the owner's action. Read R10_READY_FOR_OWNER_20261114.md.
No hardware programming, no RC2 tag, no phase7 website/sign-off update yet; hardware/formal/SOC flags remain NO.

--- Original22:01 point-in-time handoff (retained below) ---

# Revision-10 continuation handoff - 14 Nov 2026, 22:01 IST

This is a point-in-time checkpoint requested before weekly quota exhaustion. Codex cannot read the remaining
weekly usage percentage or detect 2%; this handoff was saved proactively. Later READY_FOR_OWNER/gate records
supersede the in-progress GUI state below. Running owned jobs are NOT being stopped.

## Baseline and completion estimate

Repository C:/vivado_verilog_proj/NOC_PQATTEST, branch noc/credit-integration. Read git log and live state first:
the finalizer can make a later evidence commit without another model turn. Current HEAD before this handoff:
23e917d5. Production implementation c951e876 / abc90d1d; qualification-source 1db787bb / fd6079f0.
G3 gate/evidence e35b446a; G4 gate e0b97f2b; payload comparison/interrupted-GUI evidence 23e917d5.

**About 80% of the whole approved plan is complete**, a conservative effort estimate, not a measured correctness score.
Weights: controls/coverage5 + approval5 + scratch15 + implementation20 + qualification25 + release10 =80 completed.
GUI copy plus owner main-project Generate Bitstream8, owner board7, final freeze/tag/reports/site5 remain.
A successful GUI-copy gate completes only the automated half of GUI work: roughly84%, not a fabricated95%.
The original RC1 project was already built; this percentage refers to the approved revision-10 upgrade plan.

## Implemented and verified

- Approved rev10: full16384-byte IMEM SHA3-256; existing64-byte field holds digest/length/base/zero padding.
- Tile3 uses meas_imem_hasher; tile0 keeps the small reader. No packet-format, device, clock, pin or CDC change.
- Successful local instruction fetches restricted to IMEM, including MMIO denial (explicit owner amendment approved).
- Firmware v3 button waits unbounded; grant wait remains bounded; all4096 image words defined. Profile10 references
  independently checked with hashlib and the pinned teammate reference (32-byte system tile keys).
- G0 + baseline controls/coverage PASS; scratch G1 PASS39918 LUT / WNS+0.210 / WHS+0.015, explicitly NOT a release.
- First I-27 gate NOT PASSED:27 fresh, one premature test sampling error, two dependent builds blocked. Kept unchanged.
- I-27-R2 G3 PASS:31/31 PASS_FRESH, zero reused, seven scoped mutation kills; no timeouts accepted as passes/kills.
  Same six approved-image assertions and same limits, corrected destination-authorization event; dropped-GRANT
  control killed on two explicit checks. No RTL/reference change was needed to fix the bench.
- Whole-IMEM9 / decoder19 / actual-CPU-MMIO3 plus mutation controls; closure14 and lifecycle14; error6; in-flight6;
  contention8; phase56 and their controls; tampered-image rejection6; I9 integration13; project/profile/release controls;
  four matched workloads8 each,64 transfers/mode; physical gate negatives6/6 plus wrong-top rejection.
- G3 integrated build39962 LUT,29187 FF,20 BRAM36,WNS+0.182,WHS+0.007,TNS/THS0,route/DRC0,clean check_timing.
- Matched secure read/write32/32 cycles, fixed research baseline28/27; contended distributions retained in run data.

## Two G4 release builds - BOTH PASS

| Build | LUT | FF | WNS ns | WHS ns | Whole-file SHA256 |
|---|---:|---:|---:|---:|---|
|1|39962|29187|+0.182|+0.007|2d59f7431a265452d90387538549ef1f4d93ff2381bb59a85d9b224c910768ef|
|2|39962|29187|+0.182|+0.007|bbc50b68dee4c0e2c3e04ed22e09bc0dffba83f342ad4386dd43c4788add2002|

Both source manifests match; targets/headers match. ALL five differing file bytes are inside the header time field,
17:27:31 versus18:42:24. Configuration payloads are byte-identical (3825788 bytes), SHA256:
54228bfc7b7536a48cb27e1538574199d7088fd4ff2f849664d141317204c3dd.
Thus programmed configuration is reproduced, not the complete timestamped files. See R10_G4_BITSTREAM_COMPARISON.
Latest accepted release on disk: NOC_PQATTEST.runs_merged/merged_board/pq_merged_board_top.bit (build2).

## Live GUI-copy job - inspect before doing anything

First GUI attempt _r10g did NOT finish. Lid-triggered Modern Standby18:59:57-21:26:18 was logged; processes were
absent afterward. Exact termination cause not established. No bitstream/PASS; partial evidence preserved in
reports/r10_gui_attempt1_interrupted_20261114. This was not a proven design/timing failure.

Recovery runs ONLY the isolated GUI-copy test in C:/vivado_verilog_proj/_r10g2 (no duplicate release run).
Finalizer PID12828 at launch; execution session82148. Read live before trusting PIDs:
- C:/vivado_verilog_proj/_r10g2/finalize_status.json
- C:/vivado_verilog_proj/_r10g2/finalize.lock
- reports/r10_finalize_recovery_20261114.txt
- C:/vivado_verilog_proj/_r10g2/gui_stdout.txt
- C:/vivado_verilog_proj/_r10g2/NOC_PQATTEST.runs/impl_merged/runme.log

Current snapshot: GUI_COPY_BUILD_RUNNING; post-route optimization/reports, no final GUI PASS yet.
Source sync is proven from actual copied owner-project metadata:73 GUI files, meas_imem_hasher.sv present,
demo_fw_v3.hex present and4096 words, SHA25643c62fbcf6e8772c5c77eab2a3739a3593ccdc94c9b6de8baa7d7bdcd733ec8a.
Second source sync changed0/0 files. Synth post-hook actually linked one mesh and17236 primitive cells and rewrote
its checkpoint. See reports/R10_GUI_SOURCE_SYNC_READBACK_20261114.json and synthesis runme.log.

The finalizer will, ONLY after actual GUI success, validate its routed gate and bit hash, open the implemented top,
reject ERROR/CRITICAL WARNING in parent/child logs, verify release mesh/source hashes, write G5 and owner handoff,
refresh the documentation-only GUI header, run150 harness selftests, regenerate payload ONCE with registry/config
byte equality, run preflight, and commit text evidence. It never programs hardware or tags RC2.
READY_FOR_OWNER is success; STOPPED_NEEDS_REVIEW contains an actual error. Do not call a pending gate PASS.
If the process is still alive, do not restart it. If dead, preserve evidence, diagnose, and recover only the missing step.

SYSTEM_REQUIRED requests prevent ordinary idle sleep only. Lid closure/manual sleep/critical battery override them.
Latest battery readback: AC connected/status2,50%. Keep lid open and AC connected. No permanent power setting changed.

## Next actions after GUI completion

1. Independently read R10_G5_GUI_GATE_20261114.md and actual run logs; compare GUI LUT/FF/WNS/WHS with BOTH G4 builds.
2. Preserve explicit source-sync and mesh-link proof in final handoff. Record GUI bit SHA; compare actual payload if
   claiming it matches G4. A future owner's timestamped .bit SHA cannot be predicted: record his actual programmed hash.
3. Owner opens MAIN NOC_PQATTEST.xpr and runs:

       source C:/vivado_verilog_proj/NOC_PQATTEST/scripts/merged_gui_runs.tcl

   Then Generate Bitstream, require GUI_GATE PASS and write_bitstream Complete, record that main image's SHA256.
   The main project has NOT been newly built merely because its COPY passes. NOC_PQATTEST.xpr stays uncommitted.
4. Kalash alone programs hardware and returns itemised observations for that exact hash:1152008N1 UART;
   sw0=0 CPU A/tile3, sw0=1 CPU B/tile0 (select then reset to capture each boot stream). A PASS T3 cycles=...;
   B PASS T0 REFUSED OK; btn2 revoke -> PASS T3 REVOKED / led0 authorization off; btn1 re-attest -> PASS T3 RECOVERED /
   authorization on. btn0 reset. Boot hashing ~8000 cycles (~0.16ms at50MHz), estimate; button waits no longer time out.
   External LED bus is NOT tile GPIO: led0 authorization, led1 sticky attestation failure, led2 CPU A GPIO bit0,
   led3 heartbeat; led0_r CPU B refused; led0_g either CPU FAIL bit. Record each stage, not just an overall PASS.
5. After the board record only: tag rtl-rc2, update sign-off findings D-01/D-02/D-06 with evidence, retain other
   documented/deferred findings; update STATUS/report/site data from latest accepted image, npm build/site tests.
   No ASIC physical implementation has begun. ASIC scope/technology adaptations are separate work.

HARDWARE_VALIDATED=NO, SOC_INTEGRATION_COMPLETE=NO, FORMAL_PROOF=NO. Measurement is at boot/on request, not continuous;
keys/nonce are demonstration constants. Do not claim formal, TRNG, side-channel protection or hardware PASS.

## Rules and resume instructions

Read AGENTS.md, CLAUDE.md, approved rev10, EXECUTION_BLUEPRINT and live checkpoint first. No protected RTL/ZIP/reference
writes, no original+variant duplicates, no changed frozen counts/reference vectors, no timeout pass, no destructivegit,
no killing unowned jobs. Physical jobs run alone; no duplicate release run. HARD STOP for a real design/contract
failure, LUT>47550 or final setup/hold<0; do not sweep directives or add constraints to recover without owner approval.
Do not commit main XPR or the two pre-existing CRLF-only M-F1 docs. Binary products stay on disk with recorded hashes.
Source/reference unchanged during current GUI job. Current partial build must not be called95% complete.

## Evidence index

- reports/I27_R2_GATE_20261114.md; reports/I27_GATE_20261114_NOT_PASSED.md
- reports/R10_G4_RELEASE_GATE_20261114.md; reports/R10_G4_BITSTREAM_COMPARISON_20261114.json
- reports/dual_lane_10_20261114_114143_ce2c2eba (31 fresh results/logs and matched data)
- reports/R10_EXECUTION_CHECKPOINT_20261113.md (append-only progress)
- reports/QUOTA_HANDOFF_20261114 (continuation source text and partial GUI snapshots)
- Upon SUCCESS ONLY: reports/R10_G5_GUI_GATE_20261114.md, reports/R10_READY_FOR_OWNER_20261114.md

Communication preference: minimal narration, pre-output check about one in five replies. Quota percentage is not
visible to the agent; never promise automatic detection of2%. Continue authorized work from live evidence.
