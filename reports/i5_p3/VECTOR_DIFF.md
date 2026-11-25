# I-5 / NOC-3 Track P3: `vectors/l2_golden.*` diff explanation (prepare-only, not registered)

Base: HEAD `57b7031`. Generator: `scripts/l2_golden.py --write`; check mode re-run afterwards (PASS).
Primitive unchanged: teammate `kmac128` through `s8_golden` (pinned ZIP 047bb5a9...), L = 16 bytes,
S = `NOC-L2-AUTH-v1`. The transcript, freshness and flit packing of `packet()` are byte-for-byte the
old code (only an optional `key=` override was added). No algorithm was changed.

## 1. Defect found in the old vectors (why the case table was rebuilt)

Old `generate()` built `cases = [base, base, ..., base, ...]` and then ran `copy.deepcopy(cases)`.
`deepcopy` keeps aliasing, so the nine `base` slots (old indices 0, 1, 3, 4, 5, 8, 9, 10, 11) were still
**one object**. Every mutation was applied to all nine: control bit 7 (`^1<<11`), src_x bit 0
(`^1<<27`), length bit 0 (`^1<<15`), last-flit bit 16, truncation to 8 flits, F4 bit 20 and VC 3 on
flit 3. So the old "genuine" case 0 was an 8-flit packet with head `0x04148080` (the genuine head is
`0x04948800`), and old cases 0/1/3/4/5/8-11 were identical. The old TB checks `GENUINE_PACKET` and
`COMPLETE_VALIDATED_PAYLOAD` would have failed on that vector. This was never simulated (no result
exists for `tb_noc_l2_auth`).

## 2. Old -> new mapping (old svh lines 1-286, old json `cases`/`tx`)

| Old line(s) | Old content | New location | Explanation |
|---|---|---|---|
| 1 | header comment | 1-2 | Same oracle id; adds "every expected value is here" |
| 2 | `BOOT` = `BOOT_00001` | 5 `L2_BOOT_A` | Same value, renamed (l2_ prefix avoids collision with the full_chain svh) |
| 3 | `KEYS` (all 36 keys, 9216 bits) | 7-8 `L2_TX_KEYS_A`, `L2_RX_KEYS_A` | Same keys, already sliced into the 1536-bit ports of TILE 3 (R6.6: TX to p = K[3->p], RX from p = K[p->3]). Equal to the old TB slicing `KEYS[(3*6+p)*256+:256]` / `KEYS[(p*6+3)*256+:256]` |
| - | (none) | 6, 9-10 `L2_BOOT_B`, `L2_TX/RX_KEYS_B` | NEW boot epoch `BOOT_00002` and its directed keys, for reset/old-boot cases (C-8). Derived with the full_chain_golden formula `KMAC128(bytes(range(32)), [src,dst]||boot, 32, "NOC-L2-KEY-v1")`; the script asserts this formula reproduces `full_chain_golden.produce()` keys for BOOT_A |
| - | (none) | 3, 4, 11 | `L2_TILE=3`, `L2_ORACLE_ID`, `L2_EXP_ABORTS=0` |
| 4-23 | `packet_len` (18 cases) | 12-43 `l2_pkt_len` (30 packets, named) | See table 3 |
| 24-272 | `packet_flit` | 44-575 `l2_pkt_flit` | See table 3 |
| 273-286 | `tx_expected` (one TX packet) | 576-750 `l2_tx_*`, `l2_tx_flit` t=0 | t=0 flits **bit-identical** to old `tx_expected` (12 flits, tag `64c548ad...`). t=1..6 are new (one per TX step) |
| - | (none) | 751-1330 `l2_n_steps`, `l2_step_*`, `l2_exp_*` | Step scripts for 4 modes and every expected verdict/reason/delivery/slot/ready value from the spec model (R6.5-R6.8) |

Old case fate (bit-exact comparison of flit lists, scratch script, old json vs new json):

| Old idx | Old intent | Old actual | New packet |
|---|---|---|---|
| 0, 1, 3, 4, 5, 8, 9, 10, 11 | genuine/replay/header/tag/source/length/truncated/padding/VC | the single corrupted 8-flit alias (sect. 1) | Dropped. Replaced by separate packets 0, 1, 3, 7, 12-14, 6 |
| 2 | payload tamper seq 2 | as intended | 2 `ch2_tamper_payload` (identical) |
| 6 | seq 0 | as intended | 11 `ch_seq_zero` (identical) |
| 7 | seq 3, old TB used it for the epoch test | genuine boot-A seq 3 | Dropped. Epoch test now uses 27 `ch1_epochA_keyB`; old-boot replay uses 0 |
| 12 | genuine seq 2 | as intended | 18 `ch2_genuine` (identical) |
| 13 | seq 2^64-1 | payload p | 25 `ch_seq_max` uses payload `0xfedc000i` (distinct delivered values); flits differ only in payload and tag |
| 14 | seq 1 | genuine seq 1 (17 flits) | 0 `ch1_genuine` (identical) |
| 15 | new boot, boot = int(BOOT)+1 (`COOT_00001`), **old keys** | inconsistent with C-8 key rotation | Dropped. 28 `ch1_genuine_bootB` uses `BOOT_00002` and keys B |
| 16 | MEM_WR_RESP 2->3 genuine | as intended | 20 `resp1_genuine` (identical) |
| 17 | MEM_WR_RESP bad tag (`^1<<22`) | as intended | 19 `resp1_bad_tag` (identical) |

## 3. New packet table (`l2_pkt_*`, svh lines 12-575)

All sources are ROT (4) -> CRYPTO (3) unless noted; challenge = MSG 4, 7 payload words, 17 flits.
Expected ENFORCE reason is computed by the model (MAC recomputed with teammate kmac128), and the
generator asserts it equals the intended reason.

| p | Name | Construction | ENFORCE verdict |
|---|---|---|---|
| 0 | ch1_genuine | seq 1, boot A, K_A[4->3] | accept / replay -> 4 / under boot B -> 2 |
| 1 | ch2_tamper_head_control | ch2, HEAD data bit 7 flipped | 2 |
| 2 | ch2_tamper_payload | ch2, P0 bit 16 | 2 |
| 3 | ch2_tamper_tag | ch2, M3 bit 16 | 2 |
| 4 | ch2_tamper_fresh_seq | ch2, F0 bit 0 (seq 2 -> 3) | 2 |
| 5 | ch2_tamper_fresh_epoch | ch2, F2 bit 0 | 2 (MAC precedes epoch) |
| 6 | ch2_fresh_padding_nonzero | ch2, F4 bit 16 (Fr[144]) | 1 |
| 7 | ch2_wrong_src_claim | ch2, HEAD src (1,1) -> (2,1) | 2 |
| 8 | ch2_wrong_key_spoof_signed | src field 4, MACed with K_A[5->3] | 2 |
| 9 | ch2_wrong_key_reverse_direction | MACed with K_A[3->4] | 2 |
| 10 | ch2_wrong_dest_tile5 | genuine 4->5 packet | 1 |
| 11 | ch_seq_zero | seq 0 | 4 |
| 12 | ch2_wrong_vc_body | ch2, flit 3 VC = 3 | 1 |
| 13 | ch2_len_field_tamper | ch2, HEAD length 17 -> 16 | 1 |
| 14 | ch2_truncated_8 | first 8 flits, flit 7 -> TAIL | 1 |
| 15 | ch2_overlong_30_flits | ch2 with TAIL->BODY + 12 BODY + TAIL (30 flits > 26) | 1 (drain) |
| 16 | ch2_len_over_max_27 | HEAD length 27, 27 flits | 1 (drain) |
| 17 | grant_undersize_unextended | NI-format GRANT, length 5, no freshness (5 flits) | 1 (drain) |
| 18 | ch2_genuine | seq 2 | accept |
| 19 | resp1_bad_tag | MEM_WR_RESP 2->3 seq 1, M3 bit 18 | 2 |
| 20 | resp1_genuine | MEM_WR_RESP 2->3 seq 1 tag 0 | accept + retire / replay -> 4 |
| 21 | resp2_genuine | seq 2 | accept + retire |
| 22, 24 | grant3/grant5_genuine | ATTEST_GRANT ctl 0x080, seq 3 / 5, 10 flits | burst |
| 23 | ch4_genuine | seq 4, payload `0x2468a00i` | dropped in burst, then accept |
| 25 | ch_seq_max | seq 2^64-1, payload `0xfedc000i` | accept, replay -> 4 |
| 26 | ch_seq_max_minus1 | seq 2^64-2 | 4 |
| 27 | ch1_epochA_keyB | epoch A in freshness+transcript, MACed with K_B[4->3] | 3 (boot B) |
| 28 | ch1_genuine_bootB | epoch B, K_B[4->3] | accept (boot B) |
| 29 | resp1_genuine_bootB | MEM_WR_RESP, epoch B, K_B[2->3] | accept + retire (boot B) |

## 4. TX table (`l2_tx_*`, svh lines 576-750), all MEM_WR_REQ 3->2, ctl in 0x780, payload {0x82000100, 0xcafe1234}

| t | Step | seq | boot/keys | tag (ctl[0]) | Note |
|---|---|---|---|---|---|
| 0 | ENFORCE S1 | 1 | A | 0 | identical to old `tx_expected` |
| 1 | ENFORCE S24 | 2 | A | 0 | |
| 2 | ENFORCE S36 | 1 | B | 0 | sequence restarts after reset |
| 3 | ENFORCE S39 | 2^64-1 | B | 0 | after injected tx_seq = 2^64-2: last legal value |
| 4 | NEG_MAC S1 | 1 | A | 0 | same flits as t=0 |
| 5, 6 | NEG_SEQUENCE S1, S6 | 1, 2 | A | 0 | same flits as t=0, t=1 |

## 5. JSON (`vectors/l2_golden.json`)

Keys `scope`, `oracle`, `reference_sha256` unchanged. `cases` replaced by `packets` (index, name,
flits); `tx` is now a list (adds `control_in`, `control`, `payload`, `dest`, `msg`); new `tile`,
`boot_a`, `boot_b`, `modes` (every step with expected values) and `tb_checks`
(`{"ENFORCE":145,"NEG_MAC":16,"NEG_SEQUENCE":26,"NEG_EPOCH":10}`, computed by the generator from the
step table with the TB's per-op rule; cross-checked by hand in P3_COUNT_DERIVATION.md).
`scripts/test_track_a.py::test_committed_chain_and_l2` compares the JSON with `generate()`; it passes.

Side effect to check before merge: the `s8_golden` job snapshot (`include_dirs=['vectors']`) records a
hash of `vectors/l2_golden.json` in its result.json. If the PASS_REUSED identity includes include-dir
contents, merging this changes the identity of jobs that include `vectors/`. Not verified here.
