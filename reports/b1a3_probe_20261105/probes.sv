// Scratch area probes (not evidence). Tie-offs copied from the in-context instances.
module probe_enc #(parameter int SPEC=0, parameter int SHARED=1)(
  input  logic clk, rst_n, start, block_ready, owner_b,
  input  logic [255:0] key_in,
  input  logic [127:0] custom_in,
  input  logic [(SHARED?65:88)*8-1:0] msg_in,
  input  logic [6:0] msg_len,
  output logic [167:0][7:0] block_data,
  output logic block_valid, block_last, busy, done);
  localparam int CB = SHARED ? 16 : 14;
  localparam int MB = SHARED ? 65 : 88;
  // shared (endpoint E1, verifier E4): KDF owner custom 0, tag owner custom 14, key 32, L256 for both (2'b01)
  // L2 engine E3: key 32, custom 14, L128
  wire [4:0] clen = SHARED ? (owner_b ? 5'd14 : 5'd0) : 5'd14;
  wire       lsel = SHARED ? 1'b1 : 1'b0;
  if (SPEC) begin : G
    kmac_encode_a3 #(.KEY_BYTES(32),.CUSTOM_BYTES(CB),.MSG_BYTES(MB)) u(.clk,.rst_n,.start,
      .key_in, .key_len(6'd32), .custom_in(custom_in[CB*8-1:0]), .custom_len(clen[$clog2(CB+1)-1:0]),
      .msg_in, .msg_len(msg_len[$clog2(MB+1)-1:0]), .out_len_sel(lsel),
      .block_data, .block_valid, .block_ready, .block_last, .busy, .done);
  end else begin : G
    kmac_encode #(.KEY_BYTES(32),.CUSTOM_BYTES(CB),.MSG_BYTES(MB)) u(.clk,.rst_n,.start,
      .key_in, .key_len(6'd32), .custom_in(custom_in[CB*8-1:0]), .custom_len(clen[$clog2(CB+1)-1:0]),
      .msg_in, .msg_len(msg_len[$clog2(MB+1)-1:0]), .out_len_sel(lsel),
      .block_data, .block_valid, .block_ready, .block_last, .busy, .done);
  end
endmodule

// B1 probe: N status counters, 32-bit wrap (today) vs 16-bit saturating zero-extended to the same 32-bit port.
module probe_cnt #(parameter int SAT16=0, parameter int N=16)(
  input logic clk, rst, clr, input logic [N-1:0] inc, output logic [N-1:0][31:0] count);
  for (genvar i=0;i<N;i++) begin : C
    if (SAT16) begin : S
      logic [15:0] c;
      always_ff @(posedge clk) if (rst||clr) c<='0; else if (inc[i] && c!=16'hFFFF) c<=c+16'd1;
      assign count[i] = {16'd0, c};
    end else begin : W
      always_ff @(posedge clk) if (rst||clr) count[i]<='0; else if (inc[i]) count[i]<=count[i]+32'd1;
    end
  end
endmodule
