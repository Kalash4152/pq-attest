# PQ-Attest

**Post-quantum hardware attestation and authorization enforcement for a RISC-V network-on-chip SoC, on an AMD Artix-7 FPGA.**

PQ-Attest is a multi-tile system-on-chip. A hardware root of trust (RoT) measures a RISC-V tile, verifies a KMAC/SHA-3
based attestation response, and only then authorizes that tile to reach protected memory across a credit-based 3Ã—2 mesh
network-on-chip. Authorization can be revoked at runtime.

This repository holds the RTL, testbenches, verification harness, generators, firmware, FPGA build flow, reports and
project website. The `titan` branch holds the ongoing research extension, **TITAN** (bounded transaction finality under
revocation); see [TITAN](#titan-research-extension) below.

> **Status (25 Nov 2026):**
> - Revision 10 is RTL-complete and builds and closes timing on xc7a100tcsg324-1.
> - `HARDWARE_VALIDATED = NO`, `FORMAL_PROOF = NO`, `SOC_INTEGRATION_COMPLETE = NO`.
> - Board validation of the exact release image is pending.
> - See [docs/STATUS.md](docs/STATUS.md) and [Limitations](#limitations).

---

## Contents
- [Architecture](#architecture)
- [Measured results](#measured-results)
- [Verification approach](#verification-approach)
- [Repository layout](#repository-layout)
- [Getting started](#getting-started)
- [TITAN research extension](#titan-research-extension)
- [Limitations](#limitations)
- [Team](#team)
- [Acknowledgements and third-party code](#acknowledgements-and-third-party-code)
- [License](#license)

## Architecture

```
            x=0                     x=1                     x=2
  y=0  â”Œâ”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”        â”Œâ”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”        â”Œâ”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”
       â”‚ Tile 0       â”‚â—„â”€â”€â”€â”€â”€â”€â–ºâ”‚ Tile 1       â”‚â—„â”€â”€â”€â”€â”€â”€â–ºâ”‚ Tile 2       â”‚
       â”‚ CPU B        â”‚        â”‚ plain tile   â”‚        â”‚ protected    â”‚
       â”‚ (never auth) â”‚        â”‚              â”‚        â”‚ memory 16 KB â”‚
       â””â”€â”€â”€â”€â”€â”€â–²â”€â”€â”€â”€â”€â”€â”€â”˜        â””â”€â”€â”€â”€â”€â”€â–²â”€â”€â”€â”€â”€â”€â”€â”˜        â””â”€â”€â”€â”€â”€â”€â–²â”€â”€â”€â”€â”€â”€â”€â”˜
              â”‚                       â”‚                       â”‚
  y=1  â”Œâ”€â”€â”€â”€â”€â”€â–¼â”€â”€â”€â”€â”€â”€â”€â”        â”Œâ”€â”€â”€â”€â”€â”€â–¼â”€â”€â”€â”€â”€â”€â”€â”        â”Œâ”€â”€â”€â”€â”€â”€â–¼â”€â”€â”€â”€â”€â”€â”€â”
       â”‚ Tile 3       â”‚â—„â”€â”€â”€â”€â”€â”€â–ºâ”‚ Tile 4       â”‚â—„â”€â”€â”€â”€â”€â”€â–ºâ”‚ Tile 5       â”‚
       â”‚ CPU A +      â”‚  L2    â”‚ Root of      â”‚        â”‚ test / attackâ”‚
       â”‚ attest. end- â”‚ KMAC   â”‚ trust        â”‚        â”‚ injector     â”‚
       â”‚ point        â”‚â—„â•â•â•â•â•â•â–ºâ”‚ (verifier)   â”‚        â”‚              â”‚
       â””â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”˜        â””â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”˜        â””â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”˜
   3Ã—2 mesh Â· XY routing Â· credit-based virtual channels Â· one link register per hop (LINK_PIPE=1)
```

| Block | Implementation |
|---|---|
| Cores | 2 Ã— PicoRV32 (RV32I) with instruction/data memories, MMIO status, UART, GPIO |
| Interconnect | 6 routers, credit/VC flow control, XY routing, 32-bit flits; network interfaces with per-slot timeouts |
| Attestation | SHA-3-256 measurement of the tile (whole instruction memory in revision 10), KMAC-128 key derivation and tag, nonce/epoch freshness, bounded BUSY retry |
| Link authentication | KMAC on control messages (CHALLENGE/RESPONSE/GRANT/REVOKE) between tiles 3 and 4, with one shared L2 engine under RoT priority |
| Enforcement | Per-tile authorization gate, ingress source checks, quarantine, and a tile-2 memory front end that checks authority at the side-effect point |
| Clocking | 100 MHz board clock â†’ MMCM â†’ one 50 MHz (20 ns) design clock |

Design decisions are recorded in [docs/DECISION_REGISTER.md](docs/DECISION_REGISTER.md) and [docs/decisions/](docs/decisions/).
The wire format is frozen through numbered interface revisions (`M-F1`).

## Measured results

All numbers come from Vivado 2024.1, xc7a100tcsg324-1, 20 ns clock, post-route, unless stated otherwise. FPGA
utilisation is not ASIC area.

| Build | LUT | FF | BRAM36 | WNS | WHS | Source |
|---|---:|---:|---:|---:|---:|---|
| Revision 10 release (main project, owner build, 15 Nov 2026) | 39,962 | 29,187 | 20 | +0.182 ns | +0.007 ns | [R10_OWNER_GUI_BUILD](reports/R10_OWNER_GUI_BUILD_20261115.md) |
| RC1, revision 9 | 34,952 | 25,328 | 20 | +0.120 ns | +0.009 ns | release record |
| Attestation subsystem, real-pin N-13 top (S4 area package) | 32,708 | 30,841 | â€“ | +0.275 ns | +0.052 ns | [S4 gate](reports/S4_GATE_20261105_REV1.md) |

- **Release image:** `pq_merged_board_top.bit`, SHA-256 `7a81ddf2c8f6c10bf5410f04dc5f55fc0fe2748575b3a85fc30f56c345fdd20e`.
  The binary is not committed.
- **Matched secure memory access (revision 10):** read and write medians 32 cycles each (I-27).
- **Area work:** âˆ’14 % LUT on the attestation subsystem through architecture sharing, specialisation, fan-out replication
  and per-block synthesis strategy. See [docs/methodology/AREA_TIMING_PLAYBOOK.md](docs/methodology/AREA_TIMING_PLAYBOOK.md).

## Verification approach

A result counts only when it comes out of the registered evidence harness:
`scripts/dual_lane.py` with the job registry in `scripts/dual_lane_jobs.json`.

- **Frozen expectations:** every job's expected check count is frozen before its first run. Accepted states are
  `PASS_FRESH`, or `PASS_REUSED` with an exact identity match (sources, hashes, defines, configuration).
- **Negative controls and mutants:** deliberately broken variants must fail on the targeted check, with no unrelated
  failure.
- **Golden data:** vectors are generated from the teammate Python reference (`software/`); none are hand-typed.
- **Protected originals:** these are hash-checked. Secure changes live in `rtl/dual_lane/` variants built by generators
  with pinned inputs.
- **Claims vocabulary:** implemented / XSim-simulated / reference-checked / mutation-tested. Formal and hardware
  validation are reported separately and are currently **NO**.

Method documents are in [docs/methodology/](docs/methodology/). Gate reports for every increment are in [reports/](reports/).

## Repository layout

| Path | Contents |
|---|---|
| `rtl/dual_lane/` | Secure SoC RTL: P7 subsystem, network interfaces, L2 authentication, gates, verifier, endpoint, KMAC/SHA-3 variants; `merged/` holds the merged SoC core and system benches |
| `rtl/riscv/` | CPU tile, PicoRV32 adapter, memory, MMIO, bridge to the NoC |
| `NOC_PQATTEST.srcs/` | Original (protected) NoC and crypto sources and their benches |
| `synth/` | Board tops, XDC constraints |
| `scripts/` | Evidence harness, generators (`prepare_*.py`), build flows (`merged_bitstream_flow.tcl`, `merged_impl.tcl`) |
| `automation/` | Harness payload used by the job runner |
| `sim/`, `sim_riscv/`, `verification/` | Testbenches, RISC-V benches, Python verification suite |
| `vectors/`, `golden/` | Generated golden vectors |
| `software/`, `sw/riscv/` | Python reference models; RV32I firmware and assembler |
| `reports/` | Gate reports, build reports and area/timing studies (per-job raw logs are archived separately) |
| `docs/` | Status, decisions, interface revisions, methodology, plans, reviews |
| `site/` | PQ-Attest SoC Explorer website (interactive 3D view, flows, evidence browser) |
| `archive/` | Historical HDL snapshots (pre-recovery copies, mutants, planned snapshots); not built |

## Getting started

**Requirements:** AMD Vivado/XSim 2024.1 (Windows), Python 3.10+ (developed on 3.13), Node 20+ for the website.

```bash
# regenerate the generated RTL variants and check them
python scripts/prepare_i9.py && python scripts/check_i9.py

# run a registered increment through the evidence harness (example)
python scripts/dual_lane.py preflight
python scripts/dual_lane.py run --select I-27-R2
```

- **Build the merged SoC bitstream (batch):** see `scripts/merged_bitstream_flow.tcl` and
  [docs/STATUS.md](docs/STATUS.md). The source list is generated by `scripts/make_merged_sources.py`.
- **Website:** `cd site && npm install && npm run dev`. See [site/README.md](site/README.md).

Detailed reproduction notes: [docs/REPRODUCE.md](docs/REPRODUCE.md).

## TITAN research extension

Branch [`titan`](../../tree/titan). TITAN adds **bounded transaction finality under revocation**:
- per-tile authorization epochs;
- epoch-stamped memory requests;
- a commit guard at the memory side-effect point;
- explicit denial responses;
- a read-response filter;
- truthful SUCCESS / DENIED / ERROR / UNKNOWN outcomes at the CPU.

| Stage | Status |
|---|---|
| S0â€“S3 | Baseline, B0 golden regression, passive finality monitor, interface package. **PASS**, 30 fresh jobs |
| S4R | Per-tile epoch tracker (advances on the rising edge of authorization). **PASS**, 19 fresh |
| S5R | Request epoch stamp with backpressure hold. **PASS**, 20 fresh, 14/14 baseline matches |
| G0 | Reachability review of the baseline races. Open |
| S6â€“S14 | Commit guard, denial, read filter, CPU outcomes, comparison modes, FPGA/ASIC. Planned |

TITAN is unpublished research. Keep this repository private until the paper is submitted.

## Limitations
- No hardware validation of the release image yet; board observations are pending.
- No formal proof of the integrated design. Isolated formal results on the authorization gate exist in the verification
  lane.
- Demonstration secrets (keys, nonce) are fixed constants in the bitstream and benches. Not for production use.
- No TRNG in the integrated design.

## Team
- **Kalash Bheda**: project lead, RTL architecture and implementation, FPGA flow, performance analysis.
- **Arnav Bhandari**: verification and software lead (contracts, reference models, formal verification, website).
- Additional team members contribute the physical-design flow, reproduction and documentation.

## Acknowledgements and third-party code
- **PicoRV32** by Claire Xenia Wolf, ISC license (`rtl/riscv/picorv32.v`; header retained).
- **Teammate Python reference** (`Pq_Attest_final.zip`, `software/pq_attest_final/`) governs the post-quantum semantics.
  It is included for internal team use; confirm the author's permission and license before any public release. See [THIRD_PARTY.md](THIRD_PARTY.md).
- Website dependencies: see [site/LICENSES.md](site/LICENSES.md).

## License
Copyright Â© 2026 Kalash Bheda and the PQ-Attest team. **All rights reserved** until a license is chosen. See [LICENSE](LICENSE).
