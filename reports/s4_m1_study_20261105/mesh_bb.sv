// M1 measurement only: black-box declaration of the protected noc_mesh_3x2 (same ports); its netlist comes from mesh.dcp.
(* black_box *) module noc_mesh_3x2 #(
    parameter bit LINK_PIPE = 1'b1
) (
    input  logic                                   clk,
    input  logic                                   rst,
    input  noc_pkg::flit_t [noc_pkg::NUM_TILES-1:0] tile_in_flit,
    input  logic           [noc_pkg::NUM_TILES-1:0] tile_in_valid,
    output logic           [noc_pkg::NUM_TILES-1:0] tile_in_ready,
    output noc_pkg::flit_t [noc_pkg::NUM_TILES-1:0] tile_out_flit,
    output logic           [noc_pkg::NUM_TILES-1:0] tile_out_valid,
    input  logic           [noc_pkg::NUM_TILES-1:0] tile_out_ready
);
endmodule
