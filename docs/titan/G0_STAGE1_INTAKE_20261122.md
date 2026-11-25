# Stage 1 G0 intake | 22 November 2026

**Disposition: HOLD for scope selection.** B0 tag titan-base-20261119 resolves to b9e41c38. S5R acceptance is recorded at 3d6f5123. Rechecked all 55 pinned B0 source bytes before building the clean-only scratch project. Main intake SHA-256 937c63b4338cd10249259326d61cf2a0c55d114dd113c1437e5f3bc9a639314b. The separate clean-control file contains a checksum line. The main archive contains the clean bench, bind and CSVs.

## Revision 11 provenance

The November 22 archive copy (SHA-256 14383ea2f57edd4439055fff37092f48e174b647d9844e75c3945cdb4e230d0b) differs from the previously verified co-signed copy in exactly three signature lines. The newer archive reverts those lines to signature pending. Continue using the previously verified co-signed digest d375a684b7eb050bd93bc054f77f76b96f34f94c106f85f36583b241129ba30e. Technical text agrees. Retain both copies and record the discrepancy for Arnav.

## Clean ordinary transaction

Scratch at C:/vivado_verilog_proj/_g0clean_20261122. Vivado 2024.1 xvlog compiled the 55 B0 inputs with PQ_MAC_ON, the unchanged received clean bench and subsystem bind, the local passive monitor and the extracted tap module. The clean fixture defaults to TB_INJECT=0 and freezes six checks. Command from scratch was xvlog -d PQ_MAC_ON -i C:/vivado_verilog_proj/_t4rr -prj clean.prj. Strict compile failed on the existing SHA3_256_xp.sv declaration-order diagnostic. Retried with --relax as in the recorded D11 launcher. It exited 1 at titan_subsystem_mon_bind.sv:58 with VRFC 10-4982, syntax error near '['. Neither elaboration nor simulation ran. See compile_strict.txt and compile.txt. This is a scratch compile diagnostic.

Previously repeated offline comparator controls gave 0 for matching, 1 for missing input, and 1 for changed outcome. The supplied bench creates both CSV ledgers and the raw monitor event file contains only a header. The reported matching cycle values remain unconfirmed. The clean acceptance package needs a normal six-check XSim verdict, a monitor-owned trace with observed acceptance, memory action, delivery and retirement, an independently produced bench record and the comparator result.

## Case disposition

| Case | Prior local D11 errors / checks | Intake disposition |
|---|---:|---|
| M1 | 19 / 21 | Unaccepted. Preserve Arnav’s observations and their workload classification. |
| M2 | 7 / 7 | Unaccepted. Preserve the reported observation and its evidence limits. |
| M3 | 1 / 3 | Inconclusive for CPU-visible UNKNOWN. The newer report labels the timeout as modeled. |
| SD | 2 / 6 | Unaccepted. Keep the observed verdict and supporting interval together. |

Next intake dependency is the independently recorded ordinary transaction and evidence that supports each proposed case verdict. S6/S8 require Kalash’s explicit G0 selection. Combined-team work starts December 4. P6 and A-WRAP stay open. HARDWARE_VALIDATED=NO, SOC_INTEGRATION_COMPLETE=NO, FORMAL_PROOF=NO.

## Local replay update | 22 November 2026

Kalash’s lane owns Vivado/XSim replay. The original archive is the intake record. The scratch bind changed one expression to select the byte in each ternary branch before comparison, an equivalent syntax accepted by Vivado. The clean fixture uses the pinned vectors directory for its include. Compilation put the top in xil_defaultlib.

Commands from the scratch root, using Vivado 2024.1 binaries:

    xvlog --relax -d PQ_MAC_ON -i C:/vivado_verilog_proj/_t4rr/vectors -prj clean.prj
    xelab --relax xil_defaultlib.tb_clean_txn -s snap_clean_txn
    xsim snap_clean_txn -tclbatch bounded.tcl

Logs compile3.txt, elaborate4.txt and simulation4.txt. The clean fixture finished normally at 25,150 ns with six checks, zero errors, RESULT PASS and TB_INJECT=0. It verified normal authorization, write acceptance, the memory value, response delivery and the slot cleared check. Bench landmarks were 1219, 1241, 1252 and 1257. These use bench observation points, including a delayed slot check. The active monitor emitted its own summary with zero reported counters for this transaction and maxlat=26. The bench’s 33-cycle interval starts at a different observation point. These measurements belong to this scratch run.

The raw event CSV is still header-only. A monitor-owned transaction ledger with observed retirement remains pending, so the six-check clean smoke is complete and the G0 evidence and scope decision remain open. No production RTL, registered test count or contract was changed.
