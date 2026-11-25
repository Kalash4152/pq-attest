# R10-SCOPE-01 — DMEM-only fetch restriction does not enforce IMEM-only execution

State: **confirmed by a registered real-CPU XSim counterexample**. Kalash approved IMEM-only local instruction
fetches on 2026-11-14. Scope decision resolved; production mitigation and its verification remain pending.
Audited baseline: 97526015; registered diagnostic at de84e090; no production RTL changed.
HARDWARE_VALIDATED=NO, SOC_INTEGRATION_COMPLETE=NO, FORMAL_PROOF=NO.

## Mechanism

`rtl/riscv/addr_decode.sv:267` routes STATUS requests without inspecting `local_is_fetch_i`.
Its STATUS_WAIT response also forwards peripheral data without an instruction-fetch restriction.
`rtl/riscv/tile_status.sv:83` returns BUILD_ID at offset 0x0c.
`rtl/riscv/tile_top.sv:183` enables compressed instructions.

The diagnostic IMEM sets SP=0x8000 and jumps to STATUS BUILD_ID at 0x1000200c.
The real core receives 0x20261108. Its low halfword 0x1108 is C.ADDI4SPN a0,sp,160,
and the core writes a0=0x80a0. This is an executed instruction fetched from MMIO.
The test does not claim a completed external exploit or an attestation bypass under the demo firmware.
It disproves the revision-10 section-4b claim that the proposed DMEM-only change limits executable code to IMEM.

Two independently compiled source copies were run:

| Variant | Fetch accepted | BUILD_ID observed | Instruction executed |
|---|---|---|---|
| Current decoder | yes | 0x20261108 | a0=0x80a0 |
| Current decoder + planned DMEM-only instruction-fetch guard | yes | 0x20261108 | a0=0x80a0 |

Both complete all three frozen diagnostic observations at 1080 ns. Neither times out.
This diagnostic's PASS means the counterexample was reproduced, not that the design passed a security gate.

## Evidence and reproduction

Harness: `python -E scripts/dual_lane.py run --select r10cov`.
Run: `reports/dual_lane_10_20261113_202552_c706f236/r10_fetch_scope/`.
Files: `finding.json`, `baseline/simulate.log`, `dmem_guard_only/simulate.log`, source manifests and copied sources.
Bench: `sim_riscv/tb_r10_mmio_fetch.sv` (three observations, frozen before first run).
Runner: `scripts/run_r10_fetch_scope.py`. Tool: XSim 2024.1.

## Smallest proposed correction (NOT APPLIED)

Before selecting any local data-memory/peripheral target, route
`local_is_fetch_i && !is_imem` to the existing ERR_RESP path.
This rejects instruction fetches from DMEM, UART, GPIO, STATUS and NI MMIO, while preserving data accesses.
The TMEM bridge already separately rejects remote instruction fetches.

Update revision 10 section 4b and its verification plan before changing RTL.
Add directed IMEM-allowed / DMEM-denied / MMIO-denied / data-access-unchanged checks and a scoped mutant.
Describe the guarantee precisely as successful instruction fetches restricted to measured IMEM;
existing bus-error poison/IRQ handling remains a separately documented limitation.

Alternative: keep the DMEM-only change and narrow the claim to that exact restriction.
Kalash chose "Approve IMEM-only instruction fetch (recommended)" in the chat on 2026-11-14.
Revision 10 was amended before trial RTL. Baseline coverage completed; the scratch hasher trial may proceed.
