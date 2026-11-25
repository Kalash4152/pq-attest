# cpu_tile_noc: port table and instantiation (brief v2 B2)

Lane 1, 2026-11-06. RTL: `rtl/riscv/cpu_tile_noc.sv` (commit d6aeea10). Bench: `sim_riscv/tb_cpu_tile_noc.sv` (12 checks).

**Status:**
- Scratch XSim run: 12/12 PASS, with a stand-in `meas_window_reader`, because the fork's B3 has not landed. See `B2_SCRATCH_20261106.txt`.
- Not registered.
- OOC synthesis (B7) has not been run.

## Ports (identical to `cpu_tile_noc_stub`)

| Port | Width | Dir | Lane 1 signal (pq_soc_merged_core, tile g = 3 / 0) |
|---|---|---|---|
| clk | 1 | in | clk |
| rst | 1 | in | rst (sync, active high; re-synchronised inside by reset_sync) |
| app_valid_o | 1 | out | app_valid[g] |
| app_ready_i | 1 | in | app_ready[g] |
| app_destination_o | noc_pkg::coord_t | out | app_destination[g] |
| app_message_o | noc_pkg::msg_type_e | out | app_message[g] |
| app_control_o | 11 | out | app_control[g] |
| app_payload_o | 32 | out | app_payload[g] |
| app_payload_valid_o | 1 | out | app_payload_valid[g] |
| app_payload_ready_i | 1 | in | app_payload_ready[g] |
| app_tx_error_i | 1 | in | app_tx_error[g] |
| app_rx_head_valid_i | 1 | in | rx_hv[g] |
| app_rx_src_i | noc_pkg::coord_t | in | rx_src[g] |
| app_rx_msg_i | noc_pkg::msg_type_e | in | rx_msg[g] |
| app_rx_control_i | 11 | in | rx_ctl[g] |
| app_rx_data_i | 32 | in | rx_data[g] |
| app_rx_data_valid_i | 1 | in | rx_dv[g] |
| app_rx_last_i | 1 | in | rx_last[g] |
| app_rx_abort_i | 1 | in | rx_abort[g] |
| authorized_i | 1 | in | authorized[g] |
| grant_done_i | 1 | in | grant_done (tile 3); 0 (tile 0) |
| attest_failed_i | 1 | in | attestation_failed (tile 3); 0 (tile 0) |
| attest_req_o | 1 | out | not connected (sec. 8 policy); 1-cycle pulse from STATUS ATTEST_REQ |
| meas_imem_o | 512 | out | verifier imem (byte i at [8i +: 8]) |
| meas_imem_len_o | 7 | out | verifier imem_len (= 64) |
| meas_valid_o | 1 | out | holds the RoT start (core) |
| uart_tx_o | 1 | out | board UART |
| gpio_o | 8 | out | {4'b0, leds} |

## Parameters

| Parameter | Default | Meaning |
|---|---|---|
| TILE_ID | 3 | tile number (bridge self-check, STATUS TILE_ID) |
| MEM_TILE | 2 | memory tile |
| BRIDGE_TIMEOUT | 4096 | D7 |
| NI_SLOT_TIMEOUT | 8192 | D6; also the bridge's LATE_DRAIN_CYCLES |
| BUILD_ID | 0 | STATUS +0xC |
| MEAS_BASE | 0 | first IMEM byte of the 64-byte window |
| IMEM_WORDS / DMEM_WORDS | 4096 | |
| IMEM_INIT_FILE / DMEM_INIT_FILE | "" | firmware image (R-3) |
| ADDR, DATA_SEED, ROUND_GAP, NEVER_AUTHORIZED_TEST, MEAS_IMAGE | | stub-compatibility only; ignored |

## Swap in the merged core

The core's two instances (`u_cpu_a` tile 3, `u_cpu_b` tile 0) elaborate unchanged. To use the real tile:

1. Compile with `-d CPU_TILE_MODULE=cpu_tile_noc`.
2. Add these files to the source list: the rtl/riscv sources, `tmem_app_bridge.sv`, `reset_sync.sv`, `meas_window_reader.sv` and `picorv32.v`.

Example (tile 3):

```systemverilog
cpu_tile_noc #(.TILE_ID(3), .MEM_TILE(2), .BRIDGE_TIMEOUT(4096), .NI_SLOT_TIMEOUT(8192),
               .BUILD_ID(32'h2026_1106), .IMEM_INIT_FILE("fw_tile3.hex")) u_cpu_a ( /* ports as in the table */ );
```

## Design decisions (VLSI review, 2026-11-06)

- **A3 sideband.** `tmem_err_code_i = {1'b0, last_err_kind_o}`.
  - It is registered on the same edge that enters the bridge's error state.
  - The bench checks the alignment (CTN_ERRKIND_ALIGNED).
  - A mutant with the sideband tied to 0 is killed.
- **Measurement trigger.** The reader starts on ATTEST_REQ, and also once after reset release.
  - The core holds the RoT start until `meas_valid_o`, so the first measurement must not depend on firmware.
  - IMEM is read-only to the CPU (R-D8), so the image measured at reset is the one the CPU executes.
