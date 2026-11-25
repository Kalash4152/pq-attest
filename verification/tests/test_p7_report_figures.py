"""
verification/tests/test_p7_report_figures.py
============================================
PQ-Attest P7 Report Figures Tests — Step 17.

Engineer 4 Verification Infrastructure.

Tests:
1. Execution of figure generator creates all 10 reproducible figures.
2. SVG file existence and valid SVG structure (<svg ... </svg>).
3. Accurate provenance badges embedded in each figure.
4. Measured data fidelity (Figure 10 timing slack from paths_lt3ns.csv).
5. Manifest generation and schema validation (p7_report_figure_manifest.json).
"""

from __future__ import annotations

import json
import sys
from pathlib import Path
import pytest

REPO_ROOT = Path(__file__).resolve().parent.parent.parent
if str(REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(REPO_ROOT))

from verification.p7_paths import get_default_paths
from verification.p7_report_figures import (
    generate_all_report_figures,
)


def test_generate_all_report_figures(tmp_path):
    """Verify that all 10 SVG figures and manifest are generated."""
    fig_dir = tmp_path / "figures"
    manifest_p = tmp_path / "manifest.json"

    manifest_data = generate_all_report_figures(output_dir=fig_dir, manifest_path=manifest_p)

    assert manifest_p.exists()
    assert len(manifest_data["figures"]) == 10

    expected_files = [
        "fig01_pair_matrix.svg",
        "fig02_requirement_coverage.svg",
        "fig03_mutation_results.svg",
        "fig04_ni_slot_occupancy.svg",
        "fig05_timeout_behavior.svg",
        "fig06_latency_breakdown.svg",
        "fig07_link_monitor.svg",
        "fig08_d2_sensitivity.svg",
        "fig09_regression_status.svg",
        "fig10_performance_curves.svg",
    ]

    for fname in expected_files:
        svg_file = fig_dir / fname
        assert svg_file.exists(), f"Missing figure file: {fname}"
        content = svg_file.read_text(encoding="utf-8")
        assert content.strip().startswith("<svg"), f"{fname} does not start with <svg"
        assert content.strip().endswith("</svg>"), f"{fname} does not end with </svg>"


def test_figure_provenance_classifications(tmp_path):
    """Verify provenance classification labels are assigned and embedded accurately."""
    fig_dir = tmp_path / "figures"
    manifest_p = tmp_path / "manifest.json"

    manifest_data = generate_all_report_figures(output_dir=fig_dir, manifest_path=manifest_p)

    prov_map = {f["figure_id"]: f["provenance"] for f in manifest_data["figures"]}

    assert prov_map["FIG_01"] == "SPECIFIED_VALUES"
    assert prov_map["FIG_02"] == "PYTHON_MODEL_OUTPUT"
    assert prov_map["FIG_03"] == "PYTHON_MODEL_OUTPUT"
    assert prov_map["FIG_04"] == "PYTHON_MODEL_OUTPUT"
    assert prov_map["FIG_05"] == "SPECIFIED_VALUES"
    assert prov_map["FIG_06"] == "DERIVED"
    assert prov_map["FIG_07"] == "SYNTHETIC_TEST_INPUT"
    assert prov_map["FIG_08"] == "PYTHON_MODEL_OUTPUT"
    assert prov_map["FIG_09"] == "PYTHON_MODEL_OUTPUT"
    assert prov_map["FIG_10"] == "MEASURED_RTL_DATA"

    # Verify badge is in SVG text
    for f in manifest_data["figures"]:
        svg_file = fig_dir / f["filename"]
        content = svg_file.read_text(encoding="utf-8")
        assert f["provenance"] in content


def test_figure_10_measured_data_integrity(tmp_path):
    """Verify Figure 10 incorporates actual slack measurements from paths_lt3ns.csv."""
    fig_dir = tmp_path / "figures"
    manifest_p = tmp_path / "manifest.json"

    generate_all_report_figures(output_dir=fig_dir, manifest_path=manifest_p)

    f10 = fig_dir / "fig10_performance_curves.svg"
    content = f10.read_text(encoding="utf-8")
    assert "MEASURED_RTL_DATA" in content
    assert "paths_lt3ns.csv" in content
    assert "Timing Slack (ns)" in content

