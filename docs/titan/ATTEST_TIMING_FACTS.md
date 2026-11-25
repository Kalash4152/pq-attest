# Attestation timing facts for D10

Clock: 20 ns. The observations below predate the D10 implementation and are registered XSim evidence for their named configurations.

| Quantity | Registered provenance | Result |
|---|---|---|
| Idle full-subsystem control RTT | n2p7_rtt, run 20261029_140104_d9fb229d, source 27e7169, I5_GATE_20261029.md | 1,204 cycles (four observations); loaded range 1,205–1,206. |
| GRANT transport through L2 | Same n2p7_rtt job | 122–124 cycles from GRANT HEAD into mesh to tile-3 delivery. |
| C4 revoke bound | M-F1-interface-freeze.md, §7 | ≤1,500 cycles from verifier revoke input to authorization falling. |
| C4 historical phase/load campaign | p7_c4, B-4 run 185719, registry 65ac72b, S1_GATE_20261023.md | 486 cycles maximum. |
| Revision-10 merged control timing | it1_phase_sweep, run 021237_3e3d1a4a, source 24525209 | 1,253 cycles from start to grant and 232 cycles for each of the seven revoke phases in this bench. |
| Shared L2 engine job | l2e_engine, B-4 run 231047, registry 65ac72b | Job bound 128 cycles checked, including engine overhead. This is an upper bound. |

No standalone registered timing measurement of per-call KMAC, the 24-round permutation or individual endpoint and verifier phases was located in these records. RTL shows 24 state-update rounds per permutation and three serialized permutations per short-message KMAC in the selected kmac_128_a5.sv. These are structural counts. Measured RTT and revoke latency do not bound minimum GRANT spacing.

## Derived minimum for successive receiving-gate authorization rises

Scope is reset-free tile-3 operation with authenticated L2 on and no TB_INJECT or bypass. The remote verifier sends a new CHALLENGE after the previous GRANT on the same ordered control VC and peer path. At receive, the peer replay slot completes the earlier GRANT before delivering the next CHALLENGE. The endpoint can only start the next RESPONSE after delivery of that later CHALLENGE. Tile-3 RESPONSE TX computes the L2 MAC before emitting the packet (T_REQ/T_WAIT → T_ISSUE). Tile 4 computes its RX MAC after collecting the RESPONSE and before replay to the verifier (P_COL → P_REQ/P_WAIT → P_RDY). The verifier cannot send the next GRANT before that response is delivered and verified.

Those two RESPONSE KMAC jobs are causally serial and each takes at least 3 × 24 active round cycles. This gives T_GG ≥ 144 cycles as an RTL lower bound for the stated path, ignoring additional nonnegative control and transport overhead. It is neither an exact minimum nor a formal result. Under the proposed 8,192-cycle lifetime, 63 × 144 = 9,072 > 8,192. The lifetime itself requires independent closure: the configured NI timeout first marks a slot stale and later frees it. A-WRAP stays X until the relevant lifetime and protocol assumptions are checked.
