# I-5 / NOC-3 Track P3 notes (prepare-only; NOT registered in I-3)

Read live at HEAD `57b7031`: CLAUDE.md, M-F1 rev 6 R6.5-R6.9, M-F1-rev6-conflicts.md (C-3, C-6,
C-7, C-8), N-9-l2-authentication.md, rtl/dual_lane/noc_l2_auth.sv, rtl/dual_lane/noc_network_interface.sv
(RX delivery/slot rules), rtl/dual_lane/NOC_PKG.sv, scripts/l2_golden.py, full_chain_golden.py,
s8_golden.py, vectors/l2_golden.*.

Evidence class: TB and vectors **implemented**; oracle **reference-checked** (teammate kmac128);
TB **not compiled, not XSim-simulated**, not mutation-tested. Formal/hardware: NO.

## Oracle identity
`scripts/l2_golden.py` imports `kmac128` from `s8_golden`, which verifies the pinned ZIP member
hashes against `docs/decisions/dual_lane_config.json` and asserts the module resolves inside
`software/pq_attest_final/` (adapter since `912ee39`). Check mode: `L2_ORACLE: PASS`.

## Bypass controls in `noc_l2_auth.sv` (C-3)

| Control | Exists | Where | TB mode |
|---|---|---|---|
| MAC | yes, `BYPASS_MAC` | :5, :226 | `L2_NEG_MAC`: tampered payload and bad-tag MEM_WR_RESP delivered (the latter retires slot 0) |
| Sequence | yes, `BYPASS_SEQUENCE` | :5, :230 | `L2_NEG_SEQUENCE`: replay, seq 0, and replayed response (retires a slot) delivered |
| Epoch | yes, `BYPASS_EPOCH` | :5, :228 | `L2_NEG_EPOCH`: stale epoch under current key delivered; old-boot replay still rejected at MAC (C-8) |
| Identity | **no** | dest = TILE :210, key by source :215 | no mode; blocked on C-3 / Q-1 |

## Case coverage (ENFORCE unless stated; every row checks counters, reason, NI delivery, slots)

| Requirement | Steps (packet) | Expected (oracle) |
|---|---|---|
| Valid packets | S2 ch1, S21 ch2, S28 ch4, S29 seq max, S35 boot B, S23/S26/S37 MEM_WR_RESP | accept; head + payload words equal oracle; response retires slot |
| TX bit-exact | S1, S24, S36, S39 | every wire flit equals oracle (incl. preview tag, +5 length, F0-F4, MAC) |
| Tamper header / payload / tag | S4, S5, S6 (+ freshness S7, S8; padding S9) | 2, 2, 2 (2, 2; 1) |
| Wrong source / wrong key | S10 src claim, S11 SPOOF-signed, S12 reverse-direction key, S13 wrong dest | 2, 2, 2, 1 |
| Replay | S3 (seq 1 again), S25 (response replay with slot outstanding), S30 | 4; slot NOT retired |
| Reset / old-boot replay | S32 reset to BOOT_00002 + keys B; S33 boot-A packet | **2 (MAC), per C-8** - keys rotate with the boot epoch, so the old tag fails before the epoch check |
| Epoch check itself | S34 epoch A MACed with key B | 3 |
| Reset clears authorization | S35 seq 1 accepted after reset; S36 TX restarts at seq 1 | accept |
| Sequence wrap boundary | RX: S29 2^64-1 accepted, S30 replay, S31 2^64-2; S14 seq 0. TX: S38 inject tx_seq=2^64-2, S39 sends 2^64-1, S40 refusal (request driven 20 cycles, no flit), S41 other peer still ready | 0/4/4/4; ready 0 then 1 |
| Truncated / overlong | S17 truncated, S18 30 flits, S19 length 27, S20 length 5 (unextended), S16 length field, S15 VC | 1 for all |
| Overload drain | S27 burst grant3+ch4+grant5 back-to-back; S28 ch4 resent | 1 accept, drops >= 2 with reason 7 (C-6 lower bound); ch4 then accepted (drop had no sequence side effect) |
| Rejected => zero NI delivery and zero slot retirement | every rejected step: `NI_DELIVERY` (0 heads, 0 payloads, 0 TX flits) and `SLOTS` (slot 0 is outstanding from S1 through S22 and again at S25) | exact |
| Sequence not committed by rejects | S21 ch2 (seq 2) accepted after 9 rejected seq-2 packets | accept |
| No NI abort | final `NI_NO_ABORT` | 0 |

Derived CHECKS: ENFORCE 145, NEG_MAC 16, NEG_SEQUENCE 26, NEG_EPOCH 10 (P3_COUNT_DERIVATION.md).

## Findings
1. **Old vector defect** (VECTOR_DIFF.md sect. 1): deepcopy aliasing made 9 old cases one corrupted
   8-flit packet; the old "genuine" vector was not genuine. Fixed by building every packet separately.
2. The old draft TB tested old-boot replay with unrotated keys (epoch reason 3) and built the new-boot
   packet from `int(BOOT)+1` with old keys, both contrary to C-8 key derivation. Replaced.

## Open questions / risks
- **Compile risk (unverified):** `step_inject` writes `dut.tx_seq[i]`, an always_ff variable, from the
  TB (IEEE 1800 9.2.2.4 forbids other writers; XSim may error or warn). It was in the original draft too.
  If xelab rejects it, options: a test-only seed port/parameter in a `rtl/dual_lane` variant (I-5 RTL), or
  drop S38-S40 and keep the RX-side wrap only. Needs Kalash.
- **Q-1 / C-3:** no identity bypass; NOC-3 needs four controls. Count above has no identity mode.
- **C-6:** overload count is a lower bound; tighten to exact (`==2`) after the drop-in-progress fix.
- **C-7:** reasons are the local L2 namespace (1/2/3/4/7), not OD-2.
- **C-8 / Q-4:** vectors assume L2 keys rotate with the boot epoch (`NOC-L2-KEY-v1` derivation is
  OFFLINE DEMO and unfrozen; l2_golden.py mirrors full_chain_golden.py and asserts equality for BOOT_A).
  If Kalash freezes static keys instead, S33 becomes reason 3 and the oracle changes.
- **C-5:** TX payload address `0x82000100` kept for continuity with the old vector; not a §5a claim.
- Reset with unchanged provisioning (same boot epoch) is outside the secure profile and not tested.
- PASS_REUSED identity: jobs that snapshot `vectors/` (e.g. s8_golden) recorded the old
  `l2_golden.json` hash; check whether merging invalidates reuse.
- Registry: `l2_auth` remains an `unimplemented` gate; counts must be frozen before the first run.

## Oracle guard and void vectors (integrator, 2026-10-19)

- **VOID:** every `vectors/l2_golden.*` before commit `724c96e` is void. The old `generate()` deep-copied a list holding
  one shared base packet, so cases 0, 1, 3, 4, 5 and 8–11 were a single packet (10 distinct out of 18), including
  the "genuine" vector. No accepted gate ever used them (no L2 job ran in I-1 or I-2). The I-2 Track A statement
  that the L2 payloads were byte-identical across the adapter rewrite is true, but those payloads carried this defect.
- **Guard** (`scripts/l2_golden.py`, run on every generate, so in both check and --write mode):
  `guard_packets()` fails if any two directed cases serialize to the same packet, or if `ch1_genuine` /
  `ch2_genuine` / `resp1_genuine` differ from an independent fresh rebuild made after all mutations.
  `kmac_kat()` checks NIST SP 800-185 KMAC128 sample 2 (key 0x40..0x5F, data 00010203, S = "My Tagged Application",
  L = 256 → 3b1fba96…4aa5) through the same `kmac128` import that L2 uses.
- **Self-test** `scripts/test_l2_golden_guard.py` (5/5 OK):
  - the guard rejects a synthetic reproduction of the aliasing and the real pre-724c96e vectors
    (`git show 57b7031:vectors/l2_golden.json`, the committed output of the old code);
  - it rejects a mutated genuine packet and passes the fixed generator;
  - the KAT fails when `kmac128` is stubbed.
