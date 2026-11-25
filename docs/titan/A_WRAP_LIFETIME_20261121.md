# TITAN transaction lifetime and A-WRAP

21 November 2026. Static review of the S5R baseline at dad730cd. A-WRAP evidence class X. This review changes no timeout, epoch width or signed requirement.

## From epoch capture to final use

| Point | What happens | RTL |
|---|---|---|
| First eligible application HEAD | The S5R stamp uses the effective epoch on first valid and holds it across backpressure. This can precede application acceptance. Withdrawal clears the held stamp. | rtl/dual_lane/titan/titan_epoch_stamp.sv:19–32, rtl/dual_lane/titan/s5r/pq_noc_subsystem_p7_t1.sv:209–223 |
| Application HEAD accepted | The tile-3 wrapper captures stamped control, fills the payload buffer, then issues to the inner NI. | rtl/dual_lane/noc_l2_auth_p7_i9.sv:132–155 |
| Inner NI accepts request | The NI allocates a tag and clears its age. The timer starts here, downstream of stamp capture. | rtl/dual_lane/noc_network_interface_p7_i9.sv:780–807 |
| Tile-2 request HEAD and last payload | The front end latches source and control at HEAD and makes its memory decision at the final payload. S6 would compare the stored stamp here for both read and write. Tile 2 receives no requester slot retirement signal on this path. | rtl/dual_lane/titan/s5r/pq_noc_subsystem_p7_t1.sv:339–387 |
| CPU bridge timeout | The bridge can report the fault on its own 4,096-cycle timer. When the HEAD was accepted, it enters a drain phase that consumes a late response or expires after its configured 8,192 drain cycles. The timeout/drain state has no request cancellation path into the mesh. | rtl/riscv/tmem_app_bridge.sv:143–190, rtl/riscv/cpu_tile_noc.sv:133–144 |
| NI age expiry | With no matching response and no receive hold, the slot becomes stale after 8,192 age ticks. Another 8,192 ticks free it. A stale matching response is ineligible for normal delivery and can free it at the terminator. | rtl/dual_lane/noc_network_interface_p7_i9.sv:759–775, 813–827, 888–945 |
| NI response HEAD and terminator | A matching response can reserve release through rx_free_q and pause the slot age. Matching uses response tag, source and message type. A HEAD_TAIL can release immediately. A multi-flit response or discard path releases at the actual terminator. | rtl/dual_lane/noc_network_interface_p7_i9.sv:813–827, 888–949, 1237–1241, 1341–1345, 1404–1434 |
| CPU-facing response | The app RX export is valid-only and propagates HEAD, data and last/abort. D6 puts the S8 authorization/echo decision at HEAD. The packet remains relevant through data delivery and bridge drain for the associated checks. | rtl/dual_lane/titan/s5r/pq_noc_subsystem_p7_t1.sv:391–405 |

The RISC-V profile supplies 4,096 for bridge timeout and 8,192 for NI_SLOT_TIMEOUT. The NI receive watchdog counts cycles of valid traffic under receiver backpressure. It does not advance on a missing flit and does not make every matched response release in wall-clock time. Slot aging also has no cancellation effect on a request already buffered downstream.

## Bound supported by the review

- The no-response, unpaused slot schedule is exactly stale at allocation plus 8,192 age ticks and free at allocation plus 16,384 age ticks. It gives neither a wall-clock bound with a receive pause nor an upper bound on the lifetime of an epoch-bearing request at tile 2.
- For write/read admission, bound from epoch capture to the last possible tile-2 decision that can still use that stamp. For response filtering, also bound from capture to the requester HEAD decision, including late responses and reuse of the same requester/tag/source/type tuple. For data retirement and credit conservation, track the terminator separately. These intervals start and end at different events.
- The conservative D10 calculation is 63 × T_GG > L, where L is the relevant lifetime in cycles and T_GG is a proven minimum gap between receiver authorization rises within the same reset-free interval. The current conditional structural result T_GG ≥ 144 gives 9,072 cycles on the left. It exceeds 8,192 if that lifetime is established. Substituting 16,384 as a sensitivity example would require T_GG ≥ 261 with strict inequality. This comparison does not establish 16,384 as the relevant lifetime or demonstrate a wrap failure.
- Closure requires an enforced end-to-end lifetime under the agreed traffic/fairness model, or an argument that any old packet beyond the bound is ineffective at both decision points. Include a stalled pre-NI stamp, bridge timeout before remote side effect, live/stale response HEAD just before expiration with a delayed terminator, and same-tag reuse with a late old response. Record stamp, allocation, both age edges, last-word decision, response HEAD and terminator. Check equal-cycle boundaries explicitly. The bounds and any ensuing design decision need the existing review process.

Evidence cross-reference is ATTEST_TIMING_FACTS.md for the 144-cycle derivation and G0_BENCH_FEEDBACK.md for the current absence of witness results. No simulation or proof was run for this audit.
