# G0 intake and D10 monitor audit

Checked 21 November 2026 against S5R aac1eb33 and Arnav r2. This is a static audit and intake procedure. Existing S2 results retain their original meaning.

## Monitor compatibility

The historical monitor binds to pq_soc_merged_core through tb_titan_mon_b0. The four r2 benches instantiate pq_noc_subsystem_p7 directly. A passing subsystem bench cannot establish that this binding ran. Require an explicit compatible observation path and real event output before comparing it with Arnav's independent scoreboard.

rtl/dual_lane/titan/titan_mon_bind.sv:75–90 feeds epoch_bump on accepted GRANT and REVOKE. titan_finality_monitor.sv:60–69 captures that shadow epoch at inner NI allocation and :129–130 updates it after other observations on that sampled edge. D10 instead advances on a rise of registered authorized and S5R stamps at first eligible app HEAD, before inner NI allocation. Keep the three values distinct: historical shadow at allocation, effective D10 at the decision, and on-wire request stamp associated with the exact transaction.

| Sequence from reset | S2 message-bump count | D10 rising-edge count | Consequence |
|---|---:|---:|---|
| Idle | 0 | 0 | Agreement on no work. |
| GRANT then held-high GRANT | 2 | 1 | A transaction straddling the second GRANT may get a historical stale classification even though D10 stayed current. |
| GRANT, REVOKE, GRANT | 3 | 2 | Both can flag authority turnover, but epoch numbers differ. Check actual low and rise edges for M1. |
| GRANT, trusted_fail clears authorized, GRANT | 2 | 2 | Equal final counts alone do not capture authorization loss during the transaction. |
| Redundant REVOKE while unauthorized | 1 | 0 | B0 probe records a message epoch change that D10 ignores. |

An offline integer trace cross-check reproduced these five rows from the two update rules. It was not an HDL run. Preserve S2 result files and its frozen oracle. Any D10-aware follow-up checker belongs in a separate simulation-only job with separately qualified evidence and the existing approval rules.

Other distinctions for intake:

- P1 combines authority, epoch, and missing/wrong transaction conditions. A P1 counter alone is insufficient to claim M1. Compare one requester/tag generation across issue, an actual authorized 1→0→1 sequence, and a memory commit. Preserve the request stamp when available.
- P2 samples app RX data-valid and considers the historical epoch plus immediate revoke. Compare responder offer, requester HEAD and data delivery separately. If revoke is between requester HEAD and data, identify the D6 HEAD-latched case so an observed B0 event and the future S8 rule are not conflated.
- The historical monitor's slot_expired is a rise in txn_stale_q, not final release or credit return. For SD, require measured tile-2 arrival, absence of a definitive response within the stated observation, stale transition and subsequent release cause where claimed. The r2 600-cycle NI configuration in M1/M2/SD is a bench profile, not the 8,192-cycle release setting.
- The historical bridge-timeout tap correlates a timeout counter change to last_issue_tag. A newest tag is only a proxy. For M3 need the timeout on the same accepted transaction and a later commit. The r2 M3 bench manually waits 4,200 cycles and calls check(1, ...) for timeout. It instantiates the subsystem without the CPU bridge, so that line cannot witness an actual bridge timeout. Check real or explicitly modelled timeout evidence, show separate HEAD/address/data handshakes, and do not assume elapsed time means software observed UNKNOWN.

## Intake when the revised packet arrives

1. Preserve ZIP SHA-256 and Arnav's commit. Confirm the B0 source identity, test top, tool, define/parameter settings, extra helpers and vector hashes against ARNAV_NOC_FILE_LIST_20261121.md. Keep any profile differences visible.
2. For each M1/M2/M3/SD run require a normal final verdict, frozen count and CONFIG identity, complete raw log and output traces. A working bench can intentionally reproduce a B0 gap.
3. Align timestamps on the same posedge convention. Group by run, case, reset interval, requester, tag and request generation; a reused tag or restarted cycle counter is not a unique ID. Compare observed events and absence cases with the scoreboard, not hard-coded CSV flags or summary totals alone.
4. Record each case as observed, not observed within the exercised sweep, or inconclusive with reason. If monitors disagree, preserve both views and the first divergent cycle. Report the actual reachable cases to Kalash for the G0 scope decision. Arnav owns the bench corrections under D11.
