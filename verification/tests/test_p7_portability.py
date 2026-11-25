#!/usr/bin/env python3
"""
Portability tests for PQ-Attest Engineer 4 verification infrastructure.
Validates path resolution, CLI overrides, environment variable precedence,
out-of-source directory builds, Stage 12 scoping, and machine-independence.
"""

from __future__ import annotations

import os
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path
from typing import Generator

import pytest

from verification.p7_paths import (
    MissingInputError,
    P7Paths,
    PathConfigError,
    discover_repo_root,
    get_default_paths,
    injected_environ,
    resolve_paths,
    validate_repo_root,
)
from verification import p7_regression


@pytest.fixture
def clean_env() -> Generator[None, None, None]:
    """Temporarily clears any P7_* environment variables."""
    old_env = {k: os.environ.get(k) for k in ("P7_REPO_ROOT", "P7_DATA_DIR", "P7_OUT_DIR")}
    for k in ("P7_REPO_ROOT", "P7_DATA_DIR", "P7_OUT_DIR"):
        os.environ.pop(k, None)
    try:
        yield
    finally:
        for k, v in old_env.items():
            if v is not None:
                os.environ[k] = v
            else:
                os.environ.pop(k, None)


def test_default_discovery_from_repo_root(clean_env: None) -> None:
    """Verifies default path discovery when invoked from the repository root."""
    actual_repo_root = discover_repo_root()
    assert validate_repo_root(actual_repo_root) == actual_repo_root
    paths = get_default_paths()
    assert paths.repo_root == actual_repo_root
    assert paths.data_dir == actual_repo_root
    assert paths.out_dir == actual_repo_root / "verification" / "generated"
    assert paths.generated_dir == actual_repo_root / "verification" / "generated"
    assert paths.rtl_dir == actual_repo_root / "rtl" / "dual_lane"


def test_default_discovery_from_external_cwd(clean_env: None) -> None:
    """Invokes path resolution from a temporary working directory and verifies it finds repo root."""
    actual_repo_root = discover_repo_root()
    with tempfile.TemporaryDirectory() as external_dir:
        original_cwd = os.getcwd()
        try:
            os.chdir(external_dir)
            resolved = resolve_paths()
            assert resolved.repo_root == actual_repo_root
            assert resolved.repo_root != Path(external_dir)
            assert resolved.data_dir == actual_repo_root
        finally:
            os.chdir(original_cwd)


def test_explicit_repo_root_override(clean_env: None) -> None:
    """Verifies --repo-root and P7_REPO_ROOT override default discovery."""
    with tempfile.TemporaryDirectory() as mock_root:
        mock_path = Path(mock_root).resolve()
        (mock_path / "verification").mkdir(parents=True)
        (mock_path / "verification" / "p7_regression.py").write_text("# mock", encoding="utf-8")

        # CLI override
        paths = resolve_paths(repo_root=mock_path)
        assert paths.repo_root == mock_path

        # Env override
        os.environ["P7_REPO_ROOT"] = str(mock_path)
        paths_env = resolve_paths()
        assert paths_env.repo_root == mock_path


def test_explicit_data_dir_override(clean_env: None) -> None:
    """Verifies --data-dir and P7_DATA_DIR override evidence and report resolution."""
    actual_repo_root = discover_repo_root()
    with tempfile.TemporaryDirectory() as mock_data:
        mock_data_path = Path(mock_data).resolve()
        # CLI override
        paths = resolve_paths(data_dir=mock_data_path)
        assert paths.repo_root == actual_repo_root
        assert paths.data_dir == mock_data_path
        assert paths.xsim_evidence_dir == mock_data_path / "E4_P7_XSIM_20261103"
        assert paths.reports_dir == mock_data_path / "reports"

        # Env override
        os.environ["P7_DATA_DIR"] = str(mock_data_path)
        paths_env = resolve_paths()
        assert paths_env.data_dir == mock_data_path
        assert paths_env.reports_dir == mock_data_path / "reports"


def test_explicit_out_dir_override(clean_env: None) -> None:
    """Verifies --out and P7_OUT_DIR point generated artifacts to designated directory."""
    actual_repo_root = discover_repo_root()
    with tempfile.TemporaryDirectory() as mock_out:
        mock_out_path = Path(mock_out).resolve()
        # CLI override
        paths = resolve_paths(out_dir=mock_out_path)
        assert paths.out_dir == mock_out_path
        assert paths.generated_dir == mock_out_path

        # Env override
        os.environ["P7_OUT_DIR"] = str(mock_out_path)
        paths_env = resolve_paths()
        assert paths_env.out_dir == mock_out_path
        assert paths_env.generated_dir == mock_out_path


def test_relative_path_resolution(clean_env: None) -> None:
    """Verifies relative path arguments are resolved against cwd without losing semantics."""
    actual_repo_root = discover_repo_root()
    with tempfile.TemporaryDirectory() as temp_work:
        temp_work_path = Path(temp_work).resolve()
        sub_out = temp_work_path / "rel_out"
        sub_out.mkdir()
        original_cwd = os.getcwd()
        try:
            os.chdir(temp_work_path)
            paths = resolve_paths(out_dir=Path("rel_out"))
            assert paths.out_dir == sub_out
        finally:
            os.chdir(original_cwd)


def test_absolute_path_resolution(clean_env: None) -> None:
    """Verifies absolute path arguments work directly on any directory."""
    with tempfile.TemporaryDirectory() as temp_dir:
        abs_p = Path(temp_dir).resolve()
        (abs_p / "verification").mkdir(parents=True)
        (abs_p / "verification" / "p7_regression.py").write_text("# mock", encoding="utf-8")
        paths = resolve_paths(repo_root=abs_p, data_dir=abs_p, out_dir=abs_p)
        assert paths.repo_root == abs_p
        assert paths.data_dir == abs_p
        assert paths.out_dir == abs_p


def test_missing_inputs_produce_clear_error(clean_env: None) -> None:
    """Verifies runner reports clear error if required input directory does not exist."""
    non_existent = Path("non_existent_directory_xyz_12345").resolve()
    with pytest.raises(PathConfigError) as exc_info:
        resolve_paths(data_dir=non_existent)
    assert "Data directory does not exist" in str(exc_info.value)


def test_generated_files_written_only_to_out(clean_env: None) -> None:
    """Verifies that running with --out writes generated artifacts under --out directory."""
    actual_repo_root = discover_repo_root()
    with tempfile.TemporaryDirectory() as temp_out:
        temp_out_path = Path(temp_out).resolve()
        paths = resolve_paths(repo_root=actual_repo_root, data_dir=actual_repo_root, out_dir=temp_out_path)
        manifest_out = paths.generated_dir / "p7_test_artifact.json"
        paths.generated_dir.mkdir(parents=True, exist_ok=True)
        assert paths.generated_dir.exists()
        manifest_out.write_text('{"test": true}', encoding="utf-8")
        assert manifest_out.exists()
        assert not (actual_repo_root / "verification" / "generated" / "p7_test_artifact.json").exists()


def test_historical_inputs_not_modified() -> None:
    """Verifies historical protected baseline paths exist and are accessible."""
    paths = get_default_paths()
    assert (paths.reports_dir / "E4_P7_STEP1_REPORT.md").exists()
    assert (paths.reports_dir / "E4_P7_STEP8_FINAL_HANDOFF.md").exists()
    assert (paths.rtl_dir / "NOC_PKG.sv").exists()
    assert (paths.rtl_dir / "noc_p7_pkg.sv").exists()
    assert (paths.rtl_dir / "noc_l2_auth_p7.sv").exists()


def test_regression_runner_does_not_execute_pytest_dot() -> None:
    """Inspects verification/p7_regression.py to ensure it does not invoke pytest ."""
    assert p7_regression.FULL_PYTEST_TARGET == "verification"
    assert p7_regression.FULL_PYTEST_TARGET != "."


def test_stage12_scoping() -> None:
    """Verifies Stage 12 explicitly invokes scoped target 'verification'."""
    assert p7_regression.FULL_PYTEST_TARGET == "verification"
    runner_py = discover_repo_root() / "verification" / "p7_regression.py"
    code = runner_py.read_text(encoding="utf-8")
    assert "FULL_PYTEST_TARGET = \"verification\"" in code


def test_no_machine_specific_paths_required() -> None:
    """Verifies that P7Paths code does not contain hardcoded user or machine paths."""
    paths_py = discover_repo_root() / "verification" / "p7_paths.py"
    code = paths_py.read_text(encoding="utf-8")
    assert "Arnav Bhandari" not in code
    assert "c:/Users" not in code.lower()


def test_isolated_checkout_simulation() -> None:
    """Creates a minimal isolated mock checkout in TemporaryDirectory and validates resolution."""
    with tempfile.TemporaryDirectory() as mock_checkout:
        mock_root = Path(mock_checkout).resolve()
        (mock_root / "verification").mkdir(parents=True)
        (mock_root / "verification" / "p7_regression.py").write_text("# mock runner", encoding="utf-8")
        (mock_root / "rtl" / "dual_lane").mkdir(parents=True)
        (mock_root / "rtl" / "dual_lane" / "NOC_PKG.sv").write_text("// mock", encoding="utf-8")
        (mock_root / "rtl" / "dual_lane" / "noc_p7_pkg.sv").write_text("// mock", encoding="utf-8")
        (mock_root / "rtl" / "dual_lane" / "noc_l2_auth_p7.sv").write_text("// mock", encoding="utf-8")
        (mock_root / "reports").mkdir(parents=True)
        (mock_root / "reports" / "E4_P7_STEP1_REPORT.md").write_text("# Step 1", encoding="utf-8")

        paths = resolve_paths(repo_root=mock_root, data_dir=mock_root)
        assert validate_repo_root(paths.repo_root) == mock_root
        paths.require_file(paths.rtl_dir / "NOC_PKG.sv", "NOC_PKG.sv")
        paths.require_file(paths.rtl_dir / "noc_p7_pkg.sv", "noc_p7_pkg.sv")
        paths.require_file(paths.rtl_dir / "noc_l2_auth_p7.sv", "noc_l2_auth_p7.sv")
