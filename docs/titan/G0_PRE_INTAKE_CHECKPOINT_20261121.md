# TITAN G0 pre-intake checkpoint

## 1. Intake baseline

- B0 tag titan-base-20261119 resolves to b9e41c383473802267c8c3d604e329770d708ab5.
- All 55 source digests in ARNAV_NOC_FILE_LIST_20261121.md match the files referenced by d11_evidence_20261121/compile_elaborate_manifest.json under C:/vivado_verilog_proj/_t4rr. The replay tree supplies the recorded bytes.
- Accepted S5R source commit 3d6f5123611056c7f191f8a8bacc80d3fbb414d8. See stage_reports/S5R.md for 20 fresh accepted jobs and 14 B0 golden matches.
- Use the co-signed rev 11 from the archived intake as the intake reference. Its SHA-256 is d375a684b7eb050bd93bc054f77f76b96f34f94c106f85f36583b241129ba30e. Comparison with the tracked copy found three changes, all recording Arnav’s signature.
- Previous packet SHA-256 is 495e768fecb964f096f0371372bf7876931319dd7de44c4540f09b6ba2bd6079. Record a distinct identity for the incoming packet.

## 2. Ordinary traffic monitor smoke preparation

Use Vivado/XSim 2024.1, the pinned B0 subsystem sources, a 20 ns test clock, normal authorization, and one aligned authorized tile-3 write to tile-2 memory. Use separate producers for the bench record and the passive monitor record. Record the actual elaborated top and monitor instance. The historical S2 wrapper binds to pq_soc_merged_core, so it is useful as a reference for the observation points only.

| Observation | Acceptance |
|---|---|
| Setup | Monitor instance is in the elaborated subsystem hierarchy. Both producers share a reset interval and cycle origin. Tile 3 is authorized throughout the transaction. |
| Acceptance | Both producers identify one accepted request with matching source, tag, type, address and cycle. |
| Memory | Both producers report the same decision and write commit cycle. Observe the write enable and capture the terminal event in the raw trace. |
| Response and retirement | Match delivery cycle and outcome, then confirm the terminal event and NI slot release in the raw trace. The candidate CSV schema ends at delivery and needs the raw trace for retirement. |
| Controls | Matching records pass. Missing input and a mismatched record each fail with explicit diagnostics. |

Offline run from C:/vivado_verilog_proj/_g0d11_20261121/scoreboard_review used python -E -B -m unittest -v. All 13 tests passed, including matched transactions, missing inputs, tag mismatch and agreement on an incorrect model outcome. Use the candidate README for the normalized input schema and command with expected count 1. Live subsystem monitor binding and paired trace agreement remain pending. No new XSim verdict accompanies this checkpoint.

## 3. Incoming packet review table

Record the packet digest and simulator version once. Fill each row from the new packet and retain the previous result separately. References for the prior run are G0_D11_CHECKPOINT_20261121.md and d11_evidence_20261121/simulation_summary.json. Pending means no incoming evidence has been reviewed.

| Case | Prior checks / errors / verdict | Bench and compiled-source hashes | Exact command and exit | Frozen / actual checks, errors, verdict | Raw trace and workload profile | Monitor instance, paired events and comparator result | Disposition |
|---|---|---|---|---|---|---|---|
| M1 | 21 / 19 / FAIL | Pending | Pending | Pending | Pending | Pending | Pending |
| M2 | 7 / 7 / FAIL | Pending | Pending | Pending | Pending | Pending | Pending |
| M3 | 3 / 1 / FAIL | Pending | Pending | Pending | Pending | Pending | Pending |
| SD | 6 / 2 / FAIL | Pending | Pending | Pending | Pending | Pending | Pending |

Save compile, elaboration and simulation commands and logs even when a row fails. Verify that the declared check count matches the executed checks and that the trace supports the verdict. If required evidence is missing, name the missing observation in the disposition. Capture which timeout evidence comes from the real CPU bridge and whether an absence assertion covers the stated interval.

## 4. Epoch-wrap review

Reviewed A_WRAP_LIFETIME_20261121.md with the later A_WRAP_BOUND_REFINEMENT_20261121.md. Earliest use starts at first-valid stamp capture, which can precede NI tag allocation. The final memory decision and requester response-HEAD check have separate lifetime endpoints. The terminator governs retirement. No-response NI age advances only under the documented conditions. Neither slot expiry nor CPU timeout cancels a request already buffered in the network.

The later structural note gives a conditional T_GG of at least 360 cycles for the ordinary ordered authenticated path. The D10 strict comparison is L < 63 × 360 = 22,680 cycles if those premises are established. An unpaused 16,384-age-tick slot schedule is insufficient to establish L. Remaining evidence is a defensible end-to-end bound for each endpoint under the agreed traffic and progress assumptions. A-WRAP stays X. No contract change follows from this review.

Kalash can review the packet on arrival. The combined team starts December 4. G0 scope selection remains pending.
