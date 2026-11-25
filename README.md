# PQ-Attest

**Hardware attestation and authorization enforcement for a RISC-V network-on-chip SoC, implemented on an AMD Artix-7 FPGA.**

A hardware root of trust (RoT) measures a RISC-V tile, verifies a SHA-3/KMAC attestation response, and only then lets that tile reach protected memory across a credit-based 3×2 mesh network-on-chip. Authorization can be revoked at runtime. The project combines on-chip interconnect design, hardware security and an evidence-based verification method.

> **Status (25 Nov 2026):** Revision 10 is RTL-complete and closes timing on `xc7a100tcsg324-1` at 50 MHz. Hardware validation of the release image, formal proof of the integrated design and full SoC integration sign-off are **not yet done**. See [Limitations](#limitations) and [docs/STATUS.md](docs/STATUS.md).

---

## Table of Contents

- [Summary of Contributions](#summary-of-contributions)
- [Key Findings](#key-findings)
- [Architecture](#architecture)
- [Verification Approach](#verification-approach)
- [Repository Layout](#repository-layout)
- [Getting Started](#getting-started)
- [Limitations](#limitations)
- [Team](#team)
- [Acknowledgements and Third-Party Code](#acknowledgements-and-third-party-code)
- [License](#license)

---

## Summary of Contributions

- **Architecture:** A six-router 3×2 wormhole mesh (XY routing, three virtual channels, credit-based flow control, 32-bit flits) connecting two PicoRV32 tiles, a protected memory tile and a hardware RoT.

- **Authorization enforcement:** Per-tile authorization gate, ingress source checks, quarantine, and a memory front end that checks authority at the point where a memory side effect happens.

- **Attestation:** SHA3-256 measurement of the tile's instruction memory, KMAC128 key derivation and tag, nonce and epoch freshness, replay rejection, bounded retry.

- **Deadlock fix:** A credit-exhaustion deadlock in the mesh was traced to allocator reservations that were not tied to credit-qualified flit transfers. Making reservations credit-qualified removed it.

- **Verification method:** Results count only if they come from a registered evidence harness with frozen expectations, negative controls and mutation tests. See [Verification Approach](#verification-approach).

---

## Key Findings

| Finding | Result |
|---|---|
| Timing closure, revision 10 | 50 MHz post-route, WNS +0.182 ns, WHS +0.007 ns |
| Resource use, revision 10 | 39,962 LUTs, 29,187 FFs, 20 BRAM36 |
| Secure memory access latency | 32-cycle median for reads and for writes (matched access, revision 10) |
| Area work on the attestation subsystem | About 14% fewer LUTs through architecture sharing, specialisation, fan-out replication and per-block synthesis strategy |
| Deadlock | Credit-exhaustion deadlock root-caused and removed by credit-qualified allocator reservations |

All numbers are from Vivado 2024.1, targeting `xc7a100tcsg324-1`, with a 20 ns clock, post-route.

**FPGA utilisation is not ASIC area.**

Per-build numbers and the exact reports are available in [reports/](reports/), for example [R10_OWNER_GUI_BUILD](reports/R10_OWNER_GUI_BUILD_20261115.md).

### Implementation Results

| Build | LUTs | FFs | BRAM36 | WNS | WHS |
|---|---:|---:|---:|---:|---:|
| Revision 10 release (15 Nov 2026) | 39,962 | 29,187 | 20 | +0.182 ns | +0.007 ns |
| RC1, revision 9 | 34,952 | 25,328 | 20 | +0.120 ns | +0.009 ns |
| Attestation subsystem, real-pin top | 32,708 | 30,841 | — | +0.275 ns | +0.052 ns |

---

## Architecture

```text
          x=0                x=1                x=2
  y=0  [Tile 0 ]<------>[Tile 1 ]<------>[Tile 2 ]
       CPU B              plain tile       protected memory (16 KB)
       (never authorized)
          ^                  ^                 ^
  y=1  [Tile 3 ]<------>[Tile 4 ]<------>[Tile 5 ]
       CPU A +            Root of trust     test / attack
       attest. endpoint   (verifier)        injector

  3x2 mesh, XY routing, credit-based virtual channels,
  one link register per hop
```

### Hardware Components

| Block | Implementation |
|---|---|
| Cores | 2 × PicoRV32 (RV32I) with instruction/data memories, MMIO status, UART, GPIO |
| Interconnect | 6 routers, credit/VC flow control, XY routing, 32-bit flits, network interfaces with per-slot timeouts |
| Attestation | SHA3-256 measurement, KMAC128 key derivation and tag, nonce/epoch freshness, bounded BUSY retry |
| Link authentication | KMAC on control messages (`CHALLENGE`, `RESPONSE`, `GRANT`, `REVOKE`) between tiles 3 and 4 |
| Enforcement | Per-tile authorization gate, ingress source checks, quarantine, memory front end that checks authority at the side-effect point |
| Clocking | 100 MHz board clock to an MMCM, one 50 MHz design clock |

Design decisions are recorded in [docs/DECISION_REGISTER.md](docs/DECISION_REGISTER.md).

The wire format is frozen through numbered interface revisions.

---

## Verification Approach

A result counts only when it comes out of the registered evidence harness:

- [`scripts/dual_lane.py`](scripts/dual_lane.py)
- [`scripts/dual_lane_jobs.json`](scripts/dual_lane_jobs.json)

### Verification Principles

- **Frozen expectations:** Each job's expected check count is fixed before its first run. A job passes as fresh, or as reused with an exact identity match of sources, hashes, defines and configuration.

- **Negative controls and mutants:** Deliberately broken variants must fail on the targeted check with no unrelated failure.

- **Golden data:** Vectors are generated from a Python reference model, never hand-typed.

- **Protected originals:** Original sources are hash-checked. Secure changes live in generated variants with pinned inputs.

- **Claims vocabulary:** Every claim is labeled implemented, XSim-simulated, reference-checked or mutation-tested. Formal proof and hardware validation are reported separately and are currently **not done**.

Method documents are available in [docs/methodology/](docs/methodology/).

Gate reports for each increment are available in [reports/](reports/).

---

## Repository Layout

| Path | Contents |
|---|---|
| [`rtl/dual_lane/`](rtl/dual_lane/) | Secure SoC RTL: subsystem, network interfaces, authentication, gates, verifier, endpoint, KMAC/SHA-3 variants |
| [`rtl/riscv/`](rtl/riscv/) | CPU tile, PicoRV32 adapter, memory, MMIO, NoC bridge |
| [`NOC_PQATTEST.srcs/`](NOC_PQATTEST.srcs/) | Original NoC and crypto sources and benches |
| [`synth/`](synth/) | Board tops and XDC constraints |
| [`scripts/`](scripts/) | Evidence harness, generators, build flows |
| [`sim/`](sim/), [`sim_riscv/`](sim_riscv/), [`verification/`](verification/) | Testbenches and Python verification suite |
| [`vectors/`](vectors/), [`golden/`](golden/) | Generated golden vectors |
| [`software/`](software/), [`sw/riscv/`](sw/riscv/) | Python reference models, RV32I firmware |
| [`reports/`](reports/) | Gate reports, build reports, area and timing studies |
| [`docs/`](docs/) | Status, decisions, interface revisions, methodology |
| [`site/`](site/) | Interactive website (3D view, flows, evidence browser) |

---

## Getting Started

### Requirements

- AMD Vivado/XSim 2024.1 (Windows)
- Python 3.10 or newer
- Node.js 20 or newer for the website

### Run the Verification Flow

```bash
python scripts/prepare_i9.py && python scripts/check_i9.py
python scripts/dual_lane.py preflight
python scripts/dual_lane.py run --select I-27-R2
```

### FPGA Implementation

The merged SoC bitstream flow is available in:

[`scripts/merged_bitstream_flow.tcl`](scripts/merged_bitstream_flow.tcl)

Full reproduction notes are available in:

[docs/REPRODUCE.md](docs/REPRODUCE.md)

The release bitstream is not committed.

---

## Limitations

- No hardware validation of the release image yet. Board observations are pending.
- No formal proof of the integrated design. Isolated formal results on the authorization gate exist in the verification lane.
- Demonstration keys and nonce are fixed constants. Not for production use.
- No true random number generator in the integrated design.

---

## Team

### Kalash Bheda — Project Lead

- RTL architecture and implementation (NoC, root of trust, attestation logic)
- FPGA implementation flow
- Performance analysis

### Arnav Bhandari — Verification and Software Lead

- Verification contracts
- Reference models
- Formal verification
- Website

Additional team members contributed the physical-design flow, reproduction and documentation.

---

## Acknowledgements and Third-Party Code

- **PicoRV32:** By Claire Xenia Wolf, ISC license. Original license header retained in [`rtl/riscv/picorv32.v`](rtl/riscv/picorv32.v).

- **Python reference model for the post-quantum semantics:** See [THIRD_PARTY.md](THIRD_PARTY.md).

- **Website dependencies:** See [site/LICENSES.md](site/LICENSES.md).

---

## License

See [LICENSE](LICENSE) for licensing information.
