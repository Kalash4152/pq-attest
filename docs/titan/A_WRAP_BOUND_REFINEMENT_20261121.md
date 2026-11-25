# D10 A-WRAP lower-bound refinement

21 November 2026. Static review against aac1eb33. This adds a conditional structural lower bound to ATTEST_TIMING_FACTS.md. The old 144-cycle derivation remains valid within its scope. Evidence class for end-to-end A-WRAP remains X. No signed bound is revised.

## Between two tile-3 authorization rises

Scope: unchanged secure P7 attestation profile, reset-free tile 3, authenticated and ordered 4↔3 control path with the ordinary NI/L2 wrappers, no bench injection or bypass, and a fresh successful verifier round for each new rise. The verifier finishes handing off the earlier GRANT before issuing another CHALLENGE. Both are ordered over the same control VC from tile 4, and the tile-3 peer slot replays the earlier GRANT before the later CHALLENGE can reach the endpoint. This is the ordering premise used for the existing 144-cycle note.

For the next rising GRANT, count only the following causally serialized operations. Each listed KMAC uses kmac_128_a5.sv's three permutation blocks and the 24-round pq_keccak_f1600.sv, so allow at least 72 round cycles per successful operation.

| Order | Required operation | Why it precedes the next one |
|---:|---|---|
| 1 | Tile-3 RESPONSE L2 transmit MAC | T_REQ/T_WAIT gates T_ISSUE, so the RESPONSE cannot be emitted early. |
| 2 | Tile-4 RESPONSE L2 receive MAC | P_COL/P_REQ/P_WAIT verification precedes replay to the verifier. |
| 3 | Verifier recomputes the attestation tag | pq_rot_verifier.sv:118–142 takes the full response through V_CHECK, V_TSTART and V_TWAIT; the successful tagger waits for its shared KMAC result before V_GRANT. |
| 4 | Tile-4 GRANT L2 transmit MAC | The verifier's new GRANT enters the same control T_REQ/T_WAIT path before transmission. |
| 5 | Tile-3 GRANT L2 receive MAC | P_WAIT precedes P_PLAY and delivery of the authenticated GRANT to noc_attest_gate. |

The L2 paths are in rtl/dual_lane/noc_l2_auth_p7_i9.sv:132–155, 237–289, with engine selection in l2_kmac_engine.sv:65. Verifier tag completion is in pq_attestation_tag_xk.sv:236–281 and pq_kmac_share.sv:54–72. This bound leaves out the intervening revoke, endpoint measurement and tag, challenge processing, arbitration, transport and other overhead. There is no need to assume those take any particular length for this calculation.

This gives a candidate **T_GG ≥ 360 cycles**, conditional on the ordering and successful-path premises above. It is not an exact minimum or a measured interval. The D10 inequality yields 63 × 360 = 22,680 cycles, which is 6,296 cycles above the no-response, unpaused 16,384-age-tick slot schedule. The arithmetic was independently checked with integer assertions.

## Remaining lifetime obligation

The 16,384 age ticks are an NI slot schedule, not the time from first stamp capture to the latest effect. Require an independent end-to-end bound L strictly below 22,680 cycles, or an argument that packets beyond L cannot authorize a side effect or be taken as a current response under same-key reuse. Measure separate events: first valid stamp, app accept, NI allocation, memory terminal decision, requester response HEAD, terminal/abort, stale and release. Bound pre-NI payload/fill delay, mesh transit, memory reply delay and requester arrival separately under the reviewed traffic/fairness assumptions. The current RTL review found no request cancellation tied to slot expiry. Until those pieces close and the serial-path premises are independently checked, retain A-WRAP=X.
