# N-8 baseline-v1 performance and finite liveness plan

Approved as OD-6 on 2026-10-08. The historical workstream listed bit-complement;
this accepted handoff uses neighbor as its fourth pattern and adds transpose.
Index is `y*3+x`. Uniform uses a fixed 32-bit LCG, selects 0..4, then skips the
source. Transpose maps `(x,y)` to linear index `2*x+y` interpreted in the 3x2
mesh (a rectangular permutation, including its two fixed points). Hotspot sends
to MEMORY index 2, including its local loopback. Neighbor follows the physical
Hamiltonian cycle 0→1→2→5→4→3→0 (each is a one-hop neighbor).

Four patterns × rates 1/64, 1/32, 1/16, 1/8, 1/4, 1/2, 1 × two MAC framing
modes = 56 points. Seed 0x12345678, portable LCG `state*1664525+1013904223`.
Each source queues at most 256 packets per point; attempts beyond the explicit
generation cap are counted separately as generator drops. Warm-up 128 cycles,
measurement 2048 cycles, drain bounded at 50000 cycles. Reset between points.
N_OUTSTANDING=2 is preserved. Every destination includes an independent
memory-response stand-in so real NI slots retire; payload expectations come
from generator records, never delivered DUT values.

t_gen = enqueue; t_accept = tile request handshake; t_inj = NI HEAD→mesh
handshake; t_del = destination request completion (payload-last in MAC-off,
trailing MAC completion in MAC-on). Offered/queued/accepted/injected/delivered,
generator cap drops and responses are separate. Queue latency is
t_accept−t_gen; network latency t_del−t_inj; total t_del−t_gen. Throughput is
packets/cycle/tile during the measurement interval; link units are flits/cycle;
byte rates use the declared 20ns cycle. No regression-line fit is a correctness
oracle. Isolated hop probes are a separate subgate.

Read-only monitors cover per-VC FIFO full/credit stall cycles, eject activity,
NI fill/busy cycles and link flits. No router/allocator/VC-depth changes.
Finite progress requires complete accounting, zero duplicates/corruption and
all FIFOs/eject/link/locks idle with all credits returned after drain.
Negative controls corrupt one payload, remove one TB-local flit, and stall
consumption. They must identify the mismatched/missing packet or liveness
observation; timeout alone is not a kill.

XSim runs the full matrix if Verilator is unavailable. Cross-simulator traces
for uniform 1/16 and hotspot 1/4 remain NOT_RUN until the same seed/config is
available in both. MAC-on results measure framing only. N-9 computation cost
is measured separately using the real secure boundary.
