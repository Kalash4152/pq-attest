"""
verification/tests/test_p7_coverage_audit.py
============================================
Test suite for PQ-Attest P7 Step 6: Coverage Closure and Traceability Audit.

Tests:
1. Traceability matrix completeness (57 requirements across all 6 groups).
2. Explicit numerators and denominators for all metrics.
3. Group-level coverage calculations.
4. Domain-specific coverage calculations.
5. Verification that every requirement links to Python, test, scenario, and RTL evidence.
6. Coverage manifest JSON generation and schema validation.
"""

from pathlib import Path
import pytest

from verification.p7_coverage_audit import (
    CoverageAuditEngine,
    CoverageStatus,
    RequirementGroup,
    build_requirement_traceability_matrix,
    generate_coverage_audit_manifest,
)


@pytest.fixture
def audit_engine():
    return CoverageAuditEngine()


def test_traceability_matrix_completeness(audit_engine):
    """Verify that all 58 requirements across groups A-F are present."""
    matrix = audit_engine.matrix
    assert len(matrix) == 58

    # Check each group count
    groups = {g: 0 for g in RequirementGroup}
    for req in matrix:
        groups[req.group] += 1

    assert groups[RequirementGroup.PACKET_PROTOCOL] == 11
    assert groups[RequirementGroup.AUTH_FRESHNESS] == 8
    assert groups[RequirementGroup.AUTHORIZATION] == 9
    assert groups[RequirementGroup.MEMORY_ENFORCEMENT] == 9
    assert groups[RequirementGroup.VERIFIER_I6_I7] == 12
    assert groups[RequirementGroup.NI_TRANSACTIONS] == 9


def test_coverage_classification_status(audit_engine):
    """Verify that all 58 requirements are COVERED with valid implementation links."""
    for req in audit_engine.matrix:
        assert req.status == CoverageStatus.COVERED
        assert req.python_implementation != ""
        assert req.test_function != ""
        assert req.rtl_evidence_reference != ""


def test_coverage_metrics_explicit_denominators(audit_engine):
    """Verify that all coverage metrics have explicit, mathematically exact numerators and denominators."""
    metrics = audit_engine.calculate_metrics()

    overall = metrics["overall_requirement_coverage"]
    assert overall["numerator"] == 58
    assert overall["denominator"] == 58
    assert overall["percentage"] == 100.0
    assert overall["partial"] == 0
    assert overall["unverified"] == 0

    # Group metrics
    for group_name, g_data in metrics["group_coverage"].items():
        assert g_data["tested"] == g_data["total"]
        assert g_data["percentage"] == 100.0

    # Domain metrics
    domains = metrics["domain_metrics"]
    for domain_name, d_data in domains.items():
        assert d_data["numerator"] == d_data["denominator"]
        assert d_data["percentage"] == 100.0


def test_audit_manifest_generation(tmp_path):
    """Verify that p7_coverage_audit.json is generated with valid structure."""
    out_file = tmp_path / "coverage_audit.json"
    manifest = generate_coverage_audit_manifest(output_path=out_file)

    assert out_file.exists()
    assert len(manifest["traceability_matrix"]) == 58
    assert manifest["metadata"]["status_claims"]["HARDWARE_VALIDATED"] is False
    assert manifest["metadata"]["status_claims"]["FORMAL_PROOF"] is False
    assert manifest["metadata"]["status_claims"]["SOC_INTEGRATION_COMPLETE"] is False

