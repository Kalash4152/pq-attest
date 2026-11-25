# I-2 post_format_compat: expected-count derivation (before any run) — 2026-10-19

Scope: the 10 `pfc_n81_*` jobs that were BLOCKED as FREEZE_REQUIRED. Derived by reading source only;
no simulation output was consulted. A mismatch at run time is FAIL; the expectation is not edited afterwards.

## What changes under rev 6 (P6 package)

`diff NOC_PQATTEST.srcs/sources_1/new/NOC_PKG.sv rtl/dual_lane/NOC_PKG.sv`: only
`ATTEST_CHALLENGE_WIDTH` 160 → 224 (variant :290) and `message_payload_flits(MSG_ATTEST_CHALLENGE)`
5 → 7 (variant :615). So `message_length(MSG_ATTEST_CHALLENGE)` = 1+7+MAC_FLITS = 8 (MAC off) / 12 (MAC on).
`MAX_PACKET_FLITS` (1+16+MAC) and every other message length are unchanged.

DUT side (production NI, router, mesh, used unchanged by these jobs): the only challenge-length use is the
elaboration check `message_payload_flits(m) > TX_BUF_DEPTH` (`noc_network_interface.sv`:1568-1571; TX_BUF_DEPTH=16
at :181). 7 ≤ 16, so it does not fire.

## Per bench

| Bench (jobs) | Uses challenge? | Count-determining control flow | Derived count | I-1 | Differs |
|---|---|---|---|---|---|
| `tb_ni_n81.sv` (ni_m0w16 / m0w1 / m1w16 / m1w1) | Yes: T01, T02, T03, T04, T06, T07, T08, T11, T12, T13, T16, T17 and `check_recovery` | The number of `check()` calls depends only on MAC_FLITS (T01 `:390`, T05 skip `:465`, T17 skip `:728`), on W (T16 skip `:714`) and on `W <= 3*payload(RESPONSE)` (T15 `:704`; RESPONSE is unchanged). The challenge payload count `n` appears only inside compared values (`:356-357`, `:383-386`, `:636-643`, `:731`). Loop bounds over packet flits (`send_pkt`, `mk_pkt`) add checks only on a timeout, which is the error path. | 115 / 114 / 113 / 112 | 115 / 114 / 113 / 112 | No |
| `ni_tb.sv` (nitb, top `tb_noc_ni`) | No: no `MSG_ATTEST_CHALLENGE`, `ATTEST_CHALLENGE_WIDTH` or message-type cast (grep, 0 hits) | Traffic is MEM_RD/WR and ATTEST_GRANT only. | 161 | 161 | No |
| `tb_noc_n81.sv` (sys_m0w16 / m0w64 / m0n0 / m1w16 / m1n0) | No (same grep, 0 hits) | Traffic is MEM_WR/RD, ATTEST_RESPONSE and ATTEST_REVOKE (`:493-533`, `:628`). The count is set by RUNS/WDE/W. | 97 / 43 / 19 / 43 / 19 | 97 / 43 / 19 / 43 / 19 | No |

The traffic in `tb_ni_n81` stays meaningful with 7 payload flits:
- T06 lengths {3, 20} still differ from 8 and 12, so the HEAD is still rejected.
- T02 and T08 edit flits 2 and 3, and the packet now has 8 or 12 flits.
- T17 ACCK 1+7 still blocks exactly after the payload.

Config banners (`CONFIG : W=.. MAC_FLITS=..`; system W/WDE/RUNS) are unchanged.

## Frozen

All 10 counts equal the I-1 values; none differs, so there are no changed-count line citations.
Frozen in `scripts/prepare_dual_lane.py` (`PFC_DERIVED`, `checks_basis`), committed before the first pfc run.
