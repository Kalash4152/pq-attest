# Main project revision-10 build - PASS

The ACTUAL main NOC_PQATTEST.xpr was synchronized twice (idempotent), rebuilt through write_bitstream,
gated successfully and the full implemented design opened. Not merely a copy-project result.

{
  "metrics": {
    "LUT": 39962.0,
    "FF": 29187.0,
    "BRAM": 20.0,
    "WNS": 0.182,
    "WHS": 0.007
  },
  "bitstream": "C:\\vivado_verilog_proj\\NOC_PQATTEST\\NOC_PQATTEST.runs\\impl_merged\\pq_merged_board_top.bit",
  "sha256": "8d951af86feb9085aee7f7316e231ba091d6969cb6f4b2133f8d7a96b7e1f92d",
  "payload_sha256": "54228bfc7b7536a48cb27e1538574199d7088fd4ff2f849664d141317204c3dd",
  "matches_both_g4_and_copy": true,
  "hardware_validated": false,
  "formal_proof": false
}

This main image's configuration payload matches both G4 builds and the qualified GUI copy exactly.
Different whole-file hashes reflect timestamp headers; use this exact main SHA for the owner programming record.
No new RTL/reference, clock, device, constraint or recipe changes. Main XPR stays uncommitted by policy.
No programming was performed. HARDWARE_VALIDATED=NO, SOC_INTEGRATION_COMPLETE=NO, FORMAL_PROOF=NO.
Remaining owner board validation, then freeze/tag/sign-off/site updates. Estimated whole-plan88%, not95%.
