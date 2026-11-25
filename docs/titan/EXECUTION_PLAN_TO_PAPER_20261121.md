# TITAN execution plan | 21 November 2026

**Decision today. Retain S5R as the last accepted increment. Work on G0 evidence quality, contract reconciliation, literature and physical-flow preparation now. Kalash selects the implementation branch at G0.** This plan takes the team to the paper-ready evidence package. Dates below are internal milestones from v3. A calendar date alone releases no gate.

## 1. Baseline and review

The reference is revision 10, tag titan-base-20261119, b9e41c38. The planning snapshot is bee21769 on kalash/titan-rtl. Compare like-for-like with B0. Its historical board build measured 39,962 LUT, 29,187 FF, 20 BRAM36, WNS +0.182 ns and WHS +0.007 ns. Matched read/write medians were 32/32 cycles. The 34,952-LUT RC1 predates this baseline. TITAN has no accepted FPGA PPA here.

| Prior work | Disposition and consequence |
|---|---|
| S0 baseline, S1 golden, S2 passive monitor, S3 package | Preserve 30 fresh acceptances across these stages and 14 S1 golden workloads. S2 establishes observation on its tested merged-core configurations. D11 uses a different top. |
| S4 tracker, S4R correction | Use S4R, 19/19 fresh. The RTL presents the incremented epoch in the first registered authorized cycle. Earlier S4 results describe the earlier rule. |
| S5 stamp, S5R correction | Use S5R, 20/20 fresh on 3d6f5123, 14/14 B0 matches. The stamp retains the first-valid epoch through stall. Preserve the historical invalid bench. An epoch stamp alone supplies no end-to-end guarantee. |
| Arnav November 21 intake | SHA-256 495e768fecb964f096f0371372bf7876931319dd7de44c4540f09b6ba2bd6079. Updated helpers elaborate. All four XSim runs reached normal finish. M1 had 19 errors in 21 checks, M2 7/7, M3 1/3, SD 2/6. All four bench verdicts FAIL. None carried the live independent monitor. Reachability remains unaccepted. |
| Independent checking | Original scoreboard accepts missing input. Isolated replacement passed 13 synthetic tests on a restricted clean workload. Offline transcript checks recognized two historical monitored runs and rejected four D11 extracts. Live G0 monitor comparison and broader scoreboard qualification remain open. |
| Formal and timing | Arnav reports existing-gate formal results at named boundaries. Preserve origin, tool status, assumptions and covers. P6 end-to-end conservation, P5 completion and A-WRAP remain open. Historical isolated gate evidence cannot settle them. HARDWARE_VALIDATED=NO, SOC_INTEGRATION_COMPLETE=NO, FORMAL_PROOF=NO for this local TITAN checkpoint. |

**Decision precedence.** Retain original scope and v3 priorities wherever consistent with the later approved decisions. Record a supersession beside the original entry. Reconcile the co-signed Arnav copy of rev 11 with the local pending-signature text by diff and digest. Kalash and Arnav confirm the exact agreed text including D10. An unexplained substantive difference holds dependent work.

| Decision | Execution consequence |
|---|---|
| D1 | Use explicit same-name source-list substitution, generated TITAN variants, and one implementation per module. Preserve B0 source hashes. |
| D2 | Denial precedes address error. Review response reason priority at the final decision. |
| D3 | B2 globally stops admitting new HEADs while in-flight work drains. Freeze mode composition before comparison. |
| D4 / D10 | Trusted fail/timeout clears authority per gate semantics. Epoch advances on a registered 0→1 authorization transition. Review actual gate visibility, including first authorized cycle. |
| D5 | A single CPU DENIED code 6, poison 0xBADBE006. Preserve codes 1–5 and detailed wire reasons. Supersedes the old code-5 suggestion. |
| D6 | Latch the local read-filter decision on response HEAD. State the boundary in every relevant property. |
| D7 | Six-bit epoch. Prove stamp-to-last-possible-use lifetime versus receiving-gate wrap, or retain an explicit assumption/open result. Slot stale time alone is insufficient. |
| D8 | Same-cycle REVOKE wins at the final decision. Preserve the existing trusted path defined in rev 11. |
| D9 | A latency-changing register stage requires Kalash's decision before editing. |
| D11 | Arnav owns G0 benches. Local D11 runs are scratch. December 3 is a fallback request date. December 6 is the joint evidence review and Kalash's scope decision. |
| H1–H7 | Trace registered authority → epoch → request snapshot → final memory decision → response → bridge → observation. Verify H5 local HEAD boundary and H6 software-visible mapping independently of H7 monitoring. |

## 2. Ownership and working agreement

**Availability confirmed by Kalash.** The combined team starts after December 3, 2026. December 4 is the earliest start. Through December 3, Kalash and Arnav own all preparation, reviews and handoffs needed for their work. Combined-team review, replay, literature, ledger and physical-design deliverables first become dependencies after the handoff.

| Owner | Produces | Independent acceptance |
|---|---|---|
| **Kalash** | Scope, decisions, RTL/generator, constraints, registered stage runs, performance interpretation and owner board observations if hardware testing is authorized. | Arnav reviews behavior. Combined team reviews synthesis suitability. Kalash reviews Arnav's benches. Kalash and Arnav sign gates. |
| **Arnav** | Contract/property mapping, verification software, independent event interpretation, benches, reference model, formal boundaries/covers, statistical campaigns and formal evidence package. | Kalash reviews verification logic and checks evidence against RTL. Combined team independently reproduces results. |
| **Combined team** (two members, one accountable lane) | Physical design cut and fair PPA runs, FPGA result testing with Kalash, independent reproduction, literature differential, ledger, figures, venue and manuscript assembly. | Arnav reproduces physical synthesis. Kalash signs comparable configuration and reviews figures. Internally schedule physical runs early enough to leave time for independent replay. |

Daily async done/next/blocked. Wednesday resolve technical dependencies. Sunday review artifacts and record decisions. At each handoff provide revision, source/firmware/constraint hashes, tool and configuration, commands, frozen expected counts, raw logs and verdict, open conditions, owner and reviewer. No self-merge. Archive old failures. New registered results use the dual_lane.py selector, predeclared counts, harness self-test before registry changes, one regeneration per logical group. Respect protected sources, the single 20 ns clock and part, two-process limit, exclusive synthesis/implementation. Stop for any signed bound, wire, security scope, clock, device or budget change, design/contract failure, N-13 timing decision or full subsystem above 47,550 LUT.

## 3. Critical path and acceptance criteria

1. **Now to December 3 — establish a trustworthy intake.** Kalash pins B0, S5R, source lists and rev 11. Arnav supplies updated bench identities, expected checks and event definitions. First qualify a passive monitor on an ordinary authorized transaction at the actual subsystem top. Show its instance elaborates, records a nonempty transaction, and agrees with an independently derived ledger on identity, memory action, response and retirement. Include a missing-input control and a deliberately mismatched ledger control. Kalash reviews Arnav's packet and prepares the replay instructions. Exit with paired traces, an executable comparison and Kalash's intake verdict, or a list of missing items for the D11 fallback. Keep modeled timeouts separate from bridge-observed UNKNOWN. Record injected and natural workloads separately. Assess the four supplied bench verdicts against actual events; retain inconclusive rows.
2. **In parallel — close review inputs.** Arnav assigns each P1–P7 property a boundary, assumption, cover and evidence class. Kalash reviews the lifetime of an outstanding stamp through its last possible use. Arnav drafts the credit and slot reconciliation. Kalash stages the evidence index, tool manifests and open questions for the post-December 3 handoff. On December 3 request D11 fallback from Kalash if the evidence remains inadequate. Document fallback ownership and evidence class. From December 4, the combined team prioritizes independent replay of available G0 evidence and the closest-five-work comparison for the December 6 review. While awaiting any missing packet, they can prepare the results ledger, draft the common E8 cut and review the available credit and slot records.
3. **G0, December 6 — choose one written branch.** Kalash chairs, Arnav signs the evidence, the combined team presents available independent replay and literature findings. If a review needed for a scope decision is outstanding, record the missing evidence, owner and next review date. Continue any preparation that can proceed under the current scope. Accepted M1 supports S6 priority, accepted M2 supports S8 priority, both support both. Silent denial alone supports a denial-only investigation with a narrower claim. M3 alone goes to Kalash for a scoped decision about requester-visible finality. With inconclusive evidence, hold and identify the missing observation. If nothing is reachable under stated conditions or closest work subsumes the contribution, stop and reselect. Capture selected modes, stages, mandatory comparisons, property boundaries and exclusions in the decision. No research claim follows from an injected-only trace.
4. **S6, December 9–13 — final memory decision, if selected.** Kalash implements the guard at the existing last-word decision using request snapshot, current authority and epoch. Arnav verifies approved and denied operations, concurrent control priority and actual memory enables. Combined team reviews generated boundary and timing depth. Exit with accepted stage gate, frozen controls and B0 equivalence.
5. **S7, December 13–18 — definitive denial in selected modes.** Kalash implements one reason-coded response after final consumption. Arnav checks identity, zero read data, retirement, stalls and absence of duplicate outcomes or unintended side effects. Release to S9 only with a passing stage gate and agreed status mapping.
6. **S8, December 18–22 — read-response delivery, if selected.** Kalash integrates HEAD-latched authority/echo handling, with the chosen mode semantics and existing last/abort lifetime. Arnav checks whole response data and status, approved delivery and unaffected writes. Exit with reviewed latency, registered controls and B0 golden comparison.
7. **S9, December 22–25 — CPU outcome.** Kalash integrates the bridge result and fault code. Arnav checks SUCCESS, DENIED, ERROR and local UNKNOWN against the real bridge, firmware-visible values, one definitive result per transaction and preservation of legacy codes. Exit with firmware hash, observed results and stage report.
8. **S10, December 25–29 — comparative builds.** Kalash produces explicit source lists for approved profiles B0 reference, B1 denial, B2 drain, B3 read filter, B4 epoch guard, B5/TITAN combined. Record selected and omitted profiles. Arnav checks distinguishes-each-mode behavior and matched inputs. Combined team reproduces the configuration banners and checks comparable measurement boundaries. B0 must match all 14 frozen cases. A missing B2 or B4 removes support for a drain–epoch crossover claim.
9. **S11, December 29–January 3 — feature freeze.** Kalash integrates the merged core and release firmware. Run approved full regressions, compilation/elaboration for every selected mode, firmware boot, outcomes, contention, latency and controls. Arnav reconciles scoreboards and new warnings. Combined team independently rebuilds the source manifest. Exit with signed feature tag, mode matrix and gate report. A changed source reopens affected evidence.
10. **S12, January 3–10 — FPGA comparison (E9).** Combined team prepares identical Vivado 2024.1 recipes for B0 and selected variants on xc7a100tcsg324-1. Kalash authorizes implementation separately. Record routed top, part, clock, constraints, LUT/FF/BRAM, WNS/WHS, routing and DRC, image hash and cost deltas. Qualify timing for each reported mode individually. Where board validation is undertaken, Kalash records the exact programmed image, firmware, UARTs, LEDs, revoke and re-attest observations. Historical board evidence stays attached to its original image.
11. **S14 preparation overlaps S12/S13 — ASIC cut (E8).** Combined team owns the comparable enforcement boundary, Kalash the wrapper and mode manifests. Lock equivalent ports, included NI/gate/front end, libraries, constraints, corner, clock, floorplan and treatment of memories before evidence collection. Elaborate both B0 and selected cuts; reconcile black boxes and undriven ports. Use one pinned IHP SG13G2 flow, or record the approved common SKY130 fallback across all comparisons. Whole-SoC SRAM/ROM and FPGA-clock replacement belong to a separately scoped whole-chip handoff. Deliver the comparable synthesis cut before January 17. January 24 can close wrapper packaging; any later logic or boundary change invalidates affected January figures.
12. **S13, January 10–17 — evidence freeze.** Arnav leads assurance and campaigns, Kalash leads performance, combined team leads physical metrics and independent reproduction. Execute the matrix below on S11 identity. Archive failures/nulls and every omitted comparison. Kalash and Arnav freeze only reviewed rows with reproducible inputs. If Tier 1 evidence is missing, record a dated hold or explicitly narrowed scope. Draft methods, architecture and limitations can start earlier.
13. **Paper start gate, January 17.** Combined team regenerates figures and tables in a fresh checkout, reconciles each plotted value with a frozen ledger ID, checks official CFP/template/anonymity and records venue status. Kalash approves scope and wording, Arnav approves evidence classes. Agree authorship and acknowledgments before first full draft. Hand over F1 architecture/threat model, F2 matched observed timelines where supported, F3 implemented microarchitecture/outcomes, F4 latency/load/interference, F5 comparable physical area/timing; T1 closest work, T2 property status, T3 scenario/mode outcomes, T4 separate FPGA and ASIC costs. Flag limitations beside the claim they qualify.
14. **Downstream milestones for context.** Full draft January 24, internal paper completion February 1. Combined team assembles methods, figures and citations; Arnav writes verification and bounds; Kalash writes architecture, analysis and limitations. Route text through independent figure/claim review. The March 7 GDSII package is a later physical-design milestone with extraction, STA, DRC/LVS and archived decks. Only completed, reviewed physical results enter the paper.

## 4. Experiment blueprint and decision record for drafting

| Experiment | Deliverable, owner and acceptance |
|---|---|
| E1 G0 | Arnav supplies the case table with observable events, actual verdict and scope. Combined team independently confirms the accepted evidence. D11 failures remain in the ledger. |
| E2 epoch/lifetime | Kalash and Arnav document width, receiving-gate interval and maximum stamp lifetime including buffered work. Classify A-WRAP as open if either bound is unavailable. |
| E3 assurance | Arnav records P1 stale write safety, P2 read data, P3 response integrity, P4 at-most-one definitive response, P5 bounded completion, P6 credit/slot conservation, P7 interference. Per property state scope, assumptions, cover, engine/depth and U, B(k), S, F or X. Keep timeout UNKNOWN outside definitive-response uniqueness. |
| E4 comparisons / E5 campaigns | Arnav uses matching approved cases and seeds across designs. Combined team verifies denominators and observed outcomes. E5 target ≥1,000 transactions per configuration. Record lost, unmatched or censored observations. Retain effective, surviving and invalid controls separately. |
| E6 latency / E7 overhead | Arnav measures requested→effective and requested→complete, denial latency, throughput and unrelated traffic. Kalash owns matched workload and crossover interpretation. Use ≥5 offered loads for E6 and ≥10 seeds per stochastic configuration. Report N, min/mean/p95/max and 95% bootstrap intervals for distribution comparisons. Deterministic tests get exact counts. Report no crossover observed if appropriate. |
| E8 ASIC / E9 FPGA | Combined team provides same-boundary comparisons. Use ≥3 placement seeds per physical design, median and range; distinguish synthesis from routed data. Kalash reviews timing exceptions, comparability and units. |
| E10 reproduction | Combined team replays an accepted G0 trace, a formal result where available, a targeted control and a campaign. Arnav independently reproduces a synthesis. Record mismatches and their disposition before freezing a row. |
| L1 / publication | Combined team maps the closest work to contract, in-flight handling and requester-visible outcomes. Use primary evidence and report overlap. Kalash chooses claim strength after results and literature agree. |

**Tier order.** Prioritize B0/B1/selected TITAN, E1, E3 for P1/P3/P4/P6, E4–E8 essentials and evidence-backed paper figures. Retain E2, E9 and E10 deliverables per the stage plan. B2–B4 ablations, stronger P2/P5/P7 results, extra seeds/loads are second-tier per v3. If a comparison or proof is missing, narrow its claim. Each result row records ID, owner/reviewer, source/tool/target, mode, seed, exact command, raw log and digest, metric/unit, sample count, result and review state.

**Paper decision.** Methods and architecture can be documented today. The full results narrative starts once the signed result ledger, independent replay, scoped property table and reproducible figure sources exist. If G0 stops the project, document the negative or inconclusive finding and obtain a new research decision before commissioning downstream work.

## 5. Review trail and limits

Planning sources include the November 19 frozen scope and RTL stage blueprint, November 20 v3 paper plan, local rev 11 and signed-copy discrepancy, BASELINE.md, stage_reports/S0 through S5R, G0_D11_CHECKPOINT_20261121.md, the S6–S9 and S10–S11 preparation records, bound and P6 observation notes, and the isolated scoreboard transcript checks. Targeted RTL inspection included the revised tracker and stamp. The following inventory cross-checks the S5R compiled source paths against the planning tree. It describes review coverage and provides the per-file checklist for independent behavioral review. A path/hash match establishes identity only. No new simulation, formal, board or timing run forms part of this plan. Full semantic review of every implementation, verification dependency and historical decision remains outstanding. This plan carries no independently authenticated Astra model attribution.

### S5R compiled-source cross-check

Unique path/digest pairs across saved S5R runtime compilation manifests. The jobs column counts manifests containing that identity. Verify generated and staging-only entries in their recorded replay roots before reuse.

| Source | SHA-256 from replay | Jobs | Current file |
|---|---|---:|---|
| `C:/vivado_verilog_proj/_t5rr/reports/dual_lane_10_20261121_135030_abd7e1b2/it5r_b0_attack_approve_changed/workspace/dual_job.sim/sim_1/behav/xsim/glbl.v` | `6270251cf35e1fce3119fc79f8fb968912f7983027e43cf030409ba68f048936` | 1 | match |
| `C:/vivado_verilog_proj/_t5rr/reports/dual_lane_10_20261121_135030_abd7e1b2/it5r_b0_attack_reject_changed/workspace/dual_job.sim/sim_1/behav/xsim/glbl.v` | `6270251cf35e1fce3119fc79f8fb968912f7983027e43cf030409ba68f048936` | 1 | match |
| `C:/vivado_verilog_proj/_t5rr/reports/dual_lane_10_20261121_135030_abd7e1b2/it5r_b0_closure/workspace/dual_job.sim/sim_1/behav/xsim/glbl.v` | `6270251cf35e1fce3119fc79f8fb968912f7983027e43cf030409ba68f048936` | 1 | match |
| `C:/vivado_verilog_proj/_t5rr/reports/dual_lane_10_20261121_135030_abd7e1b2/it5r_b0_contention/workspace/dual_job.sim/sim_1/behav/xsim/glbl.v` | `6270251cf35e1fce3119fc79f8fb968912f7983027e43cf030409ba68f048936` | 1 | match |
| `C:/vivado_verilog_proj/_t5rr/reports/dual_lane_10_20261121_135030_abd7e1b2/it5r_b0_decoder/workspace/dual_job.sim/sim_1/behav/xsim/glbl.v` | `6270251cf35e1fce3119fc79f8fb968912f7983027e43cf030409ba68f048936` | 1 | match |
| `C:/vivado_verilog_proj/_t5rr/reports/dual_lane_10_20261121_135030_abd7e1b2/it5r_b0_error/workspace/dual_job.sim/sim_1/behav/xsim/glbl.v` | `6270251cf35e1fce3119fc79f8fb968912f7983027e43cf030409ba68f048936` | 1 | match |
| `C:/vivado_verilog_proj/_t5rr/reports/dual_lane_10_20261121_135030_abd7e1b2/it5r_b0_hasher/workspace/dual_job.sim/sim_1/behav/xsim/glbl.v` | `6270251cf35e1fce3119fc79f8fb968912f7983027e43cf030409ba68f048936` | 1 | match |
| `C:/vivado_verilog_proj/_t5rr/reports/dual_lane_10_20261121_135030_abd7e1b2/it5r_b0_i9_integ/workspace/dual_job.sim/sim_1/behav/xsim/glbl.v` | `6270251cf35e1fce3119fc79f8fb968912f7983027e43cf030409ba68f048936` | 1 | match |
| `C:/vivado_verilog_proj/_t5rr/reports/dual_lane_10_20261121_135030_abd7e1b2/it5r_b0_inflight/workspace/dual_job.sim/sim_1/behav/xsim/glbl.v` | `6270251cf35e1fce3119fc79f8fb968912f7983027e43cf030409ba68f048936` | 1 | match |
| `C:/vivado_verilog_proj/_t5rr/reports/dual_lane_10_20261121_135030_abd7e1b2/it5r_b0_lifecycle/workspace/dual_job.sim/sim_1/behav/xsim/glbl.v` | `6270251cf35e1fce3119fc79f8fb968912f7983027e43cf030409ba68f048936` | 1 | match |
| `C:/vivado_verilog_proj/_t5rr/reports/dual_lane_10_20261121_135030_abd7e1b2/it5r_b0_matched_secure/workspace/dual_job.sim/sim_1/behav/xsim/glbl.v` | `6270251cf35e1fce3119fc79f8fb968912f7983027e43cf030409ba68f048936` | 1 | match |
| `C:/vivado_verilog_proj/_t5rr/reports/dual_lane_10_20261121_135030_abd7e1b2/it5r_b0_matched_secure_contended/workspace/dual_job.sim/sim_1/behav/xsim/glbl.v` | `6270251cf35e1fce3119fc79f8fb968912f7983027e43cf030409ba68f048936` | 1 | match |
| `C:/vivado_verilog_proj/_t5rr/reports/dual_lane_10_20261121_135030_abd7e1b2/it5r_b0_mmio_guard/workspace/dual_job.sim/sim_1/behav/xsim/glbl.v` | `6270251cf35e1fce3119fc79f8fb968912f7983027e43cf030409ba68f048936` | 1 | match |
| `C:/vivado_verilog_proj/_t5rr/reports/dual_lane_10_20261121_135030_abd7e1b2/it5r_b0_phase_sweep/workspace/dual_job.sim/sim_1/behav/xsim/glbl.v` | `6270251cf35e1fce3119fc79f8fb968912f7983027e43cf030409ba68f048936` | 1 | match |
| `C:/vivado_verilog_proj/_t5rr/reports/dual_lane_10_20261121_135030_abd7e1b2/it5r_kill_no_hold/workspace/dual_job.sim/sim_1/behav/xsim/glbl.v` | `6270251cf35e1fce3119fc79f8fb968912f7983027e43cf030409ba68f048936` | 1 | match |
| `C:/vivado_verilog_proj/_t5rr/reports/dual_lane_10_20261121_135030_abd7e1b2/it5r_kill_non_memory/workspace/dual_job.sim/sim_1/behav/xsim/glbl.v` | `6270251cf35e1fce3119fc79f8fb968912f7983027e43cf030409ba68f048936` | 1 | match |
| `C:/vivado_verilog_proj/_t5rr/reports/dual_lane_10_20261121_135030_abd7e1b2/it5r_kill_trust_app/workspace/dual_job.sim/sim_1/behav/xsim/glbl.v` | `6270251cf35e1fce3119fc79f8fb968912f7983027e43cf030409ba68f048936` | 1 | match |
| `C:/vivado_verilog_proj/_t5rr/reports/dual_lane_10_20261121_135030_abd7e1b2/it5r_pkg_portable/workspace/dual_job.sim/sim_1/behav/xsim/glbl.v` | `6270251cf35e1fce3119fc79f8fb968912f7983027e43cf030409ba68f048936` | 1 | match |
| `C:/vivado_verilog_proj/_t5rr/reports/dual_lane_10_20261121_135030_abd7e1b2/it5r_stamp_unit/workspace/dual_job.sim/sim_1/behav/xsim/glbl.v` | `6270251cf35e1fce3119fc79f8fb968912f7983027e43cf030409ba68f048936` | 1 | match |
| `C:/vivado_verilog_proj/_t5rr/reports/dual_lane_10_20261121_135030_abd7e1b2/it5r_stamp_wire/workspace/dual_job.sim/sim_1/behav/xsim/glbl.v` | `6270251cf35e1fce3119fc79f8fb968912f7983027e43cf030409ba68f048936` | 1 | match |
| `NOC_PQATTEST.srcs/sim_1/new/tb_i9_integ.sv` | `00a2bfc77e08e1e7db48b5175073930ef59008c578bd6f02605a0eec40790017` | 1 | match |
| `NOC_PQATTEST.srcs/sources_1/new/NOC_CROSSBAR.sv` | `467e35f8633c3cddcddc6302304bd9bb86f7e046c1e615d37d783b68fbcc95c3` | 12 | match |
| `NOC_PQATTEST.srcs/sources_1/new/NOC_DATAPTAH.sv` | `2c77b62919e2fe1f67e2267c1344847d170f6fc4451b35c9589332ecf8cc1565` | 12 | different; CRLF normalization matches |
| `NOC_PQATTEST.srcs/sources_1/new/NOC_FIFO.sv` | `abaadfd2551f06e659034b61e77d0551982c188af2e63559f6c6b5d825c4c175` | 12 | match |
| `NOC_PQATTEST.srcs/sources_1/new/NOC_XY_ROUTING.sv` | `6b92bf51f142279a37272372bbdda75b1412ac930772dd17ded3d41c454d7416` | 12 | different; CRLF normalization matches |
| `NOC_PQATTEST.srcs/sources_1/new/NOC_arbiter.sv` | `4ad8600ce9ec5e9d9cfd41c99679e251e922ea5c2989753a985dd67e41b086a2` | 12 | match |
| `NOC_PQATTEST.srcs/sources_1/new/SHA3_256.sv` | `700a4a9aa57691dd578c1c82ba7755a04353ed88ff7e04bd6825aee6db5f6ce5` | 11 | different; CRLF normalization matches |
| `NOC_PQATTEST.srcs/sources_1/new/SHA3_ABSORB.sv` | `79e5eade0bea45604b7dc747f7a580775a5e67dd43fa49f1dafac7a25af3e98f` | 11 | different; CRLF normalization matches |
| `NOC_PQATTEST.srcs/sources_1/new/SHA3_PKG.sv` | `10240034c96f88b6dc47e52a057d0de8dc9924e832db1cb3bcc122872c889ef3` | 13 | different; CRLF normalization matches |
| `NOC_PQATTEST.srcs/sources_1/new/allocator.sv` | `cfafbd752c1f67f3d4eb9719f8382cf7fad9e96bf5e97b1e4815fdeb12b50907` | 12 | match |
| `NOC_PQATTEST.srcs/sources_1/new/kmac_absorb.sv` | `bf567d45f9154a48b4f3583ab15619eaba5beac21656774ad0b7b7a28a25d640` | 12 | different; CRLF normalization matches |
| `NOC_PQATTEST.srcs/sources_1/new/kmac_encode.sv` | `9f25a1d240d70da8eceb86d232f531614ba202cffc80f3a26b601ecc49d4f712` | 12 | match |
| `NOC_PQATTEST.srcs/sources_1/new/kmac_pkg.sv` | `ef83b37a79de495197a3919944a5e6150a6f64a35e17425988195284cf12d13b` | 12 | different; CRLF normalization matches |
| `NOC_PQATTEST.srcs/sources_1/new/noc_credit_counter.sv` | `959739e48db58d0d0ab0e4e26a90a5e41e0c1ac94cfc7fc4e68c202257ccca30` | 12 | match |
| `NOC_PQATTEST.srcs/sources_1/new/noc_mesh_3x2.sv` | `1bd171567ae2fc1708ccae8f5b0b56d461813de581b1cc7774d9aa2bf0e451cd` | 12 | match |
| `NOC_PQATTEST.srcs/sources_1/new/noc_router.sv` | `6bd5d99794358361d07df834b7141b0cfb2c952e0dbd5f427549bf583b85f773` | 12 | match |
| `NOC_PQATTEST.srcs/sources_1/new/pq_kdf_pkg.sv` | `375bb22ab9358a16c444277217dfa9b037f44800c4935ff5089a8be90c50d8b0` | 12 | different; CRLF normalization matches |
| `NOC_PQATTEST.srcs/sources_1/new/pq_keccak_chi.sv` | `17bf94c2fa5e2ec7b77de9b512f2dfe7f3c1226bc39d536316b110f94d59be41` | 13 | match |
| `NOC_PQATTEST.srcs/sources_1/new/pq_keccak_pi.sv` | `f65862c501eaf17bee03b90c97fc22efa9718f6e8513a5dc0dd80f2f97c550f2` | 13 | match |
| `NOC_PQATTEST.srcs/sources_1/new/pq_keccak_pkg.sv` | `b7193273caa6b89e27574ceed588a4dd4bd572247813fa63dfeae2906dd91e3f` | 13 | match |
| `NOC_PQATTEST.srcs/sources_1/new/pq_keccak_rho.sv` | `d3354ec0ff08d51392f69794e93dcfd64120740ae477d055f4dae0179cc91256` | 13 | match |
| `NOC_PQATTEST.srcs/sources_1/new/pq_keccak_round.sv` | `c3feda08b6af0121f0a216978bed74a1ab06821e9e2d02f569d7d02833d8b40f` | 13 | match |
| `NOC_PQATTEST.srcs/sources_1/new/pq_keccak_theta.sv` | `322adee9c6c6c21ee5bec8b3b2dff18fd64e297b983be7115e853660299d67a4` | 13 | match |
| `NOC_PQATTEST.srcs/sources_1/new/pq_measurement_pkg.sv` | `92e04ef9c30d4ae92726f36bcd6c7bfece1026cdc30b814234decf65ed22a883` | 12 | match |
| `NOC_PQATTEST.srcs/sources_1/new/pqattest_stg7_pkg.sv` | `ee8d0cc0280d281de2dbdd7232c0b31238082f254299b19a7155fcddf76299cb` | 12 | match |
| `rtl/dual_lane/NOC_PKG.sv` | `e428af103c9a0096f47f9ad97215a33b919dc9035c2a5e9d1255ff9fdd33a7be` | 18 | match |
| `rtl/dual_lane/SHA3_256_xp.sv` | `38f372d6b541bc75cd06fbb2fb76dd243b1d6372df3f9e90f47f2828920e0234` | 12 | match |
| `rtl/dual_lane/SHA3_PAD.sv` | `41ff37e0694bfce7348b75866f4d460b384dae534a1f9220dcff6497338d5743` | 11 | match |
| `rtl/dual_lane/kmac_128_a5.sv` | `4b5c867d5cffc5ca2811ef785b0bb381f5b5a1be401ae3d85c1fc3f6671685bb` | 12 | match |
| `rtl/dual_lane/kmac_128_xp_a5.sv` | `e0302fd5503dc5ddd322432731016e8a7d3d335d9f829bfbf51ab34461017b04` | 12 | match |
| `rtl/dual_lane/l2_arbiter.sv` | `794a454d75e55e0152045ce20cb2ce311c72020faff1e4ba8911f3cca8b70907` | 12 | match |
| `rtl/dual_lane/l2_kmac_engine.sv` | `ce45854dab8e4554dc8cbe6b2979254304cdf7462ba93e7158233f1f18ba8b42` | 12 | match |
| `rtl/dual_lane/merged/pq_soc_merged_core.sv` | `68e5defd0407b88514800f8ea8a85efb0d2e77f9e3ee9c091b4d7cfad016c824` | 10 | different; CRLF normalization matches |
| `rtl/dual_lane/merged/tb_matched_memory_v10.sv` | `395dacddb25bc6e0cf2d5d4b4260ff2fc08d740a11bd06a0d537aa5765c68152` | 2 | match |
| `rtl/dual_lane/merged/tb_merged_attack_v10.sv` | `9b46a4464ab628aea68cbc39c949c3a6f0a74126d1d6d1f399036dff03b7f101` | 1 | match |
| `rtl/dual_lane/merged/tb_merged_attack_v10_v2.sv` | `d024308815e88915a7d11c935162224ea9c3271490f93b0ef27a06283219acf2` | 1 | different; CRLF normalization matches |
| `rtl/dual_lane/merged/tb_merged_closure_v10.sv` | `f19348d1f7ba8619659d08e7daf24ab38cf4bb8b0b84e506b0cb86f09a75bd31` | 2 | match |
| `rtl/dual_lane/merged/tb_merged_contention_v10.sv` | `2101dd665b651268546d41116ffe313605ed850d5e650a4b1faaba6323422b71` | 1 | match |
| `rtl/dual_lane/merged/tb_merged_error_v10.sv` | `b47ab76dd0fe833e7d6f4efa9a413773afecdd6937e7bdf8bcfd10a1a58c3850` | 1 | match |
| `rtl/dual_lane/merged/tb_merged_inflight_v10.sv` | `a033da221c3237510cc76f6c59707a6733d22ff676967a38ff8b391e641389a4` | 1 | match |
| `rtl/dual_lane/merged/tb_merged_phase_sweep_v10.sv` | `52debaff588f34a899432da3ba4472a8e0d0ac80e9c8034b32039834a7734909` | 1 | match |
| `rtl/dual_lane/noc_attest_gate.sv` | `f05881987d3bffbba6ed5ee1c6d99bfa7b5b11f50d549ba73c9b0a6627ba7235` | 12 | match |
| `rtl/dual_lane/noc_fault_status.sv` | `16591d516ccdf95d4691a41d53240faf29ec30a44fb2cfd57d739d8a5275f14f` | 12 | match |
| `rtl/dual_lane/noc_ingress_parser.sv` | `a6fe871dcb86f952d6eae37a83de41fde24e4232393e152b34e1d61ec79fb1ae` | 12 | match |
| `rtl/dual_lane/noc_ingress_quarantine.sv` | `90671f9c8ee4cacc67d686fa4c9550325ddc46d672c886dff19975201c2f02af` | 12 | match |
| `rtl/dual_lane/noc_l2_auth_p7_i9.sv` | `84a9bea5569a6a61b9d9a47717e0828565359d1ab1f26ebdd0ca5f9883500933` | 12 | match |
| `rtl/dual_lane/noc_l2_p7_pair_i9.sv` | `8dbdc1ae919cb756be647572adf39c0bf2414d65d2e2b2b8e155d0ada280accb` | 12 | match |
| `rtl/dual_lane/noc_network_interface_p7_i9.sv` | `e3729b0550ce2520474920528e106d4b049db17997e3ee837a4f042029602f97` | 12 | match |
| `rtl/dual_lane/noc_p7_pkg.sv` | `8a10decc6d39c5b1dcb097f2aa638e8fb348e88d7a2fb85a696083d3a5ffe4f0` | 12 | match |
| `rtl/dual_lane/pq_attest_endpoint.sv` | `9cb038b294cf014bc55f59fab19fe2883fac2e0fbf9522d560e498336bbb1c1d` | 12 | match |
| `rtl/dual_lane/pq_attest_protocol_s3.sv` | `a467d34cca95b9a37794c76159a931ba26ea7819630c7f414f5d2f51e81d0cb4` | 12 | match |
| `rtl/dual_lane/pq_attestation_tag_xk.sv` | `dd0eaca4b609a725d541e0f4f2601af788ebcbf857a0255f36559fa08828b103` | 12 | match |
| `rtl/dual_lane/pq_kdf_xk.sv` | `9670eaa6a327a9ccd0603adb2680489446e2f84e59a33827effc77da4abc6f44` | 12 | match |
| `rtl/dual_lane/pq_keccak_f1600.sv` | `3d763b0af3cd58ef5cab103dfdd665881b8eca6c06e292dd2e0cf0b430038758` | 13 | match |
| `rtl/dual_lane/pq_keccak_iota.sv` | `d84b125dc8119c1b2f68421d62ef28b239df367f2692e9c4840ec384cc29b369` | 13 | match |
| `rtl/dual_lane/pq_kmac_share.sv` | `2131259352a437d27837bc352a2d788d220fba79dc5c97886ef2dfb2e69506be` | 12 | match |
| `rtl/dual_lane/pq_kmac_share_xp.sv` | `43d2b25e4cce85ba9eb1c2891c9a0c8575b15662ed9ec883c0fc1e42f238106b` | 12 | match |
| `rtl/dual_lane/pq_measurement_xp.sv` | `ba9ac9fc58bbc2a8983dc3ff67f344eff57043735730d67a0f64c4ac2928f326` | 12 | match |
| `rtl/dual_lane/pq_rot_verifier.sv` | `e9894b57ca05e2d1acf1baa3fcfe320d3462f29f40936fadbdd4af0c537dedaa` | 12 | match |
| `rtl/dual_lane/rst_bridge.sv` | `2c6adf573e0170b84162ea7b66bdcaa5cbf9dfc8f87a30bde34963aabe8ab519` | 12 | match |
| `rtl/dual_lane/titan/s5/titan_stamp_mut_no_hold.sv` | `b88b078727147d2993ce0f10bd65d1ab303f27c8945265e236bffff8026e52d8` | 1 | match |
| `rtl/dual_lane/titan/s5/titan_stamp_mut_non_memory.sv` | `15a84a3c91e1f0baef8a7969c4e3e81d65a9a9dea06ba4ead5afb540fb0c2a74` | 1 | match |
| `rtl/dual_lane/titan/s5/titan_stamp_mut_trust_app.sv` | `a15bbebbac9251afa66c4fe2f29157eaf3fd6f509586edcab09ed37a348d3877` | 1 | match |
| `rtl/dual_lane/titan/s5r/pq_noc_subsystem_p7_t1.sv` | `5792a0fa575fa8f8126ff323a8087cb1429a7b11d73ac265e233870cdb40f900` | 12 | match |
| `rtl/dual_lane/titan/tb_titan_pkg.sv` | `d74b0a3746fbf2812ca03c3e358fe8c8e0d73fbf86020362b02eeaf97b9581ea` | 1 | match |
| `rtl/dual_lane/titan/tb_titan_stamp.sv` | `49bb5f4d467b89c4f351b7a5214ac64c02f8dddfcc8b7a3a7c77be443e235b17` | 4 | match |
| `rtl/dual_lane/titan/tb_titan_stamp_subsystem_r1.sv` | `839e2b09e593e7aa01a384a97c7802cf2d40db0b6a55ea8d5269b135fb19c5d8` | 1 | match |
| `rtl/dual_lane/titan/titan_epoch_stamp.sv` | `58ad898afe7409e38520f5ac88dedbd37e75b278bf827b261da88ab921b45120` | 13 | match |
| `rtl/dual_lane/titan/titan_epoch_tracker_r1.sv` | `0b5da812b7eeec72a7c41022738d3d23f363459df430f6bc9a96b079b12b1f81` | 12 | match |
| `rtl/dual_lane/titan_pkg.sv` | `f5ed0e4a14e93a30445ba86085c0bc43a1e8619de787c081d679590c817ab6e9` | 17 | match |
| `rtl/riscv/addr_decode.sv` | `f9a7311b0f572d8e8cf49a89ab591219085fe9b820f45c1778cf412a8cd95739` | 12 | match |
| `rtl/riscv/cpu_tile_noc.sv` | `c1295fca7675fb46b8cf3e954e495dbc25d68097e091dc5cbf5613abb7a5ad6e` | 11 | match |
| `rtl/riscv/gpio.sv` | `ea14e1040d564fd83bde8d15373e47e786086012030bec5158870239a981d539` | 11 | match |
| `rtl/riscv/meas_imem_hasher.sv` | `a1d2393b7638ffd3feaed6886a28143d77af456068062d941760cc33770af424` | 11 | match |
| `rtl/riscv/meas_window_reader.sv` | `c698c1c2c512f54d0e6712d1354b6ddb2ce0506d1f0c800bc24eb59340c6ef12` | 11 | match |
| `rtl/riscv/mem_bram.sv` | `dcf5d97cd44b4e0512d263e613b1b1cc1c146c12f8ff4cca994f99b5b78f6c48` | 11 | match |
| `rtl/riscv/picorv32.v` | `0836050971b3c6cdd28ac3b1e5719a67fb645161912bef1e472e63995ceb0622` | 11 | match |
| `rtl/riscv/picorv32_adapter.sv` | `75e23874d86221b4b1cb0f063fac5fea637c082db4f9aa602724f0d76c3ba5f1` | 11 | match |
| `rtl/riscv/tile_mem_wrapper.sv` | `81957a02fd159c838add40d25a08da98f93f99bacd80337b7c6f3b2da7f595d7` | 11 | match |
| `rtl/riscv/tile_status.sv` | `a6a9f4b0a2a3bfda77c0a524174d89bfddc8d758f2fcb91b873c351945f65cf4` | 11 | match |
| `rtl/riscv/tile_top.sv` | `8b9ca421fd2d4a4ba0ff7e5f4f656436405c6b405b30b0189ea953478265bb20` | 11 | match |
| `rtl/riscv/tmem_app_bridge.sv` | `cc293664ed50336fcd1caa50edeead948f1d2593e940a84a7d338b0bf37b7c2a` | 11 | match |
| `rtl/riscv/uart_mmio.sv` | `00a85e5f264fd53f4319903fef9d2f199e6f9183d65f762f2ee43ecc70528861` | 11 | match |
| `rtl/riscv/uart_tx.sv` | `33c52952fcc5f44c64b424711ce7234a05edab5480beb33041ff612c6c60bd12` | 11 | match |
| `sim_riscv/app_port_checker.sv` | `093ae2d9f996ed0ddf25f2629c13e52434d8c4e95f3635684e436c2365804081` | 2 | match |
| `sim_riscv/tb_addr_decode_v10.sv` | `26255f87903af47a748b1f0eaa8c7eca492e238edca6f73742409147767c081f` | 1 | match |
| `sim_riscv/tb_meas_imem_hasher_v10.sv` | `c3f1459ad76726b1906f82fe2233c9c0c18412ac5777c5c961f8859a992398ee` | 1 | match |
| `sim_riscv/tb_r10_mmio_guard.sv` | `146cb6fe0b5d98492f3e5de8d0cdc19bf26befab1e869eaf30ed098dbc8f9f24` | 1 | match |

Of 108 path/digest pairs inspected, 98 were byte-identical in the working tree. Classification of the other ten after recomputing digests: CRLF normalization (10). Use the recorded digest for evidence reuse.
