# Arnav r2 verification review — 21 November 2026

Verified input ZIP SHA-256 6fc7ba5b376ef927d9a9e20aa70ae3516de885514dc4836ad93e9e66657c3947 and ZIP integrity. The evidence belongs to Arnav's verification repository, handoff 291a768.

- The r2 FORMAL_FLOW source hashes match the B0 proof target at b9e41c38. Arnav records sv2v v0.0.13 and recent attestable/non-attestable PASS results. These are Arnav's U-class existing-gate results. Codex has not run formal on TITAN.
- r2 records the old runner's false FAIL and describes the corrected parser plus ten positive and negative self-test cases. The old failure remains in history.
- r2 withdraws the 232-cycle KMAC premise and the associated wrap margin. P5 and A-WRAP remain open. The current rising-edge D10 rule supersedes the r2 transition assumptions. See ATTEST_TIMING_FACTS.md for a receiving-gate lower bound and the independent lifetime dependency.
- The G0 source benches are scratch-only under D11. Existing concerns include hard-coded event columns, no frozen assertion total in the verdict, and simulator-relative output paths. See G0_BENCH_FEEDBACK.md for the scratch disposition when available.
- Arnav's signature remains pending. No change to D5 or the wire STATUS table.
