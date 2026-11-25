`timescale 1ns/1ps
// Phase 0 measurement only (not a design file): a CPU-tile-sized placeholder, about 1.6-1.8k LUT / 1.1k FF, sized like
// the RISC-V lane's last measured tile_top (1,674 LUT, 1,102 FF). A 32 x 32 LUT-RAM register file, a 4-function ALU with a
// barrel shifter and 28 pipelined 32-bit mixing stages, driving one NoC application port (header + 2 payload words) and
// consuming its ready / error signals, so the placer puts it beside the tile's NI as a real CPU would be.
module cpu_placeholder #(parameter logic [31:0] SEED = 32'h1234_5678) (
  input  logic clk, rst,
  input  logic app_ready, app_payload_ready, app_tx_error,
  output logic app_valid, app_payload_valid,
  output noc_pkg::coord_t app_destination,
  output noc_pkg::msg_type_e app_message,
  output logic [10:0] app_control,
  output logic [31:0] app_payload
);
  import noc_pkg::*;
  logic [31:0] lfsr, acc;
  logic [31:0] rf [32];
  logic [4:0] wa, ra, rb;
  logic [31:0] a, b, alu;
  logic [31:0] st [29];
  logic [1:0] op;
  always_ff @(posedge clk) begin
    if (rst) begin lfsr <= SEED; wa <= 0; ra <= 1; rb <= 2; op <= 0; end
    else begin
      lfsr <= {lfsr[30:0], lfsr[31] ^ lfsr[21] ^ lfsr[1] ^ lfsr[0]};
      wa <= lfsr[4:0]; ra <= lfsr[9:5]; rb <= lfsr[14:10]; op <= lfsr[16:15];
    end
  end
  always_ff @(posedge clk) rf[wa] <= st[28] ^ {app_ready, app_payload_ready, app_tx_error, 29'd0};
  assign a = rf[ra];
  assign b = rf[rb];
  always_comb case (op)
    2'd0: alu = a + b;
    2'd1: alu = a - b;
    2'd2: alu = a ^ (b << lfsr[20:16]);
    default: alu = (a >> b[4:0]) | (b & lfsr);
  endcase
  always_ff @(posedge clk) begin
    st[0] <= alu;
    for (int i = 1; i < 29; i++) st[i] <= (st[i-1] + {st[i-1][15:0], st[i-1][31:16]}) ^ (st[i-1] >> (i % 7 + 1)) ^ lfsr;
  end
  // NoC application port: write requests to the memory tile, payload from the pipeline
  typedef enum logic [1:0] {S_IDLE, S_HDR, S_P0, S_P1} s_t;
  s_t s;
  always_ff @(posedge clk) begin
    if (rst) begin s <= S_IDLE; acc <= 0; end
    else begin
      acc <= acc ^ st[28];
      case (s)
        S_IDLE: if (lfsr[3:0] == 4'h5) s <= S_HDR;
        S_HDR:  if (app_ready) s <= S_P0;
        S_P0:   if (app_payload_ready) s <= S_P1;
        S_P1:   if (app_payload_ready) s <= S_IDLE;
      endcase
    end
  end
  assign app_valid = s == S_HDR;
  assign app_payload_valid = s == S_P0 || s == S_P1;
  assign app_destination = tile_to_coord(TILE_MEMORY);
  assign app_message = MSG_MEM_WR_REQ;
  assign app_control = 11'h780;
  assign app_payload = s == S_P0 ? 32'h2200_0100 : acc;
endmodule
