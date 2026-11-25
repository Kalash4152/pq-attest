# G0 local review and scope decision | 22 November 2026

## Ordinary authorized transaction

Vivado/XSim 2024.1, pinned B0, PQ_MAC_ON, 20 ns, TB_INJECT=0. The scratch-only clean_trace_observer.sv wrote its own CSV at the bench and subsystem interfaces without reading the bench's counters or driving DUT signals. The six frozen bench checks passed, zero errors, normal finish at 25,150 ns. This is D11 scratch evidence.

| Event | Passive sample cycle | Bench cycle |
|---|---:|---:|
| App handshake | 1220 | 1219, captured before calling the header task |
| Inner NI request issue, tag 0 | 1226 | No separate inner NI sample |
| Memory commit tap, tag 0, address 0x22000100, data 0xAABBCCDD | 1240 | 1241, memory value observed |
| Response delivery, tag 0 | 1252 | 1252 |
| NI slot occupied to free, tag 0 | 1253 | 1257, delayed empty check |

Authorization was high at all five samples. NI issue to delivery took 26 cycles, matching TITAN_SUMMARY maxlat=26. The event order, tag, data, response and retirement agree with the functional bench checks. Cycle landmarks differ because they sample different events. The commit observer uses the passive bind's commit tap and the bench checks the actual memory value. The bench's normalized files are not used as independent evidence.

Scratch root C:/vivado_verilog_proj/_g0clean_20261122. Commands using C:/xilinx_vivado/Vivado/2024.1/bin:

    xvlog --relax -d PQ_MAC_ON -i C:/vivado_verilog_proj/_t4rr/vectors -prj clean.prj
    xelab --relax xil_defaultlib.tb_clean_txn -s snap_clean_trace
    xsim snap_clean_trace -tclbatch bounded.tcl

See compile_trace.txt, elaborate_trace.txt, simulation_trace.txt and results/g0/local_independent_events.csv. No production RTL or accepted evidence changed.

## G0 case review

| Case | Latest handoff claim | Local disposition |
|---|---|---|
| M1 | Observed in injected workload. Absent in the reported uncongested natural sweep. | Inconclusive for intended-profile reachability. Earlier local D11 reported FAIL. |
| M2 | Observed in injected workload. Absent in the reported uncongested natural sweep. | Inconclusive for intended-profile reachability. Earlier local D11 reported FAIL. |
| M3 | Observation uses a modeled bridge timeout. | Inconclusive for CPU-visible UNKNOWN. Earlier local D11 reported FAIL. |
| Silent denial | Reported in both profiles, with slot held stale. | Unaccepted. Earlier local D11 reported FAIL. The current ordinary trace covers successful retirement only. |

Reviewed the supplied case report and sweep inventories. No new case replay was run. P6 and A-WRAP remain open.

## Scope decision for Kalash

Recommended disposition is to close this G0 review as inconclusive, with the ordinary observation check accepted as scratch and S6/S8 held. Alternately keep G0 open if a supported case verdict is required before ending the stage. Scope approval is pending.

## Follow-up diagnosis and scope recommendation

M2's archived simulation.txt line 16 first fails M2_INITIAL_GRANT. Its own 1 ps VCD records grant_done at 19,750 ns and tile 3 registered authorized at 24,350 ns. The old bench lines 147–148 treated them as simultaneous. The November 22 archive already contains a bounded registered-authorization wait before this assertion. That resolves the identified setup assumption at source level. Later case assertions remain unadjudicated.

A fresh scratch XSim replay of the existing 19-check tb_tmem_app_bridge fixture passed, with BRIDGE_TIMEOUT=64 and LATE_DRAIN_CYCLES=400. No-response error appeared at 66 cycles, ready-held-low at 65 cycles, and the subsequent read received its own data. See C:/vivado_verilog_proj/_bridge_diag_9323f82/simulation.txt. This covers bridge-unit behavior in the short test profile.

In C:/vivado_verilog_proj/_g0clean_20261122/interval_sim.txt, the ordinary authorized-write bench passed 6/6 and the passive per-cycle observer logged every sample from NI issue (1226) through slot retirement (1253). check_clean_interval.py verified all 28 samples, the single response at 1252 and the complete slot sequence. Removing one sample or inserting a spurious response caused rejection. The observer is qualified for this clean fixture. Silent denial and late remote commit remain unestablished. Both fresh simulations are D11 scratch diagnostics.

Recommend recording G0's current scope finding as inconclusive and holding S6/S8 pending Kalash's decision. These diagnostics identify a bench setup defect and qualify measurement on ordinary traffic. They establish no functional RTL change requirement.

## Arnav's November 22 scope recommendation

Keep the accepted B0/S4R/S5R work as the proposed December core. Use the November 27 evidence review and November 30 scope decision for any increment. Kalash and Arnav own both checkpoints. The combined team is outside this decision's dependencies.

| Case | November 30 decision input |
|---|---|
| M1 | The handoff's injected observation is preliminary. Reachability in the intended profile remains inconclusive. A nominal timing comparison does not give a worst-case bound. |
| M2 | Same profile limitation as M1. The old local first failure is explained by the grant sampling error. The standalone subsystem's observations end at the RX boundary. A software-delivery claim needs evidence at the requester boundary. |
| M3 | Modeled subsystem timeout and a passing 19-check bridge unit run are separate observations. Actual CPU-visible UNKNOWN paired with a memory-side result remains inconclusive. Stage S9 implements the planned outcome mapping. |
| Silent denial | Plausible response-handling gap. Archived local D11 was 2 errors in 6 checks. The 600-cycle reported occupancy is a bounded observation. Existing NI RTL has a stale-to-free path on the second expiry when aging is unpaused, so permanent leakage is unsupported. Record the request and denial boundary, complete response observation interval, matching slot and release cause before accepting an SD claim. |

If the SD boundary evidence supports an increment and Kalash approves it, select S7 for explicit denial. S8 is the read-response filter. S9 owns CPU-visible code 6. S7 scope does not depend on M1 or M2 passing. A supported M1 or M2 finding is evaluated against its own stage criteria. If no optional increment is supported by November 30, sign the B0/S4R/S5R scope for December, with the deferred stage IDs and reopening criteria. Keep P6 and A-WRAP open.

The proposed replay of the access-control bypass cases was not performed. Use existing records for case dispositions and local Vivado for ordinary operation and defensive checks. The already-passing clean and bridge diagnostics remain scratch evidence.

## Arnav's follow-up on silent denial | 22 November

The November 22 archive does contain a 600-cycle response-HEAD scan in the HEAD-drop case. This improves the earlier point sample. The bench waits for any m_ev, then checks whether slot 0 is valid at the end of the window. It does not assert the matching denial reason, confirm a stale transition, or observe eventual release for that request. The packaged CSV writes its stale and response fields as constants. The archived local two-error result is from the older fixture. No new SD run was performed in this review.

The 600-cycle model setting and observation interval are distinct from the pinned CPU profile's 8,192-age-tick NI timeout. In the unpaused no-response path, the first interval marks the slot stale and the second frees it. A 26-cycle ordinary transaction observation does not establish denial-response latency. Under revision 11, S7 uses existing packet lengths and emits one reason-coded response after final consumption. CPU-visible code 6 belongs to S9.

Disposition for the joint decision: B0 response suppression is supported by source review. The specific run-level denial, full matching response interval, and actual retirement remain unconfirmed. Proceed with B0/S4R/S5R as the working December scope. S7 remains conditional on stronger evidence and Kalash's explicit approval. Arnav concurs with the core scope and the November 27/30 review cadence.
