"""
PQ-Attest P7 Verification Regression Runner Tests
=================================================
Validates the one-command regression automation framework:
- Mode selection (default, quick, full, validate-only)
- Invariant checking and validation
- Artifact integrity validation
- Historical integrity guardian & tampering detection
- Summary JSON generation and boundary disclosures
"""

import json
import os
import shutil
import sys
import tempfile
from pathlib import Path

# Ensure repo root is on sys.path
REPO_ROOT = Path(__file__).resolve().parent.parent.parent
if str(REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(REPO_ROOT))

import pytest

from verification.p7_regression import (
    REPO_ROOT,
    RunnerMode,
    StageStatus,
    IntegrityGuardian,
    P7RegressionRunner,
    verify_frozen_architecture_invariants,
    validate_all_generated_artifacts,
)


class TestP7RegressionFramework:
    """Test suite for the P7 one-command verification runner."""

    def test_environment_discovery(self):
        runner = P7RegressionRunner(mode=RunnerMode.VALIDATE_ONLY)
        env = runner.discover_environment()
        assert "git_head" in env
        assert "python_version" in env
        assert "platform" in env
        assert len(env["git_head"]) > 0

    def test_frozen_architecture_invariants_pass(self):
        manifest_path = REPO_ROOT / "verification" / "generated" / "p7_protocol_manifest.json"
        assert manifest_path.exists(), "Protocol manifest must exist"
        with open(manifest_path, "r", encoding="utf-8") as f:
            manifest = json.load(f)

        passed, failures = verify_frozen_architecture_invariants(manifest)
        assert passed is True, f"Invariant verification failed: {failures}"
        assert len(failures) == 0

    def test_frozen_architecture_invariants_detects_tamper(self):
        corrupted_manifest = {
            "protocol_constants": {
                "MESH_X": {"value": 4},  # Corrupted: expected 3
                "MESH_Y": {"value": 2},
                "NUM_TILES": {"value": 8},
                "FLIT_WIDTH": {"value": 32},
                "NUM_VC": {"value": 3},
            },
            "messages": {}
        }
        passed, failures = verify_frozen_architecture_invariants(corrupted_manifest)
        assert passed is False
        assert any("MESH_X" in f for f in failures)
        assert any("NUM_TILES" in f for f in failures)

    def test_artifact_validation_all_generated(self):
        gen_dir = REPO_ROOT / "verification" / "generated"
        valid, errors = validate_all_generated_artifacts(gen_dir)
        assert valid is True, f"Artifact validation failed with errors: {errors}"
        assert len(errors) == 0

    def test_artifact_validation_missing_file_detection(self):
        with tempfile.TemporaryDirectory() as tmp_dir:
            tmp_path = Path(tmp_dir)
            valid, errors = validate_all_generated_artifacts(tmp_path)
            assert valid is False
            assert len(errors) > 0
            assert any("Missing required generated artifact" in e for e in errors)

    def test_artifact_validation_corrupt_json_detection(self):
        with tempfile.TemporaryDirectory() as tmp_dir:
            tmp_path = Path(tmp_dir)
            # Create a corrupted json file
            bad_json = tmp_path / "p7_protocol_manifest.json"
            bad_json.write_text("{bad_json: True", encoding="utf-8")
            valid, errors = validate_all_generated_artifacts(tmp_path)
            assert valid is False
            assert any("JSON syntax error" in e for e in errors)

    def test_integrity_guardian_baseline_and_verify(self):
        guardian = IntegrityGuardian(REPO_ROOT)
        snapshot = guardian.take_snapshot()
        assert len(snapshot) > 0
        # Verify RTL files are tracked
        tracked_paths = list(snapshot.keys())
        assert any("NOC_PKG.sv" in p for p in tracked_paths)
        assert any("noc_l2_auth_p7.sv" in p for p in tracked_paths)

        # Baseline verify should be clean
        ok, violations = guardian.verify_snapshot()
        assert ok is True
        assert len(violations) == 0

    def test_integrity_guardian_detects_modification(self):
        guardian = IntegrityGuardian(REPO_ROOT)
        guardian.take_snapshot()
        # Pretend a tracked file hash changed in baseline
        sample_key = next(iter(guardian.baseline_hashes.keys()))
        orig_hash = guardian.baseline_hashes[sample_key]
        guardian.baseline_hashes[sample_key] = "0" * 64

        ok, violations = guardian.verify_snapshot()
        assert ok is False
        assert any(sample_key in v for v in violations)

        # Restore
        guardian.baseline_hashes[sample_key] = orig_hash

    def test_runner_validate_only_mode(self):
        runner = P7RegressionRunner(mode=RunnerMode.VALIDATE_ONLY)
        exit_code = runner.run()
        summary = runner.summary_data
        assert exit_code == 0
        assert summary["metadata"]["overall_status"] == "PASS"

        # Check that heavy stages were skipped
        stage_map = {s["stage_id"]: s["status"] for s in summary["stages"]}
        assert stage_map["03_PROTOCOL_EXTRACTION"] == "SKIPPED"
        assert stage_map["05_PACKET_MODEL_REGRESSION"] == "SKIPPED"
        assert stage_map["11_MUTATION_ANALYSIS"] == "SKIPPED"
        assert stage_map["12_FULL_PYTEST"] == "SKIPPED"

        # Check required validation stages passed
        assert stage_map["01_ENV_DISCOVERY"] == "PASS"
        assert stage_map["02_BASELINE_SNAPSHOT"] == "PASS"
        assert stage_map["04_PROTOCOL_VALIDATION"] == "PASS"
        assert stage_map["13_ARTIFACT_VALIDATION"] == "PASS"
        assert stage_map["14_HISTORICAL_INTEGRITY"] == "PASS"
        assert stage_map["15_FINAL_SUMMARY"] == "PASS"

    def test_runner_quick_mode(self):
        runner = P7RegressionRunner(mode=RunnerMode.QUICK)
        exit_code = runner.run()
        summary = runner.summary_data
        assert exit_code == 0
        assert summary["metadata"]["overall_status"] == "PASS"

        stage_map = {s["stage_id"]: s["status"] for s in summary["stages"]}
        # In quick mode: unit tests run, but coverage audit, mutation, and full pytest skipped
        assert stage_map["05_PACKET_MODEL_REGRESSION"] == "PASS"
        assert stage_map["06_SECURITY_MODEL_REGRESSION"] == "PASS"
        assert stage_map["08_RELEASE_EVIDENCE_RECONCILE"] == "PASS"
        assert stage_map["09_INTEGRATION_SCENARIOS"] == "PASS"
        assert stage_map["10_COVERAGE_AUDIT"] == "SKIPPED"
        assert stage_map["11_MUTATION_ANALYSIS"] == "SKIPPED"
        assert stage_map["12_FULL_PYTEST"] == "SKIPPED"

    def test_summary_disclosures_present(self):
        summary_path = REPO_ROOT / "verification" / "generated" / "p7_regression_summary.json"
        assert summary_path.exists()
        with open(summary_path, "r", encoding="utf-8") as f:
            summary = json.load(f)

        disclosures = summary.get("boundary_disclosures", {})
        assert disclosures.get("HARDWARE_VALIDATED") is False
        assert disclosures.get("FORMAL_PROOF") is False
        assert disclosures.get("SOC_INTEGRATION_COMPLETE") is False
        assert "NOT equivalent to hardware execution" in disclosures.get("disclaimer", "")
