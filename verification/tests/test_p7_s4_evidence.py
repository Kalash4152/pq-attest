"""
verification/tests/test_p7_s4_evidence.py
=========================================
PQ-Attest P7 Verification - S4 Baseline Reconciliation Tests.

Tests:
1. S4 source manifest completeness (111 unique sources, exact counts per type).
2. Live SHA-256 and byte-size verification against 02_sources/.
3. A5 KMAC provenance and variant verification (kmac_128_a5, kmac_128_xp_a5).
4. S4 job accounting (66 active S4 jobs, 62 PASS_FRESH, 4 NOT_RUN, 368 out-of-scope BLOCKED).
5. Overall registered S4 run status is strictly BLOCKED (package acceptance PENDING).
6. Four registered implementation runs accounting.
7. Verification boundary disclosures (HARDWARE_VALIDATED = NO, FORMAL_PROOF = NO, SOC_INTEGRATION_COMPLETE = NO).
"""

import json
import sys
from pathlib import Path
import pytest

REPO_ROOT = Path(__file__).resolve().parent.parent.parent
if str(REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(REPO_ROOT))

from verification.p7_s4_evidence import (
    S4EvidenceParser,
    S4SourceType,
    classify_source_path,
    generate_s4_manifest_and_summary,
)


@pytest.fixture
def parser():
    return S4EvidenceParser()


class TestP7S4EvidenceReconciliation:
    """Test suite for S4 release evidence reconciliation."""

    def test_classify_source_path(self):
        assert classify_source_path("rtl/dual_lane/NOC_PKG.sv") == S4SourceType.RTL
        assert classify_source_path("NOC_PQATTEST.srcs/sim_1/new/tb_i7_sec.sv") == S4SourceType.TESTBENCH
        assert classify_source_path("vectors/i7_sec.svh") == S4SourceType.HEADER
        assert classify_source_path("scripts/check_s4.py") == S4SourceType.PYTHON
        assert classify_source_path("rtl/dual_lane/s4_provenance.json") == S4SourceType.JSON_META
        assert classify_source_path("sim/dual_lane/s2/s2_keys.mem") == S4SourceType.VECTOR_DATA

    def test_s4_source_manifest_completeness(self, parser):
        all_valid, entries, summary = parser.validate_sources_manifest()
        assert all_valid is True, "All 111 S4 sources must be verified"
        assert len(entries) == 111
        assert summary["total_unique_sources"] == 111
        assert summary["verified_count"] == 111
        assert summary["mismatch_count"] == 0

        # Exact distribution check
        td = summary["type_distribution"]
        assert td.get(S4SourceType.RTL.value) == 62
        assert td.get(S4SourceType.TESTBENCH.value) == 21
        assert td.get(S4SourceType.PYTHON.value) == 18
        assert td.get(S4SourceType.JSON_META.value) == 5
        assert td.get(S4SourceType.HEADER.value) == 3
        assert td.get(S4SourceType.VECTOR_DATA.value) == 2

    def test_kmac_a5_provenance_validation(self, parser):
        passed, prov_summary = parser.validate_kmac_a5_provenance()
        assert passed is True, "A5 KMAC provenance check must pass"
        assert prov_summary["all_verified"] is True
        assert prov_summary["contract"] == "docs/decisions/S4_AREA_CONTRACT.md"

        variants = prov_summary["variants"]
        assert len(variants) == 2

        # Check kmac_128_a5.sv
        a5 = variants.get("rtl/dual_lane/kmac_128_a5.sv")
        assert a5 is not None
        assert a5["source"] == "NOC_PQATTEST.srcs/sources_1/new/kmac_128.sv"
        assert a5["source_matches"] is True
        assert a5["output_matches"] is True
        assert a5["valid"] is True
        assert a5["expected_src_sha256"] == "796164790af7073a6260b561e9ac943a3291cfa278e5d3d6a8709fd2dafe0a72"
        assert a5["expected_out_sha256"] == "4b5c867d5cffc5ca2811ef785b0bb381f5b5a1be401ae3d85c1fc3f6671685bb"

        # Check kmac_128_xp_a5.sv
        xp_a5 = variants.get("rtl/dual_lane/kmac_128_xp_a5.sv")
        assert xp_a5 is not None
        assert xp_a5["source"] == "NOC_PQATTEST.srcs/sources_1/new/kmac_128.sv"
        assert xp_a5["source_matches"] is True
        assert xp_a5["output_matches"] is True
        assert xp_a5["valid"] is True
        assert xp_a5["expected_src_sha256"] == "796164790af7073a6260b561e9ac943a3291cfa278e5d3d6a8709fd2dafe0a72"
        assert xp_a5["expected_out_sha256"] == "e0302fd5503dc5ddd322432731016e8a7d3d335d9f829bfbf51ab34461017b04"

    def test_s4_job_accounting_and_blocked_status(self, parser):
        consistent, summary = parser.reconcile_s4_jobs()
        assert consistent is True, "S4 job accounting must be fully consistent"

        assert summary["total_registered_jobs"] == 434
        assert summary["s4_active_job_count"] == 66
        assert summary["s4_pass_fresh_count"] == 62
        assert summary["s4_not_run_count"] == 4
        assert summary["out_of_scope_blocked_count"] == 368

        # Crucial check: overall status is strictly BLOCKED, not PASS
        assert summary["registered_run_overall_status"] == "BLOCKED"
        assert summary["increment_status"] == "NOT_RUN"
        assert summary["package_acceptance"] == "PENDING"
        assert summary["python_rtl_compatibility"] == "PENDING"

        # Specific 4 NOT_RUN jobs
        expected_not_run = {"s4r_p7_pnr", "s4r_soc_pnr", "s4r_n13_secure", "s4r_n13_insecure"}
        assert set(summary["s4_not_run_jobs"]) == expected_not_run

    def test_registered_implementation_runs(self, parser):
        consistent, summary = parser.reconcile_s4_jobs()
        impl_runs = summary.get("registered_implementation_runs", {})
        assert len(impl_runs) == 4

        # Verify each job ran alone in its own registered run directory
        expected_impl_jobs = {
            "s4r_p7_pnr",
            "s4r_soc_pnr",
            "s4r_n13_secure",
            "s4r_n13_insecure",
        }
        found_jobs = set()
        for run_info in impl_runs.values():
            found_jobs.update(run_info["pass_fresh_jobs"])
        assert found_jobs == expected_impl_jobs

    def test_generated_manifest_and_summary_files(self):
        m_path, s_path = generate_s4_manifest_and_summary()
        assert m_path.exists()
        assert s_path.exists()

        with open(m_path, "r", encoding="utf-8") as f:
            m_data = json.load(f)
        assert m_data["metadata"]["total_unique_sources"] == 111
        assert m_data["metadata"]["status"] == "PASS"

        with open(s_path, "r", encoding="utf-8") as f:
            s_data = json.load(f)
        assert s_data["job_accounting"]["s4_active_jobs_total"] == 66
        assert s_data["job_accounting"]["s4_pass_fresh_count"] == 62
        assert s_data["job_accounting"]["s4_not_run_count"] == 4
        assert s_data["job_accounting"]["out_of_scope_blocked_count"] == 368
        assert s_data["metadata"]["registered_run_overall_status"] == "BLOCKED"

    def test_boundary_disclosures(self, parser):
        consistent, summary = parser.reconcile_s4_jobs()
        disclosures = summary.get("boundary_disclosures", {})
        assert disclosures.get("HARDWARE_VALIDATED") is False
        assert disclosures.get("FORMAL_PROOF") is False
        assert disclosures.get("SOC_INTEGRATION_COMPLETE") is False

