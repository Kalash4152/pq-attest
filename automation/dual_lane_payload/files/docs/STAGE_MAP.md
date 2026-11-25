# Dual-lane stage map — Revision 4

| Increment | Scope | Execution/acceptance gate |
|---|---|---|
| I-1 | NOC-1 baseline repair; PQ V1–V6 Python audit | PASS, 2026-10-09: 23 NOC-1 jobs valid; `python_ref` accepted |
| I-2 | PQ-1 adapters, profile split, golden/mutations, M-F1 rev 6, compatibility | PQ-1 PASS |
| I-3 | NOC-2 performance/liveness; PQ-2 endpoint qualification | NOC-2/PQ-2 PASS |
| I-4 | PQ-3 crypto/controller/endpoint OOC | PQ-3 PASS; OOC scope only |
| I-5 | NOC-3 L2 authentication/control/overhead qualification | NOC-3 PASS |
| I-6 | NOC-4 authorization and fault/status integration | NOC-4 PASS |
| I-7 | PQ-4 SEC-1..4 / N-11 shared matrix, then PQ-5 full chain | Security and chain PASS |
| I-8 | NOC-5: N-11 evidence reuse, N-12 final regression, N-13 integrated timing; release | Three separate gates plus release manifest |

The installed launcher runs only the frozen I-1 job list while `active_increment=I-1`. Later jobs remain blocked. Changing the active increment is a reviewed delivery change, not automatic permission to skip prerequisites. `E4` historically means Engineer 4, the automation/verification workstream; `SEC-1..4` is the new 2026-10-08 attack matrix.

Kalash directly authorized "Run the I-1 Vivado jobs here now", overriding the
Revision 4 executor assignment for I-1. That batch is complete; work is stopped
at his subsequent request. I-2 is the next delivery and has not started.
See `reports/I1_COMPLETION_20261009.md`. No board, bitstream, SoC or formal
proof is included.
