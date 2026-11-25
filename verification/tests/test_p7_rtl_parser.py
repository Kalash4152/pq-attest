#!/usr/bin/env python3
"""
Unit and mutation tests for verification/p7_rtl_parser.py.

All mutation tests use temporary file copies in pytest's tmp_path fixture.
The live RTL files in rtl/dual_lane are NEVER modified.
"""

from __future__ import annotations

import json
import shutil
import subprocess
import sys
from pathlib import Path
from typing import Tuple

import pytest

from verification.p7_rtl_parser import (
    EXPECTED_PROTOCOL,
    REQUIRED_MESSAGE_TYPES,
    P7RTLParser,
    SVParserError,
)


# Real RTL paths in workspace
WORKSPACE_ROOT = Path(__file__).resolve().parent.parent.parent
REAL_NOC_PKG = WORKSPACE_ROOT / "rtl" / "dual_lane" / "NOC_PKG.sv"
REAL_NOC_P7_PKG = WORKSPACE_ROOT / "rtl" / "dual_lane" / "noc_p7_pkg.sv"
REAL_NOC_L2_AUTH = WORKSPACE_ROOT / "rtl" / "dual_lane" / "noc_l2_auth_p7.sv"


@pytest.fixture
def temp_rtl_env(tmp_path: Path) -> Tuple[Path, Path, Path]:
    """
    Creates isolated temporary copies of the three RTL files for mutation testing.
    """
    tmp_rtl = tmp_path / "rtl"
    tmp_rtl.mkdir(parents=True, exist_ok=True)

    pkg_copy = tmp_rtl / "NOC_PKG.sv"
    p7_pkg_copy = tmp_rtl / "noc_p7_pkg.sv"
    l2_auth_copy = tmp_rtl / "noc_l2_auth_p7.sv"

    shutil.copy2(REAL_NOC_PKG, pkg_copy)
    shutil.copy2(REAL_NOC_P7_PKG, p7_pkg_copy)
    shutil.copy2(REAL_NOC_L2_AUTH, l2_auth_copy)

    return pkg_copy, p7_pkg_copy, l2_auth_copy


# ------------------------------------------------------------------------------
# 1. Correct extraction from current RTL
# ------------------------------------------------------------------------------

def test_correct_extraction_from_current_rtl() -> None:
    """Verifies that parsing live RTL yields 100% match with expected P7 protocol."""
    parser = P7RTLParser(
        noc_pkg_path=REAL_NOC_PKG,
        noc_p7_pkg_path=REAL_NOC_P7_PKG,
        noc_l2_auth_path=REAL_NOC_L2_AUTH,
        repo_root=WORKSPACE_ROOT,
    )

    manifest = parser.extract()

    # Overall status
    assert manifest["metadata"]["status"] == "PASS"
    assert manifest["validation"]["status"] == "PASS"
    assert len(manifest["validation"]["mismatches"]) == 0
    assert manifest["validation"]["passed_checks"] == 8

    # Freshness overhead from noc_l2_auth_p7.sv
    assert manifest["freshness_overhead"]["value"] == 5
    assert manifest["freshness_overhead"]["raw_expression"] == "5"
    assert manifest["freshness_overhead"]["source"]["source_file"] == str(REAL_NOC_L2_AUTH.as_posix())

    # Constants
    consts = manifest["protocol_constants"]
    assert consts["MESH_X"]["value"] == 3
    assert consts["MESH_Y"]["value"] == 2
    assert consts["NUM_TILES"]["value"] == 6
    assert consts["FLIT_WIDTH"]["value"] == 32
    assert consts["NUM_VC"]["value"] == 3
    assert consts["FIFO_DEPTH"]["value"] == 4
    assert consts["MAC_TAG_BITS"]["value"] == 128
    assert consts["MAC_FLITS_FULL"]["value"] == 4

    # Virtual Channels
    vcs = manifest["virtual_channels"]
    assert vcs["VC_REQUEST"]["id"] == 0
    assert vcs["VC_RESPONSE"]["id"] == 1
    assert vcs["VC_ATTESTATION"]["id"] == 2

    # Message Table
    messages = manifest["messages"]
    for msg_name in REQUIRED_MESSAGE_TYPES:
        assert msg_name in messages
        m = messages[msg_name]
        exp = EXPECTED_PROTOCOL[msg_name]
        assert m["payload_flits"] == exp["payload"], f"Payload mismatch on {msg_name}"
        assert m["mac_flits"] == exp["mac"], f"MAC mismatch on {msg_name}"
        assert m["ni_length"] == exp["ni_length"], f"NI length mismatch on {msg_name}"
        assert m["wire_length"] == exp["wire_length"], f"Wire length mismatch on {msg_name}"

        # Check declarations are present
        decls = m["declarations"]
        assert decls["encoding"]["source_file"] == str(REAL_NOC_PKG.as_posix())
        assert decls["payload"]["source_file"] == str(REAL_NOC_PKG.as_posix())
        assert decls["mac"]["source_file"] == str(REAL_NOC_P7_PKG.as_posix())
        if m["is_control"]:
            assert decls["freshness"]["source_file"] == str(REAL_NOC_L2_AUTH.as_posix())
            assert m["freshness_overhead"] == 5
        else:
            assert m["freshness_overhead"] == 0


# ------------------------------------------------------------------------------
# 2. Missing message type
# ------------------------------------------------------------------------------

def test_missing_message_type(temp_rtl_env: Tuple[Path, Path, Path]) -> None:
    """Mutates temp NOC_PKG.sv by removing ATTEST_REVOKE; verifies parser detects it."""
    pkg_copy, p7_pkg_copy, l2_auth_copy = temp_rtl_env

    content = pkg_copy.read_text(encoding="utf-8")
    assert "MSG_ATTEST_REVOKE" in content
    # Remove MSG_ATTEST_REVOKE from enum
    mutated = content.replace("MSG_ATTEST_REVOKE    = 4'd7", "// MSG_ATTEST_REVOKE removed")
    pkg_copy.write_text(mutated, encoding="utf-8")

    parser = P7RTLParser(
        noc_pkg_path=pkg_copy,
        noc_p7_pkg_path=p7_pkg_copy,
        noc_l2_auth_path=l2_auth_copy,
    )

    with pytest.raises(SVParserError) as exc_info:
        parser.extract()

    assert "Missing required message type 'ATTEST_REVOKE'" in str(exc_info.value)
    assert pkg_copy.name in str(exc_info.value)


# ------------------------------------------------------------------------------
# 3. Duplicate message encoding
# ------------------------------------------------------------------------------

def test_duplicate_message_encoding(temp_rtl_env: Tuple[Path, Path, Path]) -> None:
    """Mutates temp NOC_PKG.sv with duplicate encoding for REVOKE (4'd6, same as GRANT)."""
    pkg_copy, p7_pkg_copy, l2_auth_copy = temp_rtl_env

    content = pkg_copy.read_text(encoding="utf-8")
    mutated = content.replace("MSG_ATTEST_REVOKE    = 4'd7", "MSG_ATTEST_REVOKE    = 4'd6")
    pkg_copy.write_text(mutated, encoding="utf-8")

    parser = P7RTLParser(
        noc_pkg_path=pkg_copy,
        noc_p7_pkg_path=p7_pkg_copy,
        noc_l2_auth_path=l2_auth_copy,
    )

    with pytest.raises(SVParserError) as exc_info:
        parser.extract()

    assert "Duplicate message encoding 6" in str(exc_info.value)
    assert "MSG_ATTEST_REVOKE" in str(exc_info.value)


# ------------------------------------------------------------------------------
# 4. Unresolved expression
# ------------------------------------------------------------------------------

def test_unresolved_expression(temp_rtl_env: Tuple[Path, Path, Path]) -> None:
    """Mutates temp NOC_PKG.sv with an undefined identifier in parameter expression."""
    pkg_copy, p7_pkg_copy, l2_auth_copy = temp_rtl_env

    content = pkg_copy.read_text(encoding="utf-8")
    mutated = content.replace(
        "localparam int unsigned MAC_TAG_BITS = 128;",
        "localparam int unsigned MAC_TAG_BITS = UNDEFINED_CONST_XYZ;",
    )
    pkg_copy.write_text(mutated, encoding="utf-8")

    parser = P7RTLParser(
        noc_pkg_path=pkg_copy,
        noc_p7_pkg_path=p7_pkg_copy,
        noc_l2_auth_path=l2_auth_copy,
    )

    with pytest.raises(SVParserError) as exc_info:
        parser.extract()

    assert "Unresolved identifier 'UNDEFINED_CONST_XYZ'" in str(exc_info.value)
    assert "MAC_TAG_BITS" in str(exc_info.value)


# ------------------------------------------------------------------------------
# 5. Changed freshness expression
# ------------------------------------------------------------------------------

def test_changed_freshness_expression(temp_rtl_env: Tuple[Path, Path, Path]) -> None:
    """
    Mutates temp noc_l2_auth_p7.sv by changing length extension from +5 to +8.
    Verifies parser extracts 8 and reports validation mismatch.
    """
    pkg_copy, p7_pkg_copy, l2_auth_copy = temp_rtl_env

    content = l2_auth_copy.read_text(encoding="utf-8")
    mutated = content.replace("v.length=h.length+5;", "v.length=h.length+8;")
    l2_auth_copy.write_text(mutated, encoding="utf-8")

    parser = P7RTLParser(
        noc_pkg_path=pkg_copy,
        noc_p7_pkg_path=p7_pkg_copy,
        noc_l2_auth_path=l2_auth_copy,
    )

    manifest = parser.extract()

    # Freshness overhead extracted must be 8
    assert manifest["freshness_overhead"]["value"] == 8
    assert manifest["freshness_overhead"]["raw_expression"] == "8"

    # Wire length for ATTEST_CHALLENGE must be 12 + 8 = 20
    assert manifest["messages"]["ATTEST_CHALLENGE"]["wire_length"] == 20
    assert manifest["messages"]["ATTEST_RESPONSE"]["wire_length"] == 29

    # Validation must detect mismatch without altering parsed value
    assert manifest["metadata"]["status"] == "MISMATCH"
    assert manifest["validation"]["status"] == "MISMATCH"
    mismatches = manifest["validation"]["mismatches"]
    assert any("ATTEST_CHALLENGE.wire_length: parsed 20 != expected 17" in m for m in mismatches)


# ------------------------------------------------------------------------------
# 6. Changed payload length
# ------------------------------------------------------------------------------

def test_changed_payload_length(temp_rtl_env: Tuple[Path, Path, Path]) -> None:
    """
    Mutates temp NOC_PKG.sv by changing ATTEST_CHALLENGE payload from 7 to 9.
    Verifies payload=9, NI=14, wire=19, and validation mismatch reported.
    """
    pkg_copy, p7_pkg_copy, l2_auth_copy = temp_rtl_env

    content = pkg_copy.read_text(encoding="utf-8")
    mutated = content.replace(
        "MSG_ATTEST_CHALLENGE: return 5'd7;",
        "MSG_ATTEST_CHALLENGE: return 5'd9;",
    )
    pkg_copy.write_text(mutated, encoding="utf-8")

    parser = P7RTLParser(
        noc_pkg_path=pkg_copy,
        noc_p7_pkg_path=p7_pkg_copy,
        noc_l2_auth_path=l2_auth_copy,
    )

    manifest = parser.extract()

    msg = manifest["messages"]["ATTEST_CHALLENGE"]
    assert msg["payload_flits"] == 9
    assert msg["ni_length"] == 14  # 1 HEAD + 9 payload + 4 MAC
    assert msg["wire_length"] == 19  # 14 NI + 5 freshness

    assert manifest["metadata"]["status"] == "MISMATCH"
    mismatches = manifest["validation"]["mismatches"]
    assert any("ATTEST_CHALLENGE.payload: parsed 9 != expected 7" in m for m in mismatches)
    assert any("ATTEST_CHALLENGE.ni_length: parsed 14 != expected 12" in m for m in mismatches)
    assert any("ATTEST_CHALLENGE.wire_length: parsed 19 != expected 17" in m for m in mismatches)


# ------------------------------------------------------------------------------
# 7. Incorrect MAC length
# ------------------------------------------------------------------------------

def test_incorrect_mac_length(temp_rtl_env: Tuple[Path, Path, Path]) -> None:
    """
    Mutates temp NOC_PKG.sv by changing MAC_TAG_BITS from 128 to 256.
    MAC_FLITS_FULL becomes (256 + 32 - 1) / 32 = 8 flits.
    Verifies parser extracts MAC=8 for control types and reports mismatch.
    """
    pkg_copy, p7_pkg_copy, l2_auth_copy = temp_rtl_env

    content = pkg_copy.read_text(encoding="utf-8")
    mutated = content.replace(
        "localparam int unsigned MAC_TAG_BITS = 128;",
        "localparam int unsigned MAC_TAG_BITS = 256;",
    )
    pkg_copy.write_text(mutated, encoding="utf-8")

    parser = P7RTLParser(
        noc_pkg_path=pkg_copy,
        noc_p7_pkg_path=p7_pkg_copy,
        noc_l2_auth_path=l2_auth_copy,
    )

    manifest = parser.extract()

    assert manifest["protocol_constants"]["MAC_TAG_BITS"]["value"] == 256
    assert manifest["protocol_constants"]["MAC_FLITS_FULL"]["value"] == 8

    chal = manifest["messages"]["ATTEST_CHALLENGE"]
    assert chal["mac_flits"] == 8
    assert chal["ni_length"] == 16  # 1 HEAD + 7 payload + 8 MAC
    assert chal["wire_length"] == 21  # 16 NI + 5 freshness

    assert manifest["metadata"]["status"] == "MISMATCH"
    mismatches = manifest["validation"]["mismatches"]
    assert any("ATTEST_CHALLENGE.mac: parsed 8 != expected 4" in m for m in mismatches)


# ------------------------------------------------------------------------------
# 8. Missing source file
# ------------------------------------------------------------------------------

def test_missing_source_file(tmp_path: Path) -> None:
    """Verifies that a missing source file raises SVParserError immediately."""
    non_existent = tmp_path / "DOES_NOT_EXIST.sv"

    parser = P7RTLParser(
        noc_pkg_path=non_existent,
        noc_p7_pkg_path=REAL_NOC_P7_PKG,
        noc_l2_auth_path=REAL_NOC_L2_AUTH,
    )

    with pytest.raises(SVParserError) as exc_info:
        parser.extract()

    assert "Missing required source file" in str(exc_info.value)
    assert "DOES_NOT_EXIST.sv" in str(exc_info.value)


# ------------------------------------------------------------------------------
# 9. Malformed SystemVerilog declaration
# ------------------------------------------------------------------------------

def test_malformed_systemverilog_declaration(temp_rtl_env: Tuple[Path, Path, Path]) -> None:
    """
    Mutates temp NOC_PKG.sv with an unparseable enum item.
    Verifies parser raises SVParserError with line number and declaration.
    """
    pkg_copy, p7_pkg_copy, l2_auth_copy = temp_rtl_env

    content = pkg_copy.read_text(encoding="utf-8")
    # Break enum syntax by adding invalid token
    mutated = content.replace("MSG_MEM_RD_REQ       = 4'd0,", "MSG_MEM_RD_REQ === 4'd0,")
    pkg_copy.write_text(mutated, encoding="utf-8")

    parser = P7RTLParser(
        noc_pkg_path=pkg_copy,
        noc_p7_pkg_path=p7_pkg_copy,
        noc_l2_auth_path=l2_auth_copy,
    )

    with pytest.raises(SVParserError) as exc_info:
        parser.extract()

    assert "Malformed enum item" in str(exc_info.value) or "Unexpected token" in str(exc_info.value)
    assert pkg_copy.name in str(exc_info.value)


# ------------------------------------------------------------------------------
# 10. CLI execution test
# ------------------------------------------------------------------------------

def test_cli_execution(tmp_path: Path) -> None:
    """Verifies that python -m verification.p7_rtl_parser runs cleanly with --check."""
    out_file = tmp_path / "test_manifest.json"
    cmd = [
        sys.executable,
        "-m",
        "verification.p7_rtl_parser",
        "--output",
        str(out_file),
        "--check",
    ]
    proc = subprocess.run(
        cmd,
        cwd=WORKSPACE_ROOT,
        capture_output=True,
        text=True,
    )
    assert proc.returncode == 0, f"CLI failed:\nSTDOUT:\n{proc.stdout}\nSTDERR:\n{proc.stderr}"
    assert "PQ-ATTEST P7 PROTOCOL EXTRACTION REPORT" in proc.stdout
    assert "Overall Status: PASS" in proc.stdout
    assert out_file.exists()

    data = json.loads(out_file.read_text(encoding="utf-8"))
    assert data["metadata"]["status"] == "PASS"

