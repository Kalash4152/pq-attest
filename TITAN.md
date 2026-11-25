# TITAN: bounded transaction finality under revocation

Research extension of PQ-Attest, branch `titan`. Unpublished: keep the repository private until the paper is submitted.

**Problem.** PQ-Attest authorizes a tile with one bit and requests carry no epoch. Four gaps follow:
- **M1:** a request issued under an old grant can commit after REVOKE → re-GRANT.
- **M2:** an already-offered read response can complete after REVOKE.
- **M3:** a write that the bridge reported as timed out can still commit later.
- **SD:** an unauthorized write can be dropped with no response at all.

**Mechanism.**
- A per-tile epoch that advances on the rising edge of authorization (decision D10).
- Epoch-stamped memory requests (`control[6:1]`).
- A commit guard at the memory side-effect point.
- Exactly one explicit denial response.
- A read-response filter at the requester.
- CPU-visible outcomes SUCCESS / DENIED (fault code 6) / ERROR / UNKNOWN.

**Interface:** `docs/decisions/M-F1-rev11-TITAN-EPOCH-STATUS.md`. **Plan:** `docs/titan/` (stage reports, plans, reviews).
**Generated RTL:** `scripts/prepare_titan.py` and `scripts/titan/prepare_stage*.py`; the TITAN blocks are in
`rtl/dual_lane/titan/`.

| Stage | Result |
|---|---|
| S0 baseline + generator | PASS, 8 fresh; B0/T1 pairs identical in observations and cycles |
| S1 B0 golden | PASS, 15 fresh |
| S2 passive finality monitor | PASS, 6 fresh |
| S3 interface package | PASS, 2,067 exhaustive checks |
| S4R epoch tracker (D10) | PASS, 19 fresh, 3 mutants killed, 14/14 B0 matches |
| S5R request stamp | PASS, 20 fresh, 1,000 randomized HEADs, 3 mutants killed, 14/14 B0 matches |
| G0 race reachability | open (see `docs/titan/G0_*`) |
| S6–S14 | planned |

No TITAN FPGA utilisation, timing, formal or hardware result exists yet.
