# Python to RTL contract matrix — V6, Revision 4, I-1

Authority: `Pq_Attest_final.zip`, SHA-256 `047bb5a981050f11a572a60e850f7c7511ff5d636f7903c6a8d239891003c6a0`. Immutable APIs are under `software/pq_attest_final/PQ_Attest/software/`. This matrix records source-level semantics, not a fresh Python-to-RTL simulation result. `PYTHON_RTL_COMPATIBILITY=NOT_RUN` until I-2 V7–V9.

MATCH means matching specification/code structure on the stated profile. ADAPTER means lossless packing or a restriction to the hardware-supported input domain. No mismatched algorithm is silently repaired.

| Operation | Real teammate API / semantics | RTL / hardware profile | Finding |
|---|---|---|---|
| KMAC128 | `kmac128(key, message, output_bytes, customization=b'')`; cSHAKE128 function name `KMAC`; SP 800-185 encoding | `kmac_128`, rate 168 bytes, output selected as 16 or 32 bytes | MATCH for supported profile; external KAT evidence recorded by `python_ref` |
| KDF | `derive_tile_key(root_secret, tile_id, epoch, context, key_bytes=16)` | `pq_kdf` accepts 16/32; controller uses `.key_len_sel(2'b01)` = 32 | ADAPTER: pass `key_bytes=32` explicitly for system jobs; keep original 16-byte examples unchanged |
| KDF transcript | `encode_string(tile_id) + encode_string(epoch) + encode_string(context)`; empty KMAC customization | `pq_kdf.sv` bytes 0–8 = `01 38` + tile; 9–20 = `01 50` + epoch; 21 onward = `01 (8*context_len)` + context | MATCH for tile 7, epoch 10, context 0–14 bytes |
| Measurement | `measure_tile(tile_id, config, imem)` calls `sha3_256_reference(tile_id+config+imem)` | `pq_measurement` SHA3-256, 32-byte digest, raw concatenation | MATCH; no length prefix or separator introduced |
| Measurement input domain | Reference accepts byte strings and multi-block SHA3 | Hardware tile 7 bytes, config/imem each 0–64; total at most 135 bytes | ADAPTER: validate hardware bounds before issuing RTL requests; broad reference KATs do not extend RTL promises |
| Tag transcript | `build_attestation_message(tile_id, epoch, nonce, measurement)` concatenates fields without encoding | `pq_attestation_tag` offsets 0, 7, 17, 33; 65-byte message | MATCH on widths 7/10/16/32 |
| Tag primitive | `generate_attestation_tag(tile_key,tile_id,epoch,nonce,measurement)` -> KMAC128, 32 bytes, customization `PQ-ATTEST-AUTH` (14 bytes) | Stage 7 uses 32-byte tile key and 32-byte tag with the same customization | MATCH |
| Tile API | `tile_respond(tile_key,request,measurement)` returns `AttestationResponse(tile_id,epoch,nonce,measurement,tag)` | Controller obtains key/measurement/tag, then packs fields | ADAPTER: Python dataclass to fixed bytes; algorithm remains in imported API |
| Reference verifier | `verifier_check(tile_key,request,response)` compares tile/epoch/nonce, digest/tag lengths and KMAC; returns `AttestationVerdict(accepted,reason)` | RoT policy also needs an outstanding challenge and whitelist | ADAPTER: record both verdicts; reference has no outstanding-state or whitelist. V10 remains pending |
| Field widths | Reference byte fields have runtime lengths; nonce must be nonempty; measurement/tag exactly 32 bytes | Tile 56 bits, epoch 80, nonce 128, measurement/tag 256 each | ADAPTER: require tile=7, epoch=10, nonce=16; no truncation or padding of logical fields |
| Internal response packing | Reference dataclass has no numeric 776-bit serialization | Controller response is 97 bytes / 776 bits; byte `i` at `[i*8 +: 8]` | ADAPTER: little-endian numeric conversion preserves byte order |
| NoC response R-B | Reference has no NoC framing | Measurement + tag = 64-byte / 16-word response; identity/epoch/nonce are bound to the outstanding request | ADAPTER: transport contract must be published in M-F1 rev 6 before further dependent RTL changes |
| Error status | Reference verdict carries a reason string; controller has local `error_code` | OD-2 uses `tx_control[10:7]`; fixed zero 16-word payload for errors | ADAPTER: transport code mapping is separate; endpoint's current all-code-10 behavior still needs I-2/PQ-2 correction |

## Exact internal packing

| Field | Byte offset | Bytes | RTL expression |
|---|---:|---:|---|
| tile | 0 | 7 | `[0*8 +: 56]` |
| epoch | 7 | 10 | `[7*8 +: 80]` |
| nonce | 17 | 16 | `[17*8 +: 128]` |
| measurement | 33 | 32 | `[33*8 +: 256]` |
| tag | 65 | 32 | `[65*8 +: 256]` |

Source anchors: `pq_kdf.sv` transcript builder and output selection; `pq_measurement.sv` request bounds; `pqattest_stg7.sv` transcript/customization; `pq_attest_protocol.sv` response assignments. These protected files were read, not modified. Every row needs V7/V9 requalification against the immutable ZIP adapter before PQ-1 acceptance.

## Limitations carried forward

- **L-1:** raw measurement has a config/imem split ambiguity. Fix per-tile lengths beside the provisioned whitelist; this is a provisioning rule, not a digest property. The offline CRYPTO fixture uses config=16 bytes and imem=16 bytes; changing lengths needs reprovisioning and requalification.
- **L-2:** the teammate verifier is stateless and has no whitelist; duplicate retirement and measurement approval belong to the system policy layer.
- **L-3:** offline keys/nonces are deterministic demo inputs. No entropy or production provisioning claim.
- **L-4:** RTL's full 136-byte SHA3 final block and `is_final` stability remain outside the supported 135-byte message API. Reference SHA3 tests at larger lengths do not prove those RTL cases.

I-1 does not replace the existing oracles. They remain supplementary and blocked from PQ acceptance until I-2 installs the ZIP-backed adapters. Historical 16/0 demo evidence keeps its original oracle identity and cannot be relabeled as teammate-reference evidence.
