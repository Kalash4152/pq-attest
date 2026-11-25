# Engineer 4 FINAL package intake, 2026-11-06: suite reproduced and imported; latency model rejected; RTL mutant proposals triaged

- **Package:** `finalpqattest.zip` (Downloads, 2026-11-06 14:04), 50,030,890 bytes, SHA-256
  `176b162fa8eab457a0f03c992ec078b9381bb2a2c28ddc8a3a810a08c0cf7d55`, 4,743 entries. Inner `E4_P7_FINAL_HANDOFF_20261106.zip`
  matches the handoff's stated SHA-256 `c23e9b99...769c` (780,600 bytes).
- **Handoff:** `E4_P7_FINAL_HANDOFF_20261106.md` (Downloads).
- **E4 git HEAD:** still `b62b78d`: this round's work is **uncommitted** in the E4 tree.
- **Handling:** extracted read-only in the session scratch (long-path extraction; no unsafe paths); every new / changed
  script read before running (only Python, pytest, `git rev-parse`; no network, no deletes).
- **Status:** HARDWARE_VALIDATED=NO, SOC_INTEGRATION_COMPLETE=NO, FORMAL_PROOF=NO. E4's work is Python model checking.

## 1. Re-run here

| E4 claim | Re-run | Result |
|---|---|---|
| pytest 387 / 387 | `python -m pytest verification` in the package copy | **387 passed**, exit 0 |
| p7_regression `--full` 15 / 15 | package copy | **15 / 15 PASS** |
| `--validate-only --baseline s4` / `nov3` 6 / 6 active | package copy | **6 / 6** each (9 skipped by design) |
| suite on **our live sources** (release + I-9 / I-10 / merged files) | staged copy (scripts/e4_verification_v2.py) | **387 / 387, 15 / 15** |

## 2. Claims checked against our design and repository

| Item | Finding | Verdict |
|---|---|---|
| F1 pinned KMAC reference | `verification/p7_kmac_adapter.py` loads `software/pq_attest_final/.../kmac128_ref.py` and refuses the demoted `software/kmac128_ref.py`; the 6 teammate modules shipped are byte-identical to our pinned copy (the other 9 are simply absent from the package) | **FIXED, accepted** |
| F3 portability | `p7_paths.py`, `--repo-root / --data-dir / --out`; stage 12 runs `pytest verification` | **FIXED** (our wrapper still stages, because the suite reads E4 data paths) |
| D2 vectors (12) | `vectors/d2_k3_64.json/.svh` in E4 format (measurement only). **Same file names as our registered I-10 vectors** (different content and format). All 12 measurements agree with hashlib SHA3-256; E4's TILE_03 row equals our I-10 row 0 measurement (independent cross-check) | **Correct values, file-name clash.** Imported as `verification/e4_data/vectors/e4_d2_k3_64.*`; our `vectors/` untouched |
| S4 evidence | `PQ_Attest_S4_Evidence/` is byte-identical to our `_export/PQ_Attest_S4_Evidence_20261105.zip` (SHA-256 `3aa52a6b...a085`) | consistent; staged from our zip by hash |
| Step 12 latency model | round trip 78-126 cycles, KMAC 72 cycles, 1,000-cycle timeout, 4 NI slots. Registered design: control round trip **1,204 cycles** (reports/I5_GATE_20261029.md), `N_OUTSTANDING = 2` (NOC_PKG.sv; hop probes check CFG_N_OUTSTANDING), BRIDGE_TIMEOUT 4,096 (D7), VERIFIER_TIMEOUT 100,000, NI_SLOT_TIMEOUT 8,192 in the merged build. A 1,000-cycle bridge timeout is **shorter than the ~1.2k cycles the tile-3 port is legitimately held** during an attestation (contract sec. 3 rule 6) | **REJECTED as evidence** (Kalash, 2026-11-06). D7 stays 4,096 |
| Step 13 slot model | 4 slots, 1,000-cycle timeout (same mismatch as above) | not evidence for our design |
| Step 18 RTL mutant proposals | the handoff document and the JSON list **different** targets (document: TRNG_SOURCE.sv, pq_kdf_message_builder.sv, ...; JSON: NOC_XY_ROUTING.sv, NOC_PKG.sv, ...). Several targets are wrong (window / byte-enable logic is in `pq_noc_subsystem_p7_i9.sv`, not `noc_ingress_quarantine.sv`) | triaged from the JSON (section 3) |
| "RTL_MODIFICATIONS=0" | E4's `rtl/dual_lane` is unchanged vs his previous package | consistent |

## 3. Step 18 triage (JSON proposals vs our 49 killed RTL controls)

| # | E4 proposal (JSON) | Real location in our design | Verdict | Evidence |
|---|---|---|---|---|
| 01 | routing Y before X (`NOC_XY_ROUTING.sv`) | same | **GAP: survived every bench** (hop probes 414/414 with the mutant) -> new oracle + control | `tb_i11_noc_spec` SPEC_XY_*, control `i11_mut_yfirst` |
| 02 | suppress credit return | router credit path | covered | `pfc_wp0_n6_mut_b_t5` (credit loss, killed) |
| 03 | attestation messages on VC 0 (`NOC_PKG.sv`) | `message_to_vc` | **GAP: survived** (every bench derives the expected VC from the same function) -> new oracle + control | `tb_i11_noc_spec` SPEC_VC_*, control `i11_mut_attest_vc0` |
| 04 | FIFO full check removed | `NOC_FIFO.sv` | not a killable control: credit flow control never offers a write to a full FIFO (equivalent mutant under the protocol) | N-7 / credit benches |
| 05 | NI slot timeout never expires | `noc_network_interface_p7_i9.sv` | covered | `i9_mut_no_timeout` |
| 06 | late / stale response delivered | same | covered | `i9_mut_stale_deliver` |
| 07 | L2 tag check forced valid | `noc_l2_auth_p7.sv` | covered | `s2_mut_mac_off`, `i7_mut_tag_off` |
| 08 | verifier ignores epoch | `pq_rot_verifier.sv`: no separate epoch compare; epoch bound in the expected tag | covered | `i7_mut_tag_off` (SEC_STALE_EPOCH), `s2_mut_epoch_off`, `i7_mut_l2_epoch_off` |
| 09 | gate open at reset | `noc_attest_gate.sv` / subsystem | covered | `i6_mut_gate_bypass` (I6G_RESET_BLOCKED), `p7_gate_mut_bypass` |
| 10 | BRAM window overshoot (E4 named `noc_ingress_quarantine.sv`) | `pq_noc_subsystem_p7_i9.sv` front end | **GAP: only the shrink direction was controlled** -> new control on the existing check | `i11_mut_window_over` killed by `I9_WINDOW_OUT_ERR` (bram_access +1) |
| 11 | commit with wstrb = 0 | `pq_noc_subsystem_p7_i9.sv` | spec question, not a defect: M-F1 sec. 5a does not forbid an all-zero strobe; lane mapping is covered | `i9_mut_bram_lanes` |
| 12 | measurement length > 135 accepted | `pq_measurement*.sv` `req_len_ok` + SVA | unreachable in the system (K-3 fixes 16 / 64); unit invalid-length rows in s8 golden | `s8_golden` (95/0) |
| 13 | IMEM truncated to 16 bytes | endpoint -> controller `imem_len` | covered | `i10_mut_window16` |
| 14 | tile-ID compare truncated | `pq_rot_verifier.sv`: no separate tile-ID compare; tile ID bound in KDF + tag | covered | `i7_mut_tag_off` (SEC_WRONG_IDENTITY), `s2_mut_id_off` |
| 15 | nonce reuse | `pq_rot_verifier.sv` | covered | `i7_mut_nonce_stale` |

**Council decision (Kalash conflict rule; VLSI-expert view):** proposals 01 and 03 expose real oracle gaps, not just missing
mutants. XY order underpins the N-7.5 deadlock-freedom argument, and keeping attestation off the request VC prevents a
REVOKE from being held behind memory-request backpressure (C4 bound). A spec-literal unit oracle (exhaustive routing table,
literal M-F1 VC table) is the standard closure. Added as a new bench with its count frozen before the run; RTL unchanged.

## 4. What was imported

- `verification/` (110 files written, byte-identical to the zip; `__pycache__` excluded), commit 3e7c2784.
- `verification/e4_data/vectors/e4_d2_k3_64.{json,svh}` (E4's D2 vectors under a non-clashing name).
- New harness job `e4_verification_v2` (scripts/e4_verification_v2.py): frozen 387 pytest / 15 stages; judge negative tests
  (old 224 count rejected, failures / skips / stage FAIL rejected). The v1 job (224 / 15) stays as history.
