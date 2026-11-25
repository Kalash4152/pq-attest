"""
verification/p7_rtl_mutant_proposals.py
=======================================
PQ-Attest P7 RTL Mutant Proposals — Step 18 (Evidence-Grounded Correction).

Engineer 4 Verification Infrastructure.

Source of Truth:
- JSON manifest: verification/generated/p7_rtl_mutant_proposals.json (SINGLE SOURCE OF TRUTH)
- Kalash Bheda Intake Report: reports/E4_FINAL_INTAKE_20261106.md (Section 3 triage)
- Registered I-11 Run: dual_lane_10_20261106_163900_ff77f562
- Registered RTL Sources:
    - BRAM window and byte enables: pq_noc_subsystem_p7_i9.sv (tile-2 front end)
    - I-9 NI timeout and slot logic: noc_network_interface_p7_i9.sv
    - XY routing: NOC_XY_ROUTING.sv
    - VC assignment: NOC_PKG.sv (message_to_vc)
    - Verifier tag / epoch / ID: pq_rot_verifier.sv (epoch and tile ID bound in expected tag)

Classification Categories (Kalash Triage):
- implemented: Real gaps identified by E4, implemented and registered in RTL under I-11.
- already_covered: Covered by an existing killed RTL control in Lane 1 regression suite.
- not_a_killable_control: Equivalent mutant or specification question not establishing a killable bug.
"""

from __future__ import annotations

import json
import sys
from dataclasses import asdict, dataclass
from enum import Enum
from pathlib import Path
from typing import Any, Dict, List, Optional

REPO_ROOT = Path(__file__).resolve().parent.parent
if str(REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(REPO_ROOT))

from verification.p7_paths import P7Paths, get_default_paths


class ProposalClassification(str, Enum):
    """Exclusive triage outcome per Kalash intake review."""
    IMPLEMENTED = "implemented"
    ALREADY_COVERED = "already_covered"
    NOT_A_KILLABLE_CONTROL = "not_a_killable_control"


@dataclass
class RTLMutantProposal:
    """Specification of an actionable RTL mutation grounded in actual RTL sources."""
    id: str
    number: str
    target_file: str
    category: str
    intended_defect: str
    classification: ProposalClassification
    verdict_detail: str
    registered_evidence: str
    oracle_kill_signature: str
    oracle_independence_notes: str

    def to_dict(self) -> Dict[str, Any]:
        d = asdict(self)
        d["classification"] = self.classification.value
        return d


def build_all_rtl_mutant_proposals() -> List[RTLMutantProposal]:
    """Compiles the 15 grounded proposals mapped to real RTL sources and Kalash triage."""
    proposals: List[RTLMutantProposal] = [
        # 01
        RTLMutantProposal(
            id="RTL_MUT_01_ROUTING",
            number="01",
            target_file="NOC_XY_ROUTING.sv",
            category="Routing",
            intended_defect="Route Y-dimension before X-dimension on mesh hops.",
            classification=ProposalClassification.IMPLEMENTED,
            verdict_detail="Real gap identified by E4: survived every existing bench (hop-probes passed 414/414) because YX preserves hop count.",
            registered_evidence="dual_lane_10_20261106_163900_ff77f562 (job: i11_mut_yfirst)",
            oracle_kill_signature="Killed by 12 x SPEC_XY_* in tb_i11_noc_spec (every diagonal route fails literal spec assertion).",
            oracle_independence_notes="Oracle-independence fix: tb_i11_noc_spec checks literal M-F1 coordinate expectations, not derived hop counts.",
        ),
        # 02
        RTLMutantProposal(
            id="RTL_MUT_02_CREDIT",
            number="02",
            target_file="noc_credit_counter.sv",
            category="Credit Handling",
            intended_defect="Suppress credit return pulse when VC FIFO flit is popped.",
            classification=ProposalClassification.ALREADY_COVERED,
            verdict_detail="Already covered by Lane 1 credit loss mutant control.",
            registered_evidence="dual_lane_10_20261029_140104_d9fb229d (job: pfc_wp0_n6_mut_b_t5)",
            oracle_kill_signature="KILLED: Credit underflow / permanent stall detected by credit counter assertion.",
            oracle_independence_notes="Existing credit benches assert return balance independently.",
        ),
        # 03
        RTLMutantProposal(
            id="RTL_MUT_03_VC_ALLOC",
            number="03",
            target_file="NOC_PKG.sv",
            category="VC Allocation",
            intended_defect="Remap ATTESTATION message to VC 0 instead of VC 2 in message_to_vc().",
            classification=ProposalClassification.IMPLEMENTED,
            verdict_detail="Real gap identified by E4: survived because existing benches derived expected VC using the same package function under test.",
            registered_evidence="dual_lane_10_20261106_163900_ff77f562 (job: i11_mut_attest_vc0)",
            oracle_kill_signature="Killed by 4 x SPEC_VC_ATTEST_4..7 in tb_i11_noc_spec (literal M-F1 VC table comparison).",
            oracle_independence_notes="Oracle-independence fix: tb_i11_noc_spec uses literal M-F1 table constants rather than calling message_to_vc().",
        ),
        # 04
        RTLMutantProposal(
            id="RTL_MUT_04_FIFO_PROTECTION",
            number="04",
            target_file="NOC_FIFO.sv",
            category="FIFO Protection",
            intended_defect="Remove FIFO full check on push.",
            classification=ProposalClassification.NOT_A_KILLABLE_CONTROL,
            verdict_detail="Not a killable control: credit flow control never writes a full FIFO.",
            registered_evidence="N-7 / credit benches protocol invariant",
            oracle_kill_signature="N/A (credit flow control never writes a full FIFO).",
            oracle_independence_notes="Credit flow control ensures FIFO full condition is unreachable in normal operation.",
        ),
        # 05
        RTLMutantProposal(
            id="RTL_MUT_05_NI_TIMEOUT",
            number="05",
            target_file="noc_network_interface_p7_i9.sv",
            category="NI Timeout and Slot Release",
            intended_defect="NI slot timeout counter comparison disabled (never expires).",
            classification=ProposalClassification.ALREADY_COVERED,
            verdict_detail="Already covered by I-9 negative control.",
            registered_evidence="dual_lane_10_20261105_145813_9ca6a347 (job: i9_mut_no_timeout)",
            oracle_kill_signature="KILLED by tb_i9_integ: SLOT_RECOVER fails when slot is not autonomously freed after T_SLOT cycles.",
            oracle_independence_notes="Checks autonomous slot deallocation independently of response arrival.",
        ),
        # 06
        RTLMutantProposal(
            id="RTL_MUT_06_STALE_RESPONSE",
            number="06",
            target_file="noc_network_interface_p7_i9.sv",
            category="Late/Stale Response Handling",
            intended_defect="Deliver late/stale response arriving after slot timeout.",
            classification=ProposalClassification.ALREADY_COVERED,
            verdict_detail="Already covered by I-9 negative control.",
            registered_evidence="dual_lane_10_20261105_145813_9ca6a347 (job: i9_mut_stale_deliver)",
            oracle_kill_signature="KILLED by tb_i9_integ: I9_STALE_DROPPED fails if app_rx_head_valid pulses for expired tag.",
            oracle_independence_notes="Monitors app_rx interface for unauthorized pulses following slot retirement.",
        ),
        # 07
        RTLMutantProposal(
            id="RTL_MUT_07_AUTHENTICATION",
            number="07",
            target_file="noc_l2_auth_p7.sv",
            category="Authentication",
            intended_defect="L2 KMAC authentication tag comparison forced valid.",
            classification=ProposalClassification.ALREADY_COVERED,
            verdict_detail="Already covered by S2 and I-7 negative controls.",
            registered_evidence="dual_lane_10_20261029_140104_d9fb229d (jobs: s2_mut_mac_off, i7_mut_tag_off)",
            oracle_kill_signature="KILLED by s2_attacks and i7_mut_tag_off: corrupt tag accepted into secured core.",
            oracle_independence_notes="Exhaustive negative vector testbench injects invalid KMAC digests.",
        ),
        # 08
        RTLMutantProposal(
            id="RTL_MUT_08_REPLAY_PROTECTION",
            number="08",
            target_file="pq_rot_verifier.sv",
            category="Replay Protection",
            intended_defect="Verifier ignores epoch / sequence mismatch.",
            classification=ProposalClassification.ALREADY_COVERED,
            verdict_detail="Already covered by I-7 and S-2 controls. Verifier has no separate epoch compare; epoch is cryptographically bound into the expected tag.",
            registered_evidence="dual_lane_10_20261029_140104_d9fb229d (jobs: s2_mut_epoch_off, i7_mut_tag_off SEC_STALE_EPOCH, i7_mut_l2_epoch_off)",
            oracle_kill_signature="KILLED: SEC_STALE_EPOCH triggered by mismatch in reconstructed KMAC verification digest.",
            oracle_independence_notes="Epoch freshness is cryptographically embedded into message digest, not tested by an arithmetic comparator.",
        ),
        # 09
        RTLMutantProposal(
            id="RTL_MUT_09_AUTHORIZATION",
            number="09",
            target_file="noc_attest_gate.sv",
            category="Authorization",
            intended_defect="Attestation gate allows data packets while in reset or unauthorized state.",
            classification=ProposalClassification.ALREADY_COVERED,
            verdict_detail="Already covered by I-6 and P-7 gate controls.",
            registered_evidence="dual_lane_10_20261029_140104_d9fb229d (jobs: i6_mut_gate_bypass I6G_RESET_BLOCKED, p7_gate_mut_bypass)",
            oracle_kill_signature="KILLED: Gate violation flag raised on unauthorised flit egress.",
            oracle_independence_notes="Gate monitors data transit independently of control state.",
        ),
        # 10
        RTLMutantProposal(
            id="RTL_MUT_10_MEMORY_WINDOW",
            number="10",
            target_file="pq_noc_subsystem_p7_i9.sv",
            category="Memory Window",
            intended_defect="Allow Tile-2 BRAM accesses outside the 16KB window (OFF >= 0x4000).",
            classification=ProposalClassification.IMPLEMENTED,
            verdict_detail="Real gap identified by E4: previously only the window shrink direction was controlled. Implemented as new control in I-11.",
            registered_evidence="dual_lane_10_20261106_163900_ff77f562 (job: i11_mut_window_over)",
            oracle_kill_signature="KILLED by I9_WINDOW_OUT_ERR (out-of-window access correctly caught before reaching BRAM macro).",
            oracle_independence_notes="Front-end decodes address bits [31:14] and generates error response without forwarding to BRAM.",
        ),
        # 11
        RTLMutantProposal(
            id="RTL_MUT_11_BYTE_ENABLES",
            number="11",
            target_file="pq_noc_subsystem_p7_i9.sv",
            category="Byte Enables",
            intended_defect="Commit memory write when wstrb is all-zero (wstrb = 4'b0000).",
            classification=ProposalClassification.NOT_A_KILLABLE_CONTROL,
            verdict_detail="Not a killable control: all-zero wstrb is a specification question, not an established defect.",
            registered_evidence="dual_lane_10_20261105_145813_9ca6a347 (job: i9_mut_bram_lanes)",
            oracle_kill_signature="N/A (all-zero wstrb is a specification question, not an established defect; byte-lane mapping is separately killed by i9_mut_bram_lanes).",
            oracle_independence_notes="Byte lane mapping is tested by reading back partial-word stores.",
        ),
        # 12
        RTLMutantProposal(
            id="RTL_MUT_12_MEASUREMENT_LENGTH",
            number="12",
            target_file="pq_measurement_hasher.sv",
            category="Measurement Length",
            intended_defect="Accept attestation measurement message with length > 135 bytes.",
            classification=ProposalClassification.NOT_A_KILLABLE_CONTROL,
            verdict_detail="Not a killable control: length greater than 135 bytes is unreachable past K-3.",
            registered_evidence="dual_lane_10_20261029_140104_d9fb229d (job: s8_golden 95/0)",
            oracle_kill_signature="N/A (length greater than 135 bytes is unreachable past K-3).",
            oracle_independence_notes="Unit invalid-length vectors tested in standalone s8_golden bench.",
        ),
        # 13
        RTLMutantProposal(
            id="RTL_MUT_13_IMEM_64B",
            number="13",
            target_file="pq_attest_endpoint.sv",
            category="IMEM Bytes 16-63",
            intended_defect="Endpoint controller truncates IMEM measurement read length to 16 bytes instead of 64 bytes.",
            classification=ProposalClassification.ALREADY_COVERED,
            verdict_detail="Already covered by I-10 D2 negative control.",
            registered_evidence="dual_lane_10_20261106_004336_aacf4cd0 (job: i10_mut_window16)",
            oracle_kill_signature="KILLED by tb_i10_d2: digest mismatch when bytes 16..63 are excluded from Keccak sponge absorb.",
            oracle_independence_notes="D2 test vectors require exact 87-byte measurement message hash.",
        ),
        # 14
        RTLMutantProposal(
            id="RTL_MUT_14_TILE_IDENTITY",
            number="14",
            target_file="pq_rot_verifier.sv",
            category="Tile Identity",
            intended_defect="Truncate or ignore tile ID comparison during attestation verification.",
            classification=ProposalClassification.ALREADY_COVERED,
            verdict_detail="Already covered by I-7 and S-2 controls. Verifier has no separate tile ID compare: tile ID is bound directly into KDF personalization string and KMAC tag.",
            registered_evidence="dual_lane_10_20261029_140104_d9fb229d (jobs: s2_mut_id_off, i7_mut_tag_off SEC_WRONG_IDENTITY)",
            oracle_kill_signature="KILLED: SEC_WRONG_IDENTITY asserted on tile ID alteration.",
            oracle_independence_notes="Cryptographic identity binding prevents identity substitution without valid key and digest.",
        ),
        # 15
        RTLMutantProposal(
            id="RTL_MUT_15_NONCE_HANDLING",
            number="15",
            target_file="pq_rot_verifier.sv",
            category="Nonce Handling",
            intended_defect="Verifier accepts repeated nonce from previous challenge (nonce reuse).",
            classification=ProposalClassification.ALREADY_COVERED,
            verdict_detail="Already covered by I-7 control. Nonce issuer is deterministic demo logic (no TRNG claim).",
            registered_evidence="dual_lane_10_20261029_140104_d9fb229d (job: i7_mut_nonce_stale)",
            oracle_kill_signature="KILLED: Stale nonce error asserted when previously presented nonce is reused.",
            oracle_independence_notes="Verifier tracks issued challenge nonces and rejects duplicates.",
        ),
    ]
    return proposals


def generate_rtl_mutant_manifest(output_path: Optional[Path] = None) -> Dict[str, Any]:
    """Generates the single-source-of-truth JSON manifest."""
    paths = get_default_paths()
    out_p = Path(output_path) if output_path else paths.generated_dir / "p7_rtl_mutant_proposals.json"
    out_p.parent.mkdir(parents=True, exist_ok=True)

    proposals = build_all_rtl_mutant_proposals()

    triage_counts = {
        "implemented": sum(1 for p in proposals if p.classification == ProposalClassification.IMPLEMENTED),
        "already_covered": sum(1 for p in proposals if p.classification == ProposalClassification.ALREADY_COVERED),
        "not_a_killable_control": sum(1 for p in proposals if p.classification == ProposalClassification.NOT_A_KILLABLE_CONTROL),
    }

    manifest_data = {
        "metadata": {
            "title": "PQ-Attest P7 Grounded RTL Mutant Proposals and Triage",
            "version": "2.0",
            "date": "2026-11-06",
            "author": "PQ-Attest Engineer 4",
            "reviewer": "Kalash Bheda (Lane 1)",
            "source_of_truth": "verification/generated/p7_rtl_mutant_proposals.json",
            "total_proposals": len(proposals),
            "triage_summary": triage_counts,
            "registered_runs_referenced": [
                "dual_lane_10_20261029_140104_d9fb229d (I-5 baseline)",
                "dual_lane_10_20261105_145813_9ca6a347 (I-9 integration)",
                "dual_lane_10_20261106_004336_aacf4cd0 (I-10 D2 measurement)",
                "dual_lane_10_20261106_163900_ff77f562 (I-11 spec-literal controls)",
            ],
            "disclaimer": "These RTL proposals are candidate faults grounded in actual RTL source files and Lane 1 registered evidence. They are distinguished from Python behavioral reference model mutants.",
        },
        "proposals": [p.to_dict() for p in proposals],
    }

    with open(out_p, "w", encoding="utf-8") as f:
        json.dump(manifest_data, f, indent=2)

    return manifest_data


def generate_rtl_mutant_markdown(json_path: Path, md_path: Path) -> str:
    """Generates the Markdown report strictly from the JSON manifest."""
    with open(json_path, "r", encoding="utf-8") as f:
        data = json.load(f)

    meta = data["metadata"]
    proposals = data["proposals"]
    summary = meta["triage_summary"]

    lines = [
        "# PQ-Attest Engineer 4 — Step 18: Grounded RTL Mutant Proposals & Evidence Reconciliation",
        "",
        f"**Date:** {meta['date']}  ",
        f"**Author:** {meta['author']}  ",
        f"**Reviewer:** {meta['reviewer']}  ",
        f"**Status:** COMPLETE (Reconciled with Lane 1 I-11 Registered Run)  ",
        f"**Single Source of Truth:** [`{meta['source_of_truth']}`](file:///c:/Users/Arnav%20Bhandari/PQ_Attest/{meta['source_of_truth']})  ",
        "",
        "---",
        "",
        "## 1. Executive Summary & Triage Overview",
        "",
        "During the November 6 final intake review, Kalash Bheda triaged all 15 Engineer 4 RTL mutant proposals against the 49 existing killed RTL controls in Lane 1 and registered testbenches. The 15 proposals map to real RTL locations and fall into three exclusive triage categories:",
        "",
        f"- **Implemented in RTL by Lane 1 (I-11):** **{summary['implemented']}** proposals (`01`, `03`, `10`). These exposed real verification oracle gaps and were registered as live RTL negative controls in run `dual_lane_10_20261106_163900_ff77f562`.",
        f"- **Already Covered by Existing Killed Controls:** **{summary['already_covered']}** proposals (`02`, `05`, `06`, `07`, `08`, `09`, `13`, `14`, `15`). These correspond directly to existing negative controls in S2, I-6, I-7, I-9, and I-10.",
        f"- **Not a Killable Control:** **{summary['not_a_killable_control']}** proposals (`04`, `11`, `12`). These represent protocol-guaranteed invariants, benign specification questions, or architecturally unreachable bounds.",
        "",
        "```",
        f"Total Proposals: {meta['total_proposals']}",
        f"  ├── Implemented by Lane 1 (I-11): {summary['implemented']} (100% killed in registered run)",
        f"  ├── Already Covered:              {summary['already_covered']} (100% killed in baseline runs)",
        f"  └── Not a Killable Control:        {summary['not_a_killable_control']} (invariants / unreachable)",
        "```",
        "",
        "---",
        "",
        "## 2. Oracle-Independence Findings from I-11",
        "",
        "A critical verification insight emerged from proposals `01` and `03` during the I-11 intake:",
        "",
        "1. **Routing Inversion (`01_ROUTING`, `NOC_XY_ROUTING.sv`):**",
        "   - Mutating XY routing to YX routing previously survived all 414 checks of `tb_noc_hop_probes_p7` because the bench checked hop *counts*, which remain invariant under dimension order reversal.",
        "   - In response, Kalash implemented `tb_i11_noc_spec.sv` with literal coordinate trajectory assertions (`SPEC_XY_*`), killing `i11_mut_yfirst` across all 12 diagonal routing paths.",
        "2. **Attestation VC Inversion (`03_VC_ALLOC`, `NOC_PKG.sv`):**",
        "   - Mapping attestation messages to VC 0 instead of VC 2 previously survived because existing testbenches computed the expected VC dynamically using `message_to_vc()`—the very package function under mutation.",
        "   - Kalash resolved this with literal expected VC constants (`SPEC_VC_ATTEST_4..7`) from M-F1, killing `i11_mut_attest_vc0`.",
        "3. **BRAM Window Overshoot (`10_MEMORY_WINDOW`, `pq_noc_subsystem_p7_i9.sv`):**",
        "   - Previously, only the window shrink direction was controlled. Proposal 10 prompted the addition of `i11_mut_window_over`, killed by `I9_WINDOW_OUT_ERR` when an address with `OFF >= 0x4000` is rejected before reaching the BRAM macro.",
        "",
        "---",
        "",
        "## 3. Grounded RTL Mutant Proposals & Triage Table",
        "",
        "| # | ID | Target RTL File | Category | Triage Outcome | Registered Run / Evidence | Oracle Kill Signature |",
        "|---|---|---|---|---|---|---|",
    ]

    for p in proposals:
        lines.append(
            f"| {p['number']} | `{p['id']}` | `{p['target_file']}` | {p['category']} | **`{p['classification']}`** | {p['registered_evidence']} | {p['oracle_kill_signature']} |"
        )

    lines.extend([
        "",
        "---",
        "",
        "## 4. Detailed Proposal Specifications",
        "",
    ])

    for p in proposals:
        lines.extend([
            f"### Proposal {p['number']}: `{p['id']}`",
            f"- **Target File:** `{p['target_file']}`",
            f"- **Category:** {p['category']}",
            f"- **Intended Defect:** {p['intended_defect']}",
            f"- **Triage Classification:** `{p['classification']}`",
            f"- **Review Detail:** {p['verdict_detail']}",
            f"- **Registered Evidence:** {p['registered_evidence']}",
            f"- **Kill Signature:** {p['oracle_kill_signature']}",
            f"- **Oracle Independence:** {p['oracle_independence_notes']}",
            "",
        ])

    lines.extend([
        "---",
        "",
        "## 5. Architectural Integrity Disclaimers",
        "",
        "- `HARDWARE_VALIDATED=NO`",
        "- `SOC_INTEGRATION_COMPLETE=NO`",
        "- `FORMAL_PROOF=NO`",
        "- `RTL_MODIFICATIONS=0` (Engineer 4 made zero edits to RTL)",
        "- `PYTHON_MUTANTS_ARE_RTL_MUTANTS=NO` (Python mutants are reference model tests; RTL controls were executed and registered by Lane 1)",
    ])

    md_content = "\n".join(lines) + "\n"
    md_path.parent.mkdir(parents=True, exist_ok=True)
    with open(md_path, "w", encoding="utf-8") as f:
        f.write(md_content)

    return md_content


if __name__ == "__main__":
    paths = get_default_paths()
    json_manifest = generate_rtl_mutant_manifest()
    md_path = paths.reports_dir / "E4_P7_STEP18_RTL_MUTANT_PROPOSALS.md"
    generate_rtl_mutant_markdown(paths.generated_dir / "p7_rtl_mutant_proposals.json", md_path)
    print("Generated p7_rtl_mutant_proposals.json and E4_P7_STEP18_RTL_MUTANT_PROPOSALS.md successfully.")
