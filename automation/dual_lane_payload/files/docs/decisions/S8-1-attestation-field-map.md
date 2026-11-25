# S8-1 internal field map and wire proposal

The implemented internal response is 97 bytes. Byte i occupies `[i*8 +: 8]`.
Tile ID bytes 0–6, epoch 7–16, nonce 17–32, measurement 33–64, tag 65–96.
The key is `KMAC128(root, encode_string(tile) || encode_string(epoch) ||
encode_string(context), 32, empty customization)`. Measurement is
`SHA3-256(tile || config[:config_len] || imem[:imem_len])`, capped at 135 bytes.
Tag is `KMAC128(key, tile || epoch || nonce || measurement, 32,
"PQ-ATTEST-AUTH")`. Context is an encoded message field, not customization.

The reconstructed specification oracle uses the existing independently
self-tested Python KMAC primitive and hashlib, never DUT outputs. Natural byte
order is distinct from reversed SV hexadecimal literals. Existing Stage-5/6/7
literals must match before controller vectors are accepted.

Wire proposal Q-C/R-B, error policy and trust decisions are pending in
DUAL_LANE_10_CONTRACT.md. NOC_PKG.sv is unchanged. No wire conversion or
packetization acceptance is implied by an internal golden test passing.

SHA3 debt: is_final must remain stable until completion; full 136-byte final
padding is outside the promised measurement API. The 135-byte cap remains.
