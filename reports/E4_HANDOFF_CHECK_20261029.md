# Engineer 4 (verification lane) final handoff check, 2026-10-29: NOT ACCEPTED as delivered

- **Inputs:**
  - `PQ_Attest_Engineer4_Work_Completed.md` (Downloads), the completion report;
  - `pqattest.zip` (Downloads): 54,152 bytes, SHA-256 `2f63a56aa9737c9b8b021816cce8e32d04e653c388c486e7c78ed0944976b036`, 31 files.
- **Method:**
  - extracted into an isolated scratch folder;
  - scripts inspected before running (they only write vector files into their own folder: no network, no deletes);
  - the Python regression rerun on a copy with the shipped `__pycache__` removed;
  - the RTL testbench run in XSim 2024.1.
  - Nothing was copied into this repository.
- Evidence class: Python-run and XSim-simulated (scratch, not registered). Hardware, timing and formal: NO.

## Verdict

The zip does not contain the work the report describes. What it does contain is either already in this repository
(byte-identical) or a small SHA3 RTL set that passes its own three vectors.

## 1. Report against the zip

| Claimed in the report | In the zip |
|---|---|
| `verification/` with 14 scripts: xsim_parser, crypto_compare, verify_tile_map, xy_route_oracle, generate/verify_noc_pair_matrix, extract_sv_interfaces, ni_transaction_contract, sv_vector_bridge, generate_noc_traffic, generate_integration_scenarios, p4_regression | **absent** (no `verification/` directory) |
| `verification/test_*.py`, "103 TESTS PASS" | **absent**; the 103-test claim cannot be checked |
| software/noc_pair_matrix.json, noc_traffic_vectors.json, integration_scenarios.json; sv_interface_inventory.json, sv_vector_input.json, generated_sv_vector.sv | **absent** |
| sample XSim logs for the parser (sample_pass.log, ...) | **absent** |
| software/ crypto references (keccak, sha3, kmac128, measurement, kdf, trng, attestation) | present |

## 2. What the zip contains

- **software/ (14 .py files) and trng_healthtests.py:**
  - **byte-identical** to the frozen teammate reference already in this repository: `software/pq_attest_final/`, from
    `Pq_Attest_final.zip`, SHA-256 `047bb5a9...a6c0`;
  - every file compared by SHA-256, all identical (kdf_vectors.txt is generated output);
  - rerun: `software/run_all_tests.py` gives 8 / 8 suites PASS (KMAC128 NIST KAT, measurement, KDF golden and verification,
    attestation vectors and protocol, security and cross-module regressions);
  - nothing new relative to the reference we hold.
- **rtl/ (new):**
  - `keccak_round.sv`, `keccak_f1600_core.sv`, `sha3_256_core.sv`, `tb_sha3_256_core.sv`;
  - XSim: 3 / 3 multi-block vectors PASS (135, 136, 137 x 'a'); the expected digests match Python hashlib;
  - first launch was the known kernel-start stall; one relaunch, then PASS;
  - **`keccak_f1600.sv` and `tb_keccak_f1600.sv` are 0-byte files**;
  - coverage is thin: three lengths, no empty message, no "abc", no back-to-back or reset cases, no mutants.
  - This is a separate SHA3 implementation. The integrated design already uses the protected `SHA3_*.sv` /
    `pq_keccak_pkg` path with accepted KATs, so this RTL is not needed unless it is meant to replace that path (not proposed).
- **CODE_EXPLANATION.md:** describes the Python Keccak -> KMAC128 -> KDF reference stack only.

## 3. Contract staleness in the report (applies if the verification/ tree exists elsewhere)

The constants the report calls authoritative are pre-P7 (M-F1 rev 5). The integrated design is M-F1 rev 7 / P7.

| Report | Current design (P7) |
|---|---|
| MAC_FLITS = 0 for every type | per-type: data types 0-3 plain; control types 4-7 carry 4 MAC words (noc_p7_pkg p7_mac_flits) |
| ATTEST_CHALLENGE payload 5, 6 flits | payload 7; wire length 12 (7 + 4 MAC + HEAD); RESPONSE 21, GRANT / REVOKE 5 |
| vectors V1 (6 flits) and V2 (17 flits) | V1 would be 12 flits and V2 21 flits |
| parses `noc_network_interface` | the integrated NI is `noc_network_interface_p7` (CONTROL_ALLOWED, tx_auth_preview) |
| 36 pairs including LOCAL self-pairs, hop 0 | LOCAL -> LOCAL is forbidden (noc_router a_no_loopback_local_sync); 30 legal ordered pairs |
| attestation scenarios between arbitrary pairs | control types exist only 4 -> 3 (CHALLENGE, GRANT, REVOKE) and 3 -> 4 (RESPONSE); refused at tiles 0, 1, 2, 5 (R7.4) |
| integration scenarios "memory read / write" from any tile | in the P7 subsystem only attested tiles may send data (noc_attest_gate.sv:21) |

Its boundary statement is accurate: it claims no RTL, Vivado, timing or hardware correctness.

## 4. Requested before acceptance

1. Send the actual `verification/` tree, its tests, the generated JSON / SV artifacts and the sample logs, so that
   `python -m verification.p4_regression --run-tests` can be rerun here.
2. Re-baseline the contracts to M-F1 rev 7 / P7: per-type framing, CHALLENGE 7 words, no LOCAL self-pairs, control only
   between 3 and 4, data only from attested tiles.
3. Fill or remove the two 0-byte RTL files; widen the SHA3 RTL bench (empty, "abc", back-to-back, reset), or state that this
   RTL is reference-only.

Note: an XSim process (PID 31472, `snap -R -log sim1.log`) was running during this check. It was later confirmed to be my
own RISC-V-check run (`tb_gpio`), ended by that run's 900 s bounded wait. It is unrelated to this package.

---

## Re-check of the second package, `pqattest1.zip` (2026-10-29): REPRODUCED, valid for the rev-5 baseline only

- **Package:** `pqattest1.zip`: 40,095,009 bytes, SHA-256 `7cb4a3f3977247eff791aa7346e3c8fb733188dd606ae1bcdded145b0fe8eaab`,
  798 files.
  - It is a Git tree: commit `b62b78d Initialize and complete Engineer 4 verification infrastructure (P3 and P4)` on
    `0acc9e1`, inside a September snapshot of this project.
  - Its `NOC_PQATTEST.srcs/sources_1/new/NOC_PKG.sv` is identical to our protected production NOC_PKG (M-F1 rev 5).
- **The `verification/` tree is present:** 14 scripts, 10 test files, the sample logs, the crypto comparison fixtures, and
  the generated JSON / SV artifacts. This supersedes section 1's "absent" rows for this package.
- **Scripts inspected first.** The subprocess calls only launch pytest or their own scripts; writes go to temp test files.
- **Results (scratch copy, `__pycache__` removed):**
  - `python -m verification.p4_regression`: **Cross-module consistency: PASS**.
  - The claimed `--run-tests` needs pytest, which is not installed here; installing it needs a download, so it was not done.
  - Instead, the 10 test files ran through a minimal pytest-free runner: `pytest.raises` and `tmp_path` provided, every
    `test_*` function called. **103 tests, 0 failures**, matching the report's count.

### Validity limits found

1. **Payload lengths are not taken from NOC_PKG.**
   - They are hard-coded in `verification/sv_vector_bridge.py` (ATTEST_CHALLENGE = 5) and imported by p4_regression.
   - Demonstrated: the cross-module check prints PASS against both our rev-5 package (CHALLENGE 5) and the P7 base package
     `rtl/dual_lane/NOC_PKG.sv` (CHALLENGE 7).
   - So the "authoritative NOC_PKG" chain does not cover message lengths, and a length change goes undetected.
2. **MAC framing is fixed at MAC_FLITS = 0** (ni_transaction_contract.py, sv_vector_bridge.py). The P7 per-type framing
   (control types + 4 MAC words, data plain) is not modelled.
3. **36 pairs include 6 LOCAL self-pairs (hop 0).** The router forbids LOCAL -> LOCAL; the legal set is 30 ordered pairs.
4. **No P7 authorization rules.** Attestation scenarios between arbitrary tiles, and data from any tile, are generated as
   valid; P7 allows control only 4 <-> 3 and data only from attested tiles.
5. As the report itself says: no RTL, Vivado, timing or hardware correctness is established.

### Verdict for the Engineer 4 lane

Accepted as Python verification infrastructure for the M-F1 rev-5 transport baseline: the work exists and its 103 tests and
consistency check reproduce. Not valid for the integrated P7 design until:
(a) message lengths are parsed from the package;
(b) MAC framing is per-type (noc_p7_pkg);
(c) self-pairs are removed or marked illegal;
(d) the R7.4 authorization rules are added.
Re-running with pytest itself needs pytest installed (your call).
