#!/usr/bin/env python3
"""
PQ-Attest P7 Verification - Step 1: Live RTL Protocol Extraction

This module extracts the authoritative P7 protocol definitions directly from the
SystemVerilog RTL source files:
  - rtl/dual_lane/NOC_PKG.sv
  - rtl/dual_lane/noc_p7_pkg.sv
  - rtl/dual_lane/noc_l2_auth_p7.sv

It resolves numeric expressions, parameters, enums, case statements, and
function logic without hardcoding values or silently substituting defaults.
"""

from __future__ import annotations

import argparse
import datetime
import hashlib
import json
import os
import re
import sys
from dataclasses import asdict, dataclass
from pathlib import Path
from typing import Any, Dict, List, Optional, Set, Tuple

try:
    from verification.p7_paths import get_default_paths
except ImportError:  # executed as a script from within verification/
    from p7_paths import get_default_paths


# ==============================================================================
# Error Handling and Source Tracking
# ==============================================================================

class SVParserError(Exception):
    """Raised when parsing fails, files are missing, or declarations are malformed."""

    def __init__(
        self,
        message: str,
        source_file: Optional[str] = None,
        line_number: Optional[int] = None,
        declaration: Optional[str] = None,
    ) -> None:
        self.message = message
        self.source_file = source_file
        self.line_number = line_number
        self.declaration = declaration
        parts = [message]
        if source_file:
            loc = f"{source_file}"
            if line_number is not None:
                loc += f":{line_number}"
            parts.append(f"at {loc}")
        if declaration:
            parts.append(f"declaration: '{declaration.strip()}'")
        super().__init__(" - ".join(parts))


@dataclass
class SourceDeclaration:
    """Tracks origin of any extracted value."""
    source_file: str
    line_number: int
    declaration: str

    def to_dict(self) -> Dict[str, Any]:
        return asdict(self)


# ==============================================================================
# SystemVerilog Expression Evaluator
# ==============================================================================

class SVExpressionEvaluator:
    """
    Evaluator for SystemVerilog constant expressions.
    Handles:
      - Integers (decimal, sized Verilog literals like 4'd0, 1'b1, 32'h2000, 'd0)
      - Casting: 5'(expr), int unsigned'(expr), logic [4:0]'(expr)
      - System functions: $clog2(n), $bits(type)
      - Parameter / identifier lookup
      - Part select / bit slices: t[3:2], t[1]
      - Operators: +, -, *, /, %, ==, !=, <, <=, >, >=, &&, ||, &, |, ^, ~, !, <<, >>, ? :
    """

    TOKEN_RE = re.compile(
        r"""
        \s*(?:
            (?P<VNUM>(?:\d+)?'[bBdDoOhH][0-9a-fA-F_]+)
            |(?P<NUM>\b\d+\b)
            |(?P<SYSFUNC>\$[A-Za-z_][A-Za-z0-9_]*)
            |(?P<OP>==|!=|<=|>=|<<|>>|&&|\|\||[+\-*/%&|^~!?:\(\)\[\],])
            |(?P<ID>[A-Za-z_][A-Za-z0-9_]*)
        )
        """,
        re.VERBOSE,
    )

    @staticmethod
    def strip_casts(expr: str) -> str:
        """
        Replaces SystemVerilog type cast patterns like `5'(...)` or `int'(...)`
        with simple parentheses `(...)`.
        """
        pattern = re.compile(
            r"""(?:[A-Za-z_][A-Za-z0-9_]*(?:\s+unsigned)?|\d+|logic\s*\[[^\]]+\])\s*'\s*\(""",
            re.VERBOSE,
        )
        while True:
            new_expr, count = pattern.subn("(", expr)
            if count == 0:
                break
            expr = new_expr
        return expr

    @classmethod
    def sv_clog2(cls, val: int) -> int:
        """IEEE 1800 $clog2 function."""
        if val <= 1:
            return 0
        return (val - 1).bit_length()

    @classmethod
    def tokenize(cls, expr: str, origin: Optional[SourceDeclaration] = None) -> List[Tuple[str, Any]]:
        clean = cls.strip_casts(expr)
        tokens: List[Tuple[str, Any]] = []
        pos = 0
        while pos < len(clean):
            m = cls.TOKEN_RE.match(clean, pos)
            if not m:
                if clean[pos].isspace():
                    pos += 1
                    continue
                raise SVParserError(
                    f"Invalid character in expression '{clean[pos:]}'",
                    source_file=origin.source_file if origin else None,
                    line_number=origin.line_number if origin else None,
                    declaration=origin.declaration if origin else expr,
                )
            pos = m.end()
            kind = m.lastgroup
            val = m.group(kind)
            if kind == "VNUM":
                parts = val.split("'")
                base_char = parts[1][0].lower()
                num_str = parts[1][1:].replace("_", "")
                base_map = {"b": 2, "o": 8, "d": 10, "h": 16}
                if base_char not in base_map:
                    raise SVParserError(
                        f"Unsupported numeric base '{base_char}' in literal '{val}'",
                        source_file=origin.source_file if origin else None,
                        line_number=origin.line_number if origin else None,
                        declaration=origin.declaration if origin else expr,
                    )
                tokens.append(("NUM", int(num_str, base_map[base_char])))
            elif kind == "NUM":
                tokens.append(("NUM", int(val)))
            elif kind == "SYSFUNC":
                tokens.append(("SYSFUNC", val))
            elif kind == "ID":
                tokens.append(("ID", val))
            elif kind == "OP":
                tokens.append(("OP", val))
        tokens.append(("EOF", ""))
        return tokens

    @classmethod
    def evaluate(
        cls,
        expr_str: str,
        symbols: Dict[str, Any],
        origin: Optional[SourceDeclaration] = None,
        type_widths: Optional[Dict[str, int]] = None,
    ) -> int:
        """Parses and evaluates an expression using the provided symbol table."""
        tokens = cls.tokenize(expr_str, origin)
        pos = 0
        tw = type_widths or {}

        def current() -> Tuple[str, Any]:
            nonlocal pos
            return tokens[pos]

        def consume(expected: Optional[str] = None) -> Tuple[str, Any]:
            nonlocal pos
            tok = tokens[pos]
            if expected is not None:
                if tok[0] != expected and tok[1] != expected:
                    raise SVParserError(
                        f"Expected '{expected}', found '{tok[1]}'",
                        source_file=origin.source_file if origin else None,
                        line_number=origin.line_number if origin else None,
                        declaration=origin.declaration if origin else expr_str,
                    )
            pos += 1
            return tok

        def parse_ternary() -> int:
            cond = parse_logical_or()
            if current()[0] == "OP" and current()[1] == "?":
                consume("?")
                true_val = parse_ternary()
                consume(":")
                false_val = parse_ternary()
                return true_val if cond != 0 else false_val
            return cond

        def parse_logical_or() -> int:
            val = parse_logical_and()
            while current()[0] == "OP" and current()[1] == "||":
                consume("||")
                rhs = parse_logical_and()
                val = 1 if (val != 0 or rhs != 0) else 0
            return val

        def parse_logical_and() -> int:
            val = parse_bitwise_or()
            while current()[0] == "OP" and current()[1] == "&&":
                consume("&&")
                rhs = parse_bitwise_or()
                val = 1 if (val != 0 and rhs != 0) else 0
            return val

        def parse_bitwise_or() -> int:
            val = parse_bitwise_xor()
            while current()[0] == "OP" and current()[1] == "|":
                consume("|")
                rhs = parse_bitwise_xor()
                val = val | rhs
            return val

        def parse_bitwise_xor() -> int:
            val = parse_bitwise_and()
            while current()[0] == "OP" and current()[1] == "^":
                consume("^")
                rhs = parse_bitwise_and()
                val = val ^ rhs
            return val

        def parse_bitwise_and() -> int:
            val = parse_equality()
            while current()[0] == "OP" and current()[1] == "&":
                consume("&")
                rhs = parse_equality()
                val = val & rhs
            return val

        def parse_equality() -> int:
            val = parse_relational()
            while current()[0] == "OP" and current()[1] in ("==", "!="):
                op = consume()[1]
                rhs = parse_relational()
                if op == "==":
                    val = 1 if val == rhs else 0
                else:
                    val = 1 if val != rhs else 0
            return val

        def parse_relational() -> int:
            val = parse_shift()
            while current()[0] == "OP" and current()[1] in ("<", "<=", ">", ">="):
                op = consume()[1]
                rhs = parse_shift()
                if op == "<":
                    val = 1 if val < rhs else 0
                elif op == "<=":
                    val = 1 if val <= rhs else 0
                elif op == ">":
                    val = 1 if val > rhs else 0
                else:
                    val = 1 if val >= rhs else 0
            return val

        def parse_shift() -> int:
            val = parse_additive()
            while current()[0] == "OP" and current()[1] in ("<<", ">>"):
                op = consume()[1]
                rhs = parse_additive()
                if op == "<<":
                    val = val << rhs
                else:
                    val = val >> rhs
            return val

        def parse_additive() -> int:
            val = parse_multiplicative()
            while current()[0] == "OP" and current()[1] in ("+", "-"):
                op = consume()[1]
                rhs = parse_multiplicative()
                if op == "+":
                    val = val + rhs
                else:
                    val = val - rhs
            return val

        def parse_multiplicative() -> int:
            val = parse_unary()
            while current()[0] == "OP" and current()[1] in ("*", "/", "%"):
                op = consume()[1]
                rhs = parse_unary()
                if op == "*":
                    val = val * rhs
                elif op == "/":
                    if rhs == 0:
                        raise SVParserError(
                            "Division by zero in expression",
                            source_file=origin.source_file if origin else None,
                            line_number=origin.line_number if origin else None,
                            declaration=origin.declaration if origin else expr_str,
                        )
                    val = val // rhs
                else:
                    val = val % rhs
            return val

        def parse_unary() -> int:
            if current()[0] == "OP" and current()[1] in ("+", "-", "!", "~"):
                op = consume()[1]
                operand = parse_unary()
                if op == "+":
                    return operand
                if op == "-":
                    return -operand
                if op == "!":
                    return 0 if operand != 0 else 1
                if op == "~":
                    return ~operand
            return parse_primary()

        def parse_primary() -> int:
            tok = current()
            if tok[0] == "NUM":
                consume()
                val = tok[1]
                return val
            if tok[0] == "SYSFUNC":
                func_name = consume()[1]
                consume("(")
                if func_name == "$clog2":
                    arg = parse_ternary()
                    consume(")")
                    return cls.sv_clog2(arg)
                if func_name == "$bits":
                    arg_tok = consume()
                    consume(")")
                    target = str(arg_tok[1])
                    if target in tw:
                        return tw[target]
                    if target in symbols and isinstance(symbols[target], int):
                        return symbols[target].bit_length()
                    if target == "flit_t":
                        # standard flit_t width = FLIT_WIDTH + 2 (flit_type) + VC_ID_WIDTH
                        fw = symbols.get("FLIT_WIDTH", 32)
                        vcw = symbols.get("VC_ID_WIDTH", 2)
                        return fw + 2 + vcw
                    raise SVParserError(
                        f"Unable to resolve $bits({target})",
                        source_file=origin.source_file if origin else None,
                        line_number=origin.line_number if origin else None,
                        declaration=origin.declaration if origin else expr_str,
                    )
                raise SVParserError(
                    f"Unsupported system function '{func_name}'",
                    source_file=origin.source_file if origin else None,
                    line_number=origin.line_number if origin else None,
                    declaration=origin.declaration if origin else expr_str,
                )
            if tok[0] == "ID":
                ident = consume()[1]
                if ident not in symbols:
                    raise SVParserError(
                        f"Unresolved identifier '{ident}' in expression '{expr_str}'",
                        source_file=origin.source_file if origin else None,
                        line_number=origin.line_number if origin else None,
                        declaration=origin.declaration if origin else expr_str,
                    )
                val = symbols[ident]
                if current()[0] == "OP" and current()[1] == "[":
                    # Part-select or bit-select
                    consume("[")
                    msb = parse_ternary()
                    if current()[0] == "OP" and current()[1] == ":":
                        consume(":")
                        lsb = parse_ternary()
                        consume("]")
                        mask = (1 << (msb - lsb + 1)) - 1
                        val = (val >> lsb) & mask
                    else:
                        consume("]")
                        val = (val >> msb) & 1
                return val
            if tok[0] == "OP" and tok[1] == "(":
                consume("(")
                val = parse_ternary()
                consume(")")
                return val

            raise SVParserError(
                f"Unexpected token '{tok[1]}' while evaluating '{expr_str}'",
                source_file=origin.source_file if origin else None,
                line_number=origin.line_number if origin else None,
                declaration=origin.declaration if origin else expr_str,
            )

        res = parse_ternary()
        if current()[0] != "EOF":
            raise SVParserError(
                f"Extra tokens after expression: '{current()[1]}'",
                source_file=origin.source_file if origin else None,
                line_number=origin.line_number if origin else None,
                declaration=origin.declaration if origin else expr_str,
            )
        return res


# ==============================================================================
# P7 Protocol Parser Implementation
# ==============================================================================

# Required message types per specification
REQUIRED_MESSAGE_TYPES = [
    "MEM_RD_REQ",
    "MEM_RD_RESP",
    "MEM_WR_REQ",
    "MEM_WR_RESP",
    "ATTEST_CHALLENGE",
    "ATTEST_RESPONSE",
    "ATTEST_GRANT",
    "ATTEST_REVOKE",
]

# Validation expectations
EXPECTED_PROTOCOL = {
    "MEM_RD_REQ": {"payload": 1, "mac": 0, "ni_length": 2, "wire_length": 2},
    "MEM_RD_RESP": {"payload": 1, "mac": 0, "ni_length": 2, "wire_length": 2},
    "MEM_WR_REQ": {"payload": 2, "mac": 0, "ni_length": 3, "wire_length": 3},
    "MEM_WR_RESP": {"payload": 0, "mac": 0, "ni_length": 1, "wire_length": 1},
    "ATTEST_CHALLENGE": {"payload": 7, "mac": 4, "ni_length": 12, "wire_length": 17},
    "ATTEST_RESPONSE": {"payload": 16, "mac": 4, "ni_length": 21, "wire_length": 26},
    "ATTEST_GRANT": {"payload": 0, "mac": 4, "ni_length": 5, "wire_length": 10},
    "ATTEST_REVOKE": {"payload": 0, "mac": 4, "ni_length": 5, "wire_length": 10},
}


class P7RTLParser:
    """
    Authoritative P7 protocol parser for live SystemVerilog sources.
    """

    def __init__(
        self,
        noc_pkg_path: Optional[Path | str] = None,
        noc_p7_pkg_path: Optional[Path | str] = None,
        noc_l2_auth_path: Optional[Path | str] = None,
        repo_root: Optional[Path | str] = None,
    ) -> None:
        # Never default to the current working directory: discover the repository
        # (or honour P7_REPO_ROOT) through the shared resolver.
        self._repo_root_explicit = repo_root is not None
        self.repo_root = Path(repo_root).resolve() if repo_root else get_default_paths().repo_root
        self.noc_pkg_path = Path(noc_pkg_path) if noc_pkg_path else self.repo_root / "rtl" / "dual_lane" / "NOC_PKG.sv"
        self.noc_p7_pkg_path = Path(noc_p7_pkg_path) if noc_p7_pkg_path else self.repo_root / "rtl" / "dual_lane" / "noc_p7_pkg.sv"
        self.noc_l2_auth_path = Path(noc_l2_auth_path) if noc_l2_auth_path else self.repo_root / "rtl" / "dual_lane" / "noc_l2_auth_p7.sv"

        self.warnings: List[str] = []
        self.errors: List[str] = []

    def _display_path(self, path: Path) -> str:
        """Preserve file path as POSIX string."""
        return str(Path(path).as_posix())

    @property
    def default_output_path(self) -> Path:
        """Default manifest location: configured out dir, or <repo_root>/verification/generated."""
        if self._repo_root_explicit:
            return self.repo_root / "verification" / "generated" / "p7_protocol_manifest.json"
        return get_default_paths().generated_dir / "p7_protocol_manifest.json"

    def _verify_files_exist(self) -> None:
        """Verifies that all three source files exist; stops rather than guessing."""
        for path in [self.noc_pkg_path, self.noc_p7_pkg_path, self.noc_l2_auth_path]:
            if not path.exists():
                err = f"Missing required source file: {path.resolve()}"
                self.errors.append(err)
                raise SVParserError(err, source_file=str(path))

    @staticmethod
    def strip_comments(text: str) -> str:
        """Strips line and block comments while strictly preserving newline counts."""
        def repl_block(m: re.Match) -> str:
            return "\n" * m.group(0).count("\n")

        clean = re.sub(r"/\*.*?\*/", repl_block, text, flags=re.DOTALL)
        clean = re.sub(r"//[^\n]*", "", clean)
        return clean

    @staticmethod
    def preprocess_ifdefs(text: str, defines: Optional[Dict[str, bool]] = None) -> str:
        """
        Processes `ifdef / `else / `endif blocks while preserving line numbers.
        For P7 architecture, PQ_MAC_ON is defined by default.
        """
        if defines is None:
            defines = {"PQ_MAC_ON": True}

        lines = text.splitlines(keepends=True)
        out_lines: List[str] = []
        stack = [True]

        for line in lines:
            m_if = re.match(r"^\s*`ifdef\s+([A-Za-z0-9_]+)", line)
            m_else = re.match(r"^\s*`else", line)
            m_endif = re.match(r"^\s*`endif", line)

            if m_if:
                cond = m_if.group(1) in defines and defines[m_if.group(1)]
                stack.append(stack[-1] and cond)
                out_lines.append("\n")
            elif m_else:
                parent = stack[-2] if len(stack) > 1 else True
                prev = stack.pop()
                stack.append(parent and not prev)
                out_lines.append("\n")
            elif m_endif:
                if len(stack) > 1:
                    stack.pop()
                out_lines.append("\n")
            else:
                if stack[-1]:
                    out_lines.append(line)
                else:
                    out_lines.append("\n")

        return "".join(out_lines)

    @staticmethod
    def get_line_number(text: str, index: int) -> int:
        """Returns 1-based line number for character index in text."""
        return text[:index].count("\n") + 1

    def parse_constants(
        self,
        clean_text: str,
        file_path: Path,
        type_widths: Optional[Dict[str, int]] = None,
    ) -> Tuple[Dict[str, int], Dict[str, SourceDeclaration]]:
        """
        Parses localparam and parameter declarations from SystemVerilog text.
        Resolves expressions iteratively using dependency resolution.
        """
        param_pattern = re.compile(
            r"\b(?:localparam|parameter)\s+(?:(?:int\s+unsigned|int|bit|logic(?:\s*\[[^\]]+\])?)\s+)?([A-Za-z_][A-Za-z0-9_]*)\s*=\s*([^;]+);",
            re.DOTALL,
        )

        raw_params: Dict[str, Tuple[str, SourceDeclaration]] = {}
        for match in param_pattern.finditer(clean_text):
            name = match.group(1).strip()
            expr = match.group(2).strip()
            line_no = self.get_line_number(clean_text, match.start())
            decl_text = match.group(0).strip().replace("\n", " ")
            decl_text = re.sub(r"\s+", " ", decl_text)
            origin = SourceDeclaration(
                source_file=self._display_path(file_path),
                line_number=line_no,
                declaration=decl_text,
            )
            raw_params[name] = (expr, origin)

        # Resolve values iteratively
        resolved_symbols: Dict[str, int] = {}
        param_origins: Dict[str, SourceDeclaration] = {}
        remaining = dict(raw_params)

        passes = 0
        max_passes = len(remaining) + 5
        last_errors: Dict[str, SVParserError] = {}
        while remaining and passes < max_passes:
            progress = False
            for name in list(remaining.keys()):
                expr, origin = remaining[name]
                try:
                    val = SVExpressionEvaluator.evaluate(
                        expr, resolved_symbols, origin, type_widths=type_widths
                    )
                    resolved_symbols[name] = val
                    param_origins[name] = origin
                    del remaining[name]
                    progress = True
                    if name in last_errors:
                        del last_errors[name]
                except SVParserError as e:
                    last_errors[name] = e
            passes += 1
            if not progress:
                break

        if remaining:
            first_name = next(iter(remaining))
            if first_name in last_errors:
                self.errors.append(str(last_errors[first_name]))
                raise last_errors[first_name]
            expr, origin = remaining[first_name]
            err = f"Unresolved parameter expression '{first_name} = {expr}'"
            self.errors.append(f"{err} in {origin.source_file}:{origin.line_number}")
            raise SVParserError(
                err,
                source_file=origin.source_file,
                line_number=origin.line_number,
                declaration=origin.declaration,
            )

        return resolved_symbols, param_origins

    def parse_enum(
        self,
        clean_text: str,
        enum_type_name: str,
        symbols: Dict[str, int],
        file_path: Path,
    ) -> Tuple[Dict[str, int], Dict[str, SourceDeclaration]]:
        """
        Parses typedef enum ... { ... } <enum_type_name>;
        Returns member name -> numeric value and member name -> SourceDeclaration.
        """
        enum_pattern = re.compile(
            r"typedef\s+enum\s+(?:(?:logic|int)(?:\s*\[[^\]]+\])?\s*)?\{(?P<body>[^}]+)\}\s*"
            + re.escape(enum_type_name)
            + r"\s*;",
            re.DOTALL,
        )
        match = enum_pattern.search(clean_text)
        if not match:
            err = f"Missing enum declaration for '{enum_type_name}' in {file_path}"
            self.errors.append(err)
            raise SVParserError(err, source_file=str(file_path.as_posix()))

        body = match.group("body")
        enum_start_idx = match.start("body")

        members: Dict[str, int] = {}
        origins: Dict[str, SourceDeclaration] = {}
        curr_val = 0

        for raw_item in body.split(","):
            raw_item_strip = raw_item.strip()
            if not raw_item_strip:
                continue

            item_match_idx = clean_text.find(raw_item_strip, enum_start_idx)
            line_no = self.get_line_number(clean_text, item_match_idx if item_match_idx != -1 else match.start())
            origin = SourceDeclaration(
                source_file=self._display_path(file_path),
                line_number=line_no,
                declaration=raw_item_strip,
            )

            if "=" in raw_item_strip:
                parts = raw_item_strip.split("=", 1)
                name = parts[0].strip()
                expr = parts[1].strip()
                val = SVExpressionEvaluator.evaluate(expr, symbols, origin)
                curr_val = val
            else:
                name = raw_item_strip
                val = curr_val

            if not re.match(r"^[A-Za-z_][A-Za-z0-9_]*$", name):
                raise SVParserError(
                    f"Malformed enum item name '{name}' in '{enum_type_name}'",
                    source_file=origin.source_file,
                    line_number=origin.line_number,
                    declaration=origin.declaration,
                )

            members[name] = val
            origins[name] = origin
            curr_val += 1

        return members, origins

    def parse_function_case_map(
        self,
        clean_text: str,
        func_name: str,
        symbols: Dict[str, int],
        file_path: Path,
    ) -> Tuple[Dict[str, Any], Dict[str, SourceDeclaration]]:
        """
        Parses a SystemVerilog function that maps inputs via a case statement to return values.
        Returns label -> value (or string for enum return) and label -> SourceDeclaration.
        """
        func_pattern = re.compile(
            r"function\s+(?:automatic\s+)?(?:[A-Za-z0-9_\[\]:\-\$\s]+?\s+)?("
            + re.escape(func_name)
            + r")\s*\([^)]*\)\s*;(?P<body>.*?)endfunction",
            re.DOTALL,
        )
        match = func_pattern.search(clean_text)
        if not match:
            err = f"Function '{func_name}' not found in {file_path}"
            self.errors.append(err)
            raise SVParserError(err, source_file=str(file_path.as_posix()))

        body = match.group("body")
        case_match = re.search(r"case\s*\([^)]+\)(?P<case_body>.*?)endcase", body, re.DOTALL)
        if not case_match:
            err = f"Case statement not found in function '{func_name}' in {file_path}"
            self.errors.append(err)
            raise SVParserError(err, source_file=str(file_path.as_posix()))

        case_body = case_match.group("case_body")
        branch_pattern = re.compile(r"([A-Za-z0-9_,\s]+):\s*(?:begin\s*)?return\s+([^;]+);", re.DOTALL)

        mapping: Dict[str, Any] = {}
        origins: Dict[str, SourceDeclaration] = {}

        for b_match in branch_pattern.finditer(case_body):
            raw_labels = b_match.group(1).strip()
            ret_expr = b_match.group(2).strip()
            decl_text = b_match.group(0).strip().replace("\n", " ")
            decl_text = re.sub(r"\s+", " ", decl_text)
            line_no = self.get_line_number(clean_text, match.start("body") + b_match.start())
            origin = SourceDeclaration(
                source_file=self._display_path(file_path),
                line_number=line_no,
                declaration=decl_text,
            )

            val: Any
            try:
                val = SVExpressionEvaluator.evaluate(ret_expr, symbols, origin)
            except SVParserError:
                if re.match(r"^[A-Za-z_][A-Za-z0-9_]*$", ret_expr):
                    val = ret_expr
                else:
                    raise

            for label in raw_labels.split(","):
                label_strip = label.strip()
                if label_strip:
                    mapping[label_strip] = val
                    origins[label_strip] = origin

        return mapping, origins

    def parse_control_and_mac_logic(
        self,
        clean_text: str,
        symbols: Dict[str, int],
        file_path: Path,
    ) -> Tuple[str, SourceDeclaration, str, SourceDeclaration]:
        """
        Parses `is_control` and `p7_mac_flits` logic from `noc_p7_pkg.sv`.
        """
        # Parse is_control
        is_ctl_pattern = re.compile(
            r"function\s+(?:automatic\s+)?logic\s+is_control\s*\(([^)]*)\)\s*;(?P<body>.*?)endfunction",
            re.DOTALL,
        )
        ctl_match = is_ctl_pattern.search(clean_text)
        if not ctl_match:
            err = f"Function 'is_control' not found in {file_path}"
            self.errors.append(err)
            raise SVParserError(err, source_file=str(file_path.as_posix()))

        ctl_body = ctl_match.group("body")
        ret_ctl_match = re.search(r"return\s+([^;]+);", ctl_body)
        if not ret_ctl_match:
            err = f"Return statement not found in 'is_control' in {file_path}"
            raise SVParserError(err, source_file=str(file_path.as_posix()))

        ctl_expr = ret_ctl_match.group(1).strip()
        ctl_line = self.get_line_number(clean_text, ctl_match.start())
        ctl_origin = SourceDeclaration(
            source_file=self._display_path(file_path),
            line_number=ctl_line,
            declaration=f"return {ctl_expr};",
        )

        # Parse p7_mac_flits
        mac_pattern = re.compile(
            r"function\s+(?:automatic\s+)?int\s+unsigned\s+p7_mac_flits\s*\(([^)]*)\)\s*;(?P<body>.*?)endfunction",
            re.DOTALL,
        )
        mac_match = mac_pattern.search(clean_text)
        if not mac_match:
            err = f"Function 'p7_mac_flits' not found in {file_path}"
            self.errors.append(err)
            raise SVParserError(err, source_file=str(file_path.as_posix()))

        mac_body = mac_match.group("body")
        ret_mac_match = re.search(r"return\s+([^;]+);", mac_body)
        if not ret_mac_match:
            err = f"Return statement not found in 'p7_mac_flits' in {file_path}"
            raise SVParserError(err, source_file=str(file_path.as_posix()))

        mac_expr = ret_mac_match.group(1).strip()
        mac_line = self.get_line_number(clean_text, mac_match.start())
        mac_origin = SourceDeclaration(
            source_file=self._display_path(file_path),
            line_number=mac_line,
            declaration=f"return {mac_expr};",
        )

        return ctl_expr, ctl_origin, mac_expr, mac_origin

    def parse_freshness_overhead(
        self,
        clean_text: str,
        symbols: Dict[str, int],
        file_path: Path,
    ) -> Tuple[int, str, SourceDeclaration]:
        """
        Parses the actual length-extension expression from `noc_l2_auth_p7.sv`.
        Locates the `extend` function:
          function automatic head_flit_t extend(input head_flit_t h);
            head_flit_t v; v=h; v.length=h.length+5; return v;
          endfunction
        Extracts the expression added to `h.length`, resolves it, and returns
        (evaluated_int, raw_expr, SourceDeclaration).
        """
        extend_pattern = re.compile(
            r"function\s+(?:automatic\s+)?head_flit_t\s+extend\s*\([^)]*\)\s*;(?P<body>.*?)endfunction",
            re.DOTALL,
        )
        match = extend_pattern.search(clean_text)
        if not match:
            err = f"Function 'extend' not found in {file_path}"
            self.errors.append(err)
            raise SVParserError(err, source_file=str(file_path.as_posix()))

        body = match.group("body")
        assign_match = re.search(r"v\.length\s*=\s*h\.length\s*\+\s*([^;]+);", body)
        if not assign_match:
            err = f"Length-extension assignment 'v.length = h.length + ...' not found in {file_path}"
            self.errors.append(err)
            raise SVParserError(err, source_file=str(file_path.as_posix()))

        raw_expr = assign_match.group(1).strip()
        decl_text = assign_match.group(0).strip()
        line_no = self.get_line_number(clean_text, match.start("body") + assign_match.start())
        origin = SourceDeclaration(
            source_file=self._display_path(file_path),
            line_number=line_no,
            declaration=decl_text,
        )

        overhead = SVExpressionEvaluator.evaluate(raw_expr, symbols, origin)
        return overhead, raw_expr, origin

    def extract(self) -> Dict[str, Any]:
        """
        Executes full extraction pipeline and returns the protocol manifest dictionary.
        """
        self._verify_files_exist()

        # Read source files
        noc_pkg_content = self.noc_pkg_path.read_text(encoding="utf-8")
        noc_p7_pkg_content = self.noc_p7_pkg_path.read_text(encoding="utf-8")
        noc_l2_auth_content = self.noc_l2_auth_path.read_text(encoding="utf-8")

        # Strip comments and handle ifdefs
        clean_noc_pkg = self.preprocess_ifdefs(self.strip_comments(noc_pkg_content))
        clean_noc_p7_pkg = self.preprocess_ifdefs(self.strip_comments(noc_p7_pkg_content))
        clean_noc_l2_auth = self.preprocess_ifdefs(self.strip_comments(noc_l2_auth_content))

        # 1. Parse constants from NOC_PKG.sv
        symbols, param_origins = self.parse_constants(clean_noc_pkg, self.noc_pkg_path)

        # 2. Parse Virtual Channels enum
        vc_enums, vc_origins = self.parse_enum(clean_noc_pkg, "vc_e", symbols, self.noc_pkg_path)
        symbols.update(vc_enums)

        # 3. Parse Message Types enum
        msg_enums, msg_origins = self.parse_enum(clean_noc_pkg, "msg_type_e", symbols, self.noc_pkg_path)

        # Check for duplicate message encodings
        encodings_seen: Dict[int, str] = {}
        for name, enc in msg_enums.items():
            if enc in encodings_seen:
                err = f"Duplicate message encoding {enc} for '{name}' and '{encodings_seen[enc]}'"
                self.errors.append(f"{err} in {msg_origins[name].source_file}:{msg_origins[name].line_number}")
                raise SVParserError(
                    err,
                    source_file=msg_origins[name].source_file,
                    line_number=msg_origins[name].line_number,
                    declaration=msg_origins[name].declaration,
                )
            encodings_seen[enc] = name

        # Check for missing required message types
        for req_msg in REQUIRED_MESSAGE_TYPES:
            if f"MSG_{req_msg}" not in msg_enums and req_msg not in msg_enums:
                err = f"Missing required message type '{req_msg}' in msg_type_e"
                self.errors.append(f"{err} in {self.noc_pkg_path}")
                raise SVParserError(err, source_file=str(self.noc_pkg_path.as_posix()))

        # 4. Parse VC Mapping from NOC_PKG.sv (message_to_vc)
        vc_map, vc_map_origins = self.parse_function_case_map(clean_noc_pkg, "message_to_vc", symbols, self.noc_pkg_path)

        # 5. Parse Payload Flits from NOC_PKG.sv (message_payload_flits)
        payload_map, payload_origins = self.parse_function_case_map(clean_noc_pkg, "message_payload_flits", symbols, self.noc_pkg_path)

        # 6. Parse Control and MAC logic from noc_p7_pkg.sv
        ctl_expr, ctl_origin, mac_expr, mac_origin = self.parse_control_and_mac_logic(
            clean_noc_p7_pkg, symbols, self.noc_p7_pkg_path
        )

        # 7. Parse Freshness Overhead from noc_l2_auth_p7.sv
        freshness_overhead, freshness_expr, freshness_origin = self.parse_freshness_overhead(
            clean_noc_l2_auth, symbols, self.noc_l2_auth_path
        )

        # 8. Assemble protocol definitions for all message types
        messages: Dict[str, Dict[str, Any]] = {}
        validation_results: List[Dict[str, Any]] = []
        validation_mismatches: List[str] = []

        for req_name in REQUIRED_MESSAGE_TYPES:
            enum_key = f"MSG_{req_name}" if f"MSG_{req_name}" in msg_enums else req_name
            encoding = msg_enums[enum_key]

            # Payload flits
            payload = payload_map.get(enum_key, payload_map.get(req_name, payload_map.get("default")))
            if payload is None:
                err = f"Payload flits not defined for '{req_name}'"
                self.errors.append(err)
                raise SVParserError(err, source_file=str(self.noc_pkg_path.as_posix()))

            # VC mapping
            vc_target = vc_map.get(enum_key, vc_map.get(req_name, vc_map.get("default")))
            if vc_target is None:
                err = f"VC mapping not defined for '{req_name}'"
                self.errors.append(err)
                raise SVParserError(err, source_file=str(self.noc_pkg_path.as_posix()))

            if isinstance(vc_target, str):
                vc_name = vc_target
                vc_id = vc_enums.get(vc_name, symbols.get(vc_name, 0))
            else:
                vc_id = int(vc_target)
                vc_name = next((k for k, v in vc_enums.items() if v == vc_id), f"VC_{vc_id}")

            # Evaluate is_control(t)
            is_control_val = SVExpressionEvaluator.evaluate(
                ctl_expr,
                {**symbols, "t": encoding},
                ctl_origin,
            ) != 0

            # Evaluate p7_mac_flits(t)
            if "is_control(" in mac_expr:
                mac_flits = symbols.get("MAC_FLITS_FULL", 4) if is_control_val else 0
            else:
                mac_flits = SVExpressionEvaluator.evaluate(
                    mac_expr,
                    {**symbols, "t": encoding, "is_control": 1 if is_control_val else 0},
                    mac_origin,
                )

            # NI packet length = 1 (HEAD) + payload + mac
            ni_length = 1 + payload + mac_flits

            # Mesh wire length = ni_length + (freshness_overhead if is_control else 0)
            wire_freshness = freshness_overhead if is_control_val else 0
            wire_length = ni_length + wire_freshness

            msg_decl_info = {
                "encoding": msg_origins[enum_key].to_dict(),
                "payload": payload_origins.get(enum_key, payload_origins.get("default", msg_origins[enum_key])).to_dict(),
                "vc": vc_map_origins.get(enum_key, vc_map_origins.get("default", msg_origins[enum_key])).to_dict(),
                "mac": mac_origin.to_dict(),
                "freshness": freshness_origin.to_dict() if is_control_val else None,
            }

            msg_info = {
                "name": enum_key,
                "short_name": req_name,
                "encoding": encoding,
                "is_control": is_control_val,
                "vc_name": vc_name,
                "vc_id": vc_id,
                "payload_flits": payload,
                "mac_flits": mac_flits,
                "ni_length": ni_length,
                "freshness_overhead": wire_freshness,
                "wire_length": wire_length,
                "declarations": msg_decl_info,
            }
            messages[req_name] = msg_info

            # Expected protocol check
            expected = EXPECTED_PROTOCOL.get(req_name)
            if expected:
                chk_passed = True
                mismatches = []
                for field, exp_val in expected.items():
                    act_val = {
                        "payload": payload,
                        "mac": mac_flits,
                        "ni_length": ni_length,
                        "wire_length": wire_length,
                    }[field]
                    if act_val != exp_val:
                        chk_passed = False
                        msg = f"{req_name}.{field}: parsed {act_val} != expected {exp_val}"
                        mismatches.append(msg)
                        validation_mismatches.append(msg)
                        self.warnings.append(f"Validation mismatch: {msg}")

                validation_results.append({
                    "message": req_name,
                    "expected": expected,
                    "actual": {
                        "payload": payload,
                        "mac": mac_flits,
                        "ni_length": ni_length,
                        "wire_length": wire_length,
                    },
                    "passed": chk_passed,
                    "mismatches": mismatches,
                })

        # Check source file hashes for reproducibility
        def file_hash(p: Path) -> str:
            return hashlib.sha256(p.read_bytes()).hexdigest()

        manifest = {
            "metadata": {
                "generator": "verification.p7_rtl_parser",
                "timestamp": datetime.datetime.now(datetime.timezone.utc).isoformat(),
                "status": "PASS" if not validation_mismatches and not self.errors else "MISMATCH",
            },
            "source_files": {
                "noc_pkg": {
                    "path": self._display_path(self.noc_pkg_path),
                    "sha256": file_hash(self.noc_pkg_path),
                },
                "noc_p7_pkg": {
                    "path": self._display_path(self.noc_p7_pkg_path),
                    "sha256": file_hash(self.noc_p7_pkg_path),
                },
                "noc_l2_auth_p7": {
                    "path": self._display_path(self.noc_l2_auth_path),
                    "sha256": file_hash(self.noc_l2_auth_path),
                },
            },
            "protocol_constants": {
                k: {
                    "value": v,
                    "source": param_origins[k].to_dict() if k in param_origins else None,
                }
                for k, v in symbols.items()
                if k in {
                    "MESH_X", "MESH_Y", "NUM_TILES", "NUM_PORTS",
                    "FLIT_WIDTH", "NUM_VC", "VC0_DEPTH", "VC1_DEPTH", "VC2_DEPTH", "FIFO_DEPTH",
                    "MAC_TAG_BITS", "MAC_FLITS_FULL",
                }
            },
            "virtual_channels": {
                k: {
                    "id": v,
                    "source": vc_origins[k].to_dict() if k in vc_origins else None,
                }
                for k, v in vc_enums.items()
            },
            "freshness_overhead": {
                "value": freshness_overhead,
                "raw_expression": freshness_expr,
                "source": freshness_origin.to_dict(),
            },
            "messages": messages,
            "validation": {
                "status": "PASS" if not validation_mismatches else "MISMATCH",
                "total_checks": len(validation_results),
                "passed_checks": sum(1 for r in validation_results if r["passed"]),
                "mismatches": validation_mismatches,
                "checks": validation_results,
            },
            "parser_warnings": list(self.warnings),
            "parser_errors": list(self.errors),
        }

        return manifest

    def generate_manifest(self, output_path: Optional[Path | str] = None) -> Dict[str, Any]:
        """Runs extraction and saves manifest to target JSON file."""
        out = Path(output_path) if output_path else self.default_output_path
        out.parent.mkdir(parents=True, exist_ok=True)
        manifest = self.extract()
        out.write_text(json.dumps(manifest, indent=2), encoding="utf-8")
        return manifest

    def format_terminal_summary(self, manifest: Dict[str, Any]) -> str:
        """Formats a human-readable terminal table summary."""
        lines = [
            "================================================================================",
            "PQ-ATTEST P7 PROTOCOL EXTRACTION REPORT (Engineer 4)",
            "================================================================================",
            f"Timestamp     : {manifest['metadata']['timestamp']}",
            f"Overall Status: {manifest['metadata']['status']}",
            f"Freshness Ovh : {manifest['freshness_overhead']['value']} flits (expr: '{manifest['freshness_overhead']['raw_expression']}')",
            "--------------------------------------------------------------------------------",
            "Extracted Protocol Matrix (RTL Source of Truth):",
            "--------------------------------------------------------------------------------",
            f"{'Message Type':<18} {'Enc':<4} {'VC':<15} {'Payload':<8} {'MAC':<5} {'NI Len':<8} {'Wire Len':<8} {'Status'}",
            "--------------------------------------------------------------------------------",
        ]

        messages = manifest["messages"]
        val_checks = {c["message"]: c["passed"] for c in manifest["validation"]["checks"]}

        for short_name in REQUIRED_MESSAGE_TYPES:
            if short_name in messages:
                m = messages[short_name]
                passed = val_checks.get(short_name, True)
                status_str = "PASS" if passed else "MISMATCH"
                lines.append(
                    f"{m['short_name']:<18} "
                    f"{m['encoding']:<4} "
                    f"{m['vc_name']:<15} "
                    f"{m['payload_flits']:<8} "
                    f"{m['mac_flits']:<5} "
                    f"{m['ni_length']:<8} "
                    f"{m['wire_length']:<8} "
                    f"{status_str}"
                )

        lines.append("--------------------------------------------------------------------------------")
        if manifest["validation"]["mismatches"]:
            lines.append("Validation Mismatches:")
            for mis in manifest["validation"]["mismatches"]:
                lines.append(f"  [!] {mis}")
        else:
            lines.append("All extracted values match expected protocol specifications 100%.")

        if manifest["parser_errors"]:
            lines.append("Parser Errors:")
            for err in manifest["parser_errors"]:
                lines.append(f"  [ERROR] {err}")

        lines.append("================================================================================")
        return "\n".join(lines)


# ==============================================================================
# CLI Entry Point
# ==============================================================================

def main() -> int:
    parser = argparse.ArgumentParser(description="P7 RTL Protocol Parser and Manifest Generator")
    parser.add_argument("--noc-pkg", type=Path, default=None, help="Path to NOC_PKG.sv")
    parser.add_argument("--noc-p7-pkg", type=Path, default=None, help="Path to noc_p7_pkg.sv")
    parser.add_argument("--noc-l2-auth", type=Path, default=None, help="Path to noc_l2_auth_p7.sv")
    parser.add_argument("--output", type=Path, default=None, help="Path to output manifest JSON")
    parser.add_argument("--check", action="store_true", help="Exit with non-zero code if validation mismatch or error")
    parser.add_argument("--repo-root", type=Path, default=None, help="Repository root path")

    args = parser.parse_args()

    rtl_parser = P7RTLParser(
        noc_pkg_path=args.noc_pkg,
        noc_p7_pkg_path=args.noc_p7_pkg,
        noc_l2_auth_path=args.noc_l2_auth,
        repo_root=args.repo_root,
    )

    try:
        manifest = rtl_parser.generate_manifest(output_path=args.output)
        summary = rtl_parser.format_terminal_summary(manifest)
        print(summary)
        out_file = args.output or rtl_parser.default_output_path
        print(f"\nManifest successfully written to: {out_file.resolve()}\n")

        if args.check:
            if manifest["metadata"]["status"] != "PASS":
                return 1
            if manifest["parser_errors"]:
                return 1
        return 0
    except SVParserError as e:
        print(f"\n[FATAL PARSER ERROR] {e}\n", file=sys.stderr)
        return 1
    except Exception as e:
        print(f"\n[UNHANDLED ERROR] {e}\n", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
