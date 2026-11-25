## Latest owner GUI readback15 Nov12:26 - PASS

Current main bit SHA256:7a81ddf2c8f6c10bf5410f04dc5f55fc0fe2748575b3a85fc30f56c345fdd20e
Metrics unchanged:39962LUT/29187FF/WNS+0.182/WHS+0.007.0 errors/critical warnings;4 warnings documented.
See reports/R10_OWNER_GUI_BUILD_20261115.md. Hardware validation remains pending; older image hashes below are historical.

## Latest: MAIN-project bitstream built and gated successfully

Image: C:\vivado_verilog_proj\NOC_PQATTEST\NOC_PQATTEST.runs\impl_merged\pq_merged_board_top.bit
SHA256: 8d951af86feb9085aee7f7316e231ba091d6969cb6f4b2133f8d7a96b7e1f92d
All four physical builds match39962LUT/29187FF/WNS+0.182/WHS+0.007; main payload equals both releases and GUI copy.
The source-sync and main Generate Bitstream flow have now actually run. Do not rebuild again merely to program
this exact accepted image. Open the main project to view its implemented design/schematics. Board observations
are the next required input; programming remains Kalash-only. Hardware/formal/SOC flags NO.

--- earlier instructions and historical gates ---

# Revision 10 - automated build qualification complete

G3: 31/31 PASS_FRESH. G4: two fresh accepted release builds. G5: isolated GUI flow passed twice-source
idempotence, 73 sources, full synthesis/implementation/bitstream gate, implemented top opened successfully.

Open NOC_PQATTEST.xpr, then in Vivado Tcl Console:

    source C:/vivado_verilog_proj/NOC_PQATTEST/scripts/merged_gui_runs.tcl

Press Generate Bitstream. Wait for GUI_GATE PASS and write_bitstream Complete. Record the hash:

    Get-FileHash C:/vivado_verilog_proj/NOC_PQATTEST/NOC_PQATTEST.runs/impl_merged/pq_merged_board_top.bit -Algorithm SHA256

Only then program that exact image. Main project GUI generation and programming are Kalash's remaining steps.
USB UART: 115200 baud, 8 data bits, no parity, one stop. sw[0]=0 selects CPU A/tile3; sw[0]=1 selects CPU B/tile0.
Reset with btn[0] after selecting each UART source to capture its boot text. A: PASS T3 cycles=...; B: PASS T0 REFUSED OK.
Return sw[0]=0, reset, then btn[2] revoke: PASS T3 REVOKED and authorization LED0 off. btn[1] re-attests:
PASS T3 RECOVERED, authorization LED0 on. Firmware v3 button waits do not time out.
Board LEDs: led[0] authorization, led[1] sticky attestation failure, led[2] CPU A GPIO bit0, led[3] heartbeat;
led0_r indicates CPU B refused, led0_g indicates either CPU FAIL bit. Do not read tile GPIO patterns as the external LED bus.

Record image SHA256, both UART texts, LEDs before/after revoke/re-attest and any failure. No hardware PASS is assumed.
The old board checklist and old source-header comments about first64 bytes/v2 are historical; active qualified code
uses WHOLE_IMEM_MEASUREMENT=1, demo_fw_v3.hex and profile10. Current measurement covers 16384 bytes.

HARDWARE_VALIDATED=NO, SOC_INTEGRATION_COMPLETE=NO, FORMAL_PROOF=NO. No rtl-rc2 tag yet.
Remaining: owner's main GUI build and board record, then final freeze/tag/report and website data update.

## Exact accepted images and source-sync proof

| Build | LUT | FF | WNS ns | WHS ns | Whole-file SHA256 |
|---|---:|---:|---:|---:|---|
|G4 first|39962|29187|+0.182|+0.007|2d59f7431a265452d90387538549ef1f4d93ff2381bb59a85d9b224c910768ef|
|G4 second|39962|29187|+0.182|+0.007|bbc50b68dee4c0e2c3e04ed22e09bc0dffba83f342ad4386dd43c4788add2002|
|GUI copy|39962|29187|+0.182|+0.007|f633b14c02173066fc38689bd5b4e7cdcda53e3a63e473ccfe5b4a295f6a52a2|

All three configuration payloads match exactly:54228bfc7b7536a48cb27e1538574199d7088fd4ff2f849664d141317204c3dd.
Whole-file hashes differ because headers contain build times. Your future MAIN-project file's whole SHA cannot
be predicted: record its actual hash after generation. The above copy is tested, not a claim that the main project
has already generated a new image. Copy image is C:/vivado_verilog_proj/_r10g2/NOC_PQATTEST.runs/impl_merged/pq_merged_board_top.bit.

Actual copy-project readback confirmed meas_imem_hasher.sv and demo_fw_v3.hex,4096 padded words,73 GUI files,
second synchronization0/0 changes. gui_synth_post linked one mesh cell with17236 primitives and rewrote the full
checkpoint. Source-sync and payload comparisons are in R10_GUI_SOURCE_SYNC_READBACK / R10_GUI_BITSTREAM_COMPARISON JSON.
Boot hashing is about8000 cycles, approximately0.16 ms at50MHz (estimate; do not treat a short pause as a fault).
The main-project command is the SAME tested synchronization script; nevertheless the owner's main build gate
must pass and its actual image hash must be recorded before programming.
