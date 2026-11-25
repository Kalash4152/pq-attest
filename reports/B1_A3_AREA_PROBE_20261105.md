# B1 + A3 area probe, 2026-11-05: gain too small; recommend not registering either

- **Commit base:** a67cfe55. Scratch out-of-context synthesis (Vivado 2024.1, xc7a100tcsg324-1, flatten rebuilt,
  AreaOptimized_high), the same settings as the S4 crypto partition. **Scratch probe, not harness evidence.**
  Files: `reports/b1a3_probe_20261105/` (probe RTL, Tcl, results, utilization reports).
- **Status:** HARDWARE_VALIDATED=NO, SOC_INTEGRATION_COMPLETE=NO, FORMAL_PROOF=NO. No RTL in any source list changed.

## Ceiling from the released netlist (N-13 secure, 32,708 LUT, run 040617_08dd583e)

- The three kmac_encode instances: endpoint E1 1,482 + verifier E4 1,185 + L2 engine E3 893 = **3,560 LUT**.
- Status counters: about 33 counters of 32 bits (gates, parsers, L2 wrappers, fault status, endpoint, verifier).

## Measured (scratch)

| Probe | Baseline | Variant | Delta |
|---|---|---|---|
| A3, shared encoder (E1 / E4 tie-offs: key 32, custom 0 or 14, L256) | 1,066 LUT / 902 FF | 867 LUT / 900 FF | **-199 LUT** per instance |
| A3, L2 encoder (E3 tie-offs: key 32, custom 14, L128) | 989 LUT / 1,085 FF | 993 LUT / 1,084 FF | **+4 LUT** (no gain) |
| B1, 16 counters, 32-bit wrap -> 16-bit saturating | 17 LUT / 512 FF | 81 LUT / 256 FF | **+64 LUT**, -256 FF |

A3 variant = kmac_encode with the key-length, custom-length and output-select registers bypassed, so per-instance
constants fold. The message length and the message mux stay variable; they are most of the encoder.

## Reading

- **A3:** about **-0.4k LUT** in total (2 x 199; E3 nothing), against the 1.0-1.5k estimate. That is 1.2 % of 32.7k. It still
  costs a registered increment that re-earns the KMAC KATs, s8 golden, l2e, endpoint/verifier and full-chain jobs.
  The out-of-context baseline (1,066) is below the in-context figure (1,482 / 1,185): part of the in-context encoder
  cost is the owner mux that synthesis absorbs, and A3 does not remove it.
- **B1:** narrowing the counters **adds** LUT. A 32-bit incrementer is almost free on the CARRY4 chain (about 1 LUT per
  counter), and saturation needs a compare. The only effect is FF (about -0.5k), and FF is not the budget (28 %).
  Unread counters are already pruned by synthesis in the SoC profile.
- **Headroom:** 32,708 LUT against the 47,550 hard stop and the 52k D4 budget, so no need for either.

## Recommendation (needs Kalash)

Close B1 (no LUT gain; widths stay 32-bit as in I-6) and park A3 (about -0.4k, not worth a re-qualification now; reopen
only if the merged build gets within about 1k of the budget).
