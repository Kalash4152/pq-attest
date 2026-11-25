## d4_crypto_ooc.xdc - PQ-3 (D4) crypto out-of-context synthesis constraints.
## Read by scripts/d4_crypto_ooc.tcl (child mode) BEFORE synth_design, so that
## synthesis is timing-driven; the same constraints then time the netlist.
##
## Scope: OOC only. The I/O budgets are ASSUMED, not derived from a real
## neighbour. They are the same budgets ni_ooc used in I-1
## (reports/dual_lane_10_20261008_235701_d7b8ee31/ni_ooc/metrics.txt:
## CLOCK_NS=20, INPUT_BUDGET_NS=5, OUTPUT_BUDGET_NS=5), so NI and crypto OOC
## numbers are comparable. Every crypto top is a registered-request /
## registered-result engine on one clock, so a 5 ns external budget leaves
## 15 ns for the first/last internal stage. Integrated timing is N-14 / SoC
## work and is NOT claimed by this file.
##
## Part xc7a100tcsg324-1, single clock, 20 ns (50 MHz). No clock change.
## All four existing tops (pq_kdf, pq_measurement, pq_attestation_tag,
## pq_attestation_controller) and pq_attest_endpoint name the clock port clk.

create_clock -name clk -period 20.000 [get_ports clk]

## One value = both min and max, exactly as ni_ooc. Vivado reports this as
## methodology XDCH-2 (same min/max IO delay); that warning is expected here.
set_input_delay  -clock clk 5.000 [get_ports -filter {DIRECTION == IN && NAME != clk}]
set_output_delay -clock clk 5.000 [get_ports -filter {DIRECTION == OUT}]

## Deliberately NOT here:
##  - no set_false_path / multicycle: every port, rst_n included, is timed.
##  - no KEEP_HIERARCHY / DONT_TOUCH: hierarchy is kept by
##    synth_design -flatten_hierarchy none and PROVEN post-synthesis by the
##    child-instance check in d4_crypto_ooc.tcl (see reports/i2_p2/P2_OOC_PREP.md).
