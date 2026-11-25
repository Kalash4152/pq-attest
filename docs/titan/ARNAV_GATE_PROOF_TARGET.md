# Pinned existing gate proof target

Baseline titan-base-20261119 commit b9e41c383473802267c8c3d604e329770d708ab5. SHA-256 below is computed on bytes from the Git blobs, also supplied verbatim in the archive.

| Input | SHA-256 |
|---|---|
| rtl/dual_lane/NOC_PKG.sv | e428af103c9a0096f47f9ad97215a33b919dc9035c2a5e9d1255ff9fdd33a7be |
| rtl/dual_lane/noc_attest_gate.sv | f05881987d3bffbba6ed5ee1c6d99bfa7b5b11f50d549ba73c9b0a6627ba7235 |

Run from the extracted archive root:

```sh
sv2v rtl/dual_lane/NOC_PKG.sv rtl/dual_lane/noc_attest_gate.sv > gate_converted.v
```

Record the sv2v version, command, and converted SHA-256 beside the SBY job. This is the reproduction command for these pins. Arnav's original conversion command and converted hash must be read from his own evidence before linking his previous PASS to these bytes.
