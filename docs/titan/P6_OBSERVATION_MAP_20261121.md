# TITAN P6 credit and slot observation map

21 November 2026. Static map for the pinned 3×2 mesh and S5R/secure B0 subsystem. P6 stays X. This document specifies the passive measurements needed for future evidence. It changes neither the S2 monitor nor Arnav's independent proof scope.

## Mesh accounting

The active subsystem sets LINK_PIPE=1 at rtl/dual_lane/titan/s5r/pq_noc_subsystem_p7_t1.sv:119. The mesh has seven bidirectional physical neighbor links, or 14 directed links. Three VCs give 42 directed VC lanes. The VC depths are four. A static script extracted the forward data, forward valid, and reverse credit assignments from noc_mesh_3x2.sv at :227–300 and confirmed identical endpoints for all 14 directed paths.

| Physical link | Forward endpoints | Reverse endpoints |
|---|---|---|
| 0 ↔ 1 | 0 EAST → 1 WEST | 1 WEST → 0 EAST |
| 1 ↔ 2 | 1 EAST → 2 WEST | 2 WEST → 1 EAST |
| 3 ↔ 4 | 3 EAST → 4 WEST | 4 WEST → 3 EAST |
| 4 ↔ 5 | 4 EAST → 5 WEST | 5 WEST → 4 EAST |
| 0 ↔ 3 | 0 SOUTH → 3 NORTH | 3 NORTH → 0 SOUTH |
| 1 ↔ 4 | 1 SOUTH → 4 NORTH | 4 NORTH → 1 SOUTH |
| 2 ↔ 5 | 2 SOUTH → 5 NORTH | 5 NORTH → 2 SOUTH |

Observe on a common clock edge, with the pre/post sampling convention written in the trace:

- **Sender debit:** the actual qualified router output transfer and matching flit VC. Compare it with u_credit_control.send_event/selected_vc and credit_count. An allocator request or an unqualified grant alone is insufficient.
- **Forward in flight:** the active lk_v_* and lk_* VC in the one-stage link register. Include it between source debit and destination enqueue. The destination FIFO observes do_write and do_read, not attempted operations. The corresponding directional VC FIFO instance is in noc_router.u_datapath, named e.g. west_vc1_fifo.
- **Receiver return:** match the destination dequeue with its registered credit_valid (one-cycle return token) and the sender's credit_return port. The return wire itself has no additional link pipeline.
- **Ledger per direction and VC:** available sender credits + forward flits in flight + downstream FIFO occupancy + outstanding return tokens = configured VC depth. Check individual transitions and occupancy bounds as well as the idle endpoint so a lost token on one lane cannot cancel a duplicate on another. At drained quiescence each lane has zero in-flight, occupancy and pending return, and restored initial credit.
- **Local interfaces:** record NI→mesh injection on valid && ready and account for the selected local input FIFO. On mesh→NI ejection use the router's separate LOCAL credit ledger: eject_wr allocates credit, the optional eject register plus the shared eject FIFO hold flits, and eject_rd returns credit for the popped flit's VC. Count shared FIFO resident credits per VC (derive from accepted enqueue/dequeue) and compare the shared occupancy. External credit_return[LOCAL] is tied zero and does not observe the internal LOCAL return. Boundary ports with no physical neighbor are excluded from the inter-router ledger.

Source anchors are noc_router.sv:344–353, 525–598, NOC_DATAPTAH.sv:424 onward, NOC_FIFO.sv:142–165 and the credit register, and noc_credit_counter.sv for send/credit priority. These interfaces are in NOC_PQATTEST.srcs/sources_1/new; use simulation hierarchy or a read-only bind so the protected files need no edits.

## NI slots are a separate ledger

Track each NI's two slots by requester, tag and allocation generation. Observe allocation on tx_accept, valid/stale transitions, matched response HEAD, HEAD_TAIL release or rx_do_free on terminator, and final stale expiry if no response frees it. Relevant points are noc_network_interface_p7_i9.sv:759–827, 888–949 and 1237–1241. Treat simultaneous age and response updates according to the next-state priority. A stale flag alone neither releases a slot nor returns a router credit.

Confirm at drain that there are no unexplained valid/stale slots or packet obligations. Where S7 is selected, check denial retirement is caused by a single matching response with the original tag before timeout, alongside unchanged no-side-effect and credit accounting checks. Report ordinary, denial, abort/discard, and reset intervals independently. Qualify the checker with independently injected accounting faults in synthetic or separately approved simulation fixtures (missing return, duplicate return, wrong VC, and release without an allocation). Avoid relying only on net counter sums or a single final snapshot.

An accepted ordinary/denial test can establish sampled conservation for its exercised trace. A general statement for all traffic needs Arnav's independent proof or approved bounds. The S2 CSV lacks these wire events and cannot establish P6.
