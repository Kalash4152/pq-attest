#!/usr/bin/env python3
"""
PQ-Attest P7 Verification - F3: Centralized Path Resolution

Every Engineer 4 verification module resolves repository, data and output
locations through this module instead of building its own fixed paths.

Three locations are configurable
================================

repo root   Directory that holds ``verification/`` (code under test), the P7 RTL
            sources (``rtl/dual_lane/``) and the rev-5 RTL sources
            (``NOC_PQATTEST.srcs/sources_1/new/``).
data dir    Directory that holds external evidence and reference inputs.
out dir     Directory that receives generated artifacts and regression results.

Resolution precedence (first match wins)
========================================

repo root   1. explicit argument (``--repo-root``)
            2. environment variable ``P7_REPO_ROOT``
            3. discovery from this file's location (``<this file>/../..``)
            The current working directory is NEVER consulted.

data dir    1. explicit argument (``--data-dir``)
            2. environment variable ``P7_DATA_DIR``
            3. the repo root itself (the in-repository layout)
            No packaged-data location exists today; none is searched.

out dir     1. explicit argument (``--out``)
            2. environment variable ``P7_OUT_DIR``
            3. ``<repo root>/verification/generated`` (historical default)

Relative paths supplied explicitly are resolved against the caller's working
directory (normal CLI semantics) and then made absolute.  Defaults are never
cwd-relative.

External data-directory contract (``<data dir>/...``)
=====================================================

    software/pq_attest_final/PQ_Attest/software/   authoritative teammate reference
        kmac128_ref.py, keccak_ref.py (+ companions)
    software/kmac128_ref.py                          demoted reference (hash-distinctness check)
    software/noc_pair_matrix.json                    rev-5 pair matrix       (legacy P0-P4 tests)
    software/noc_traffic_vectors.json                rev-5 traffic vectors   (legacy P0-P4 tests)
    software/integration_scenarios.json              rev-5 scenarios         (legacy P0-P4 tests)
    logs/s3_kmac_2026-09-23.log                      registered KMAC simulation log
    E4_P7_XSIM_20261103/                             registered release XSim evidence
    reports/E4_P7_STEP*_REPORT.md, E4_P7_STEP8_FINAL_HANDOFF.md   protected historical reports
    PQ_Attest_S4_Evidence/                           S4 evidence package (S4 baseline and its tests)

Repo-root contract (``<repo root>/...``)
========================================

    verification/                                    code, tests and baseline generated artifacts
    rtl/dual_lane/*.sv                               P7 RTL (source of truth)
    NOC_PQATTEST.srcs/sources_1/new/NOC_PKG.sv, NOC_XY_ROUTING.sv   rev-5 RTL

The module only reads these locations; it never writes to repo root or data dir
except through the out dir.
"""

from __future__ import annotations

import contextlib
import os
from dataclasses import dataclass, replace
from pathlib import Path
from typing import Dict, Iterator, List, Mapping, Optional, Sequence, Union

PathLike = Union[str, "os.PathLike[str]"]

ENV_REPO_ROOT = "P7_REPO_ROOT"
ENV_DATA_DIR = "P7_DATA_DIR"
ENV_OUT_DIR = "P7_OUT_DIR"
#: Set by the portability tests for nested runs so the suite never recurses.
ENV_NESTED_GUARD = "P7_PORTABILITY_NESTED"

DEFAULT_GENERATED_REL = Path("verification") / "generated"
RTL_DUAL_LANE_REL = Path("rtl") / "dual_lane"
REV5_RTL_REL = Path("NOC_PQATTEST.srcs") / "sources_1" / "new"
XSIM_EVIDENCE_NAME = "E4_P7_XSIM_20261103"
S4_EVIDENCE_NAME = "PQ_Attest_S4_Evidence"
KMAC_LOG_NAME = "s3_kmac_2026-09-23.log"
REFERENCE_REL = Path("software") / "pq_attest_final" / "PQ_Attest" / "software"
S4_REFERENCE_REL = Path(S4_EVIDENCE_NAME) / "02_sources" / REFERENCE_REL


class PathConfigError(Exception):
    """Invalid path configuration (bad repo root, bad data dir, ...)."""


class MissingInputError(PathConfigError, FileNotFoundError):
    """A required external input is absent.  The message names the expected locations."""


# ==============================================================================
# Resolution helpers
# ==============================================================================

def _absolute(value: PathLike, cwd: Optional[Path] = None) -> Path:
    """Expand ``~``, anchor relative paths at ``cwd`` and normalize."""
    p = Path(os.path.expanduser(os.fspath(value)))
    if not p.is_absolute():
        p = (Path(cwd) if cwd is not None else Path.cwd()) / p
    return Path(os.path.normpath(p)).resolve()


def discover_repo_root() -> Path:
    """Repository root derived from this file's location (cwd independent)."""
    return Path(__file__).resolve().parents[1]


def validate_repo_root(path: PathLike) -> Path:
    """Return the absolute repo root or raise ``PathConfigError``.

    A repository root must contain ``verification/p7_regression.py``.
    """
    root = Path(path).resolve()
    if not root.is_dir():
        raise PathConfigError(f"Repository root is not a directory: {root}")
    marker = root / "verification" / "p7_regression.py"
    if not marker.is_file():
        raise PathConfigError(
            f"Not a PQ-Attest repository root: {root} "
            f"(expected {Path('verification') / 'p7_regression.py'} below it)"
        )
    return root


@dataclass(frozen=True)
class P7Paths:
    """Immutable, injectable path configuration."""

    repo_root: Path
    data_dir: Path
    out_dir: Path

    # ---- construction ------------------------------------------------------
    @classmethod
    def from_root(
        cls,
        repo_root: PathLike,
        data_dir: Optional[PathLike] = None,
        out_dir: Optional[PathLike] = None,
    ) -> "P7Paths":
        """Non-validating factory (backward-compatible ``workspace_root`` semantics).

        ``data_dir`` defaults to the root, ``out_dir`` to ``<root>/verification/generated``.
        """
        root = Path(repo_root).resolve()
        return cls(
            repo_root=root,
            data_dir=Path(data_dir).resolve() if data_dir is not None else root,
            out_dir=Path(out_dir).resolve() if out_dir is not None else root / DEFAULT_GENERATED_REL,
        )

    def with_out(self, out_dir: PathLike) -> "P7Paths":
        return replace(self, out_dir=Path(out_dir).resolve())

    # ---- repo-root locations ----------------------------------------------
    @property
    def verification_dir(self) -> Path:
        return self.repo_root / "verification"

    @property
    def tests_dir(self) -> Path:
        return self.verification_dir / "tests"

    @property
    def baseline_generated_dir(self) -> Path:
        """Committed generated artifacts inside the repository."""
        return self.repo_root / DEFAULT_GENERATED_REL

    @property
    def rtl_dir(self) -> Path:
        return self.repo_root / RTL_DUAL_LANE_REL

    @property
    def rev5_rtl_dir(self) -> Path:
        return self.repo_root / REV5_RTL_REL

    # ---- out-dir locations ------------------------------------------------
    @property
    def generated_dir(self) -> Path:
        return self.out_dir

    @property
    def is_default_out(self) -> bool:
        return self.out_dir == self.baseline_generated_dir

    # ---- data-dir locations -----------------------------------------------
    @property
    def software_dir(self) -> Path:
        return self.data_dir / "software"

    @property
    def logs_dir(self) -> Path:
        return self.data_dir / "logs"

    @property
    def reports_dir(self) -> Path:
        return self.data_dir / "reports"

    @property
    def xsim_evidence_dir(self) -> Path:
        return self.data_dir / XSIM_EVIDENCE_NAME

    @property
    def s4_evidence_dir(self) -> Path:
        return self.data_dir / S4_EVIDENCE_NAME

    @property
    def kmac_log(self) -> Path:
        return self.logs_dir / KMAC_LOG_NAME

    @property
    def reference_dir_candidates(self) -> List[Path]:
        """Where the authoritative teammate reference may live, in priority order."""
        return [self.data_dir / REFERENCE_REL, self.data_dir / S4_REFERENCE_REL]

    @property
    def demoted_kmac_reference(self) -> Path:
        return self.software_dir / "kmac128_ref.py"

    # ---- portable rendering -----------------------------------------------
    def portable(self, path: PathLike) -> str:
        """POSIX string without machine-specific prefixes.

        Paths under the repo root become repo-relative; under the data dir
        ``$DATA/<rel>`` (when data dir differs from the repo root); under the out
        dir ``$OUT/<rel>``.  Anything else is returned as its file name only.
        """
        p = Path(path)
        if not p.is_absolute():
            return p.as_posix()
        p = p.resolve()
        for base, prefix in (
            (self.out_dir, "$OUT/" if not self.is_default_out else None),
            (self.repo_root, ""),
            (self.data_dir, "$DATA/"),
        ):
            if prefix is None:
                continue
            try:
                return prefix + p.relative_to(base).as_posix()
            except ValueError:
                continue
        return p.name

    # ---- validation -------------------------------------------------------
    def require_file(self, path: PathLike, description: str, expected: Optional[Sequence[PathLike]] = None) -> Path:
        p = Path(path)
        if not p.is_file():
            raise MissingInputError(self._missing_message(p, description, expected))
        return p

    def require_dir(self, path: PathLike, description: str, expected: Optional[Sequence[PathLike]] = None) -> Path:
        p = Path(path)
        if not p.is_dir():
            raise MissingInputError(self._missing_message(p, description, expected))
        return p

    def _missing_message(self, p: Path, description: str, expected: Optional[Sequence[PathLike]]) -> str:
        locs = [str(Path(e)) for e in (expected if expected else [p])]
        return (
            f"Required input missing: {description}. "
            f"Expected at: {' or '.join(locs)}. "
            f"Data directory in use: {self.data_dir} "
            f"(repo root: {self.repo_root}). "
            f"Supply a complete layout with --data-dir / --repo-root "
            f"(or {ENV_DATA_DIR} / {ENV_REPO_ROOT})."
        )

    # ---- subprocess propagation -------------------------------------------
    def env_overrides(self) -> Dict[str, str]:
        return {
            ENV_REPO_ROOT: str(self.repo_root),
            ENV_DATA_DIR: str(self.data_dir),
            ENV_OUT_DIR: str(self.out_dir),
        }

    def subprocess_env(self, base: Optional[Mapping[str, str]] = None) -> Dict[str, str]:
        env = dict(base if base is not None else os.environ)
        env.update(self.env_overrides())
        return env


# ==============================================================================
# Public resolvers
# ==============================================================================

def resolve_paths(
    repo_root: Optional[PathLike] = None,
    data_dir: Optional[PathLike] = None,
    out_dir: Optional[PathLike] = None,
    env: Optional[Mapping[str, str]] = None,
    cwd: Optional[PathLike] = None,
) -> P7Paths:
    """Resolve a validated :class:`P7Paths` using the documented precedence.

    ``env`` defaults to ``os.environ``; pass ``{}`` to ignore the environment.
    ``cwd`` anchors explicitly supplied relative paths (default: process cwd).
    """
    environment = os.environ if env is None else env
    base = Path(cwd) if cwd is not None else None

    if repo_root is not None:
        root = _absolute(repo_root, base)
    elif environment.get(ENV_REPO_ROOT):
        root = _absolute(environment[ENV_REPO_ROOT], base)
    else:
        root = discover_repo_root()
    root = validate_repo_root(root)

    if data_dir is not None:
        data = _absolute(data_dir, base)
        explicit_data = True
    elif environment.get(ENV_DATA_DIR):
        data = _absolute(environment[ENV_DATA_DIR], base)
        explicit_data = True
    else:
        data = root
        explicit_data = False
    if explicit_data and not data.is_dir():
        raise PathConfigError(
            f"Data directory does not exist or is not a directory: {data} "
            f"(from {'--data-dir' if data_dir is not None else ENV_DATA_DIR})"
        )

    if out_dir is not None:
        out = _absolute(out_dir, base)
    elif environment.get(ENV_OUT_DIR):
        out = _absolute(environment[ENV_OUT_DIR], base)
    else:
        out = root / DEFAULT_GENERATED_REL

    return P7Paths(repo_root=root, data_dir=data, out_dir=out)


def get_default_paths() -> P7Paths:
    """Paths for the current process: environment overrides, else discovery."""
    return resolve_paths()


@contextlib.contextmanager
def injected_environ(paths: P7Paths) -> Iterator[P7Paths]:
    """Temporarily export ``paths`` through the environment (restored on exit)."""
    saved = {k: os.environ.get(k) for k in paths.env_overrides()}
    os.environ.update(paths.env_overrides())
    try:
        yield paths
    finally:
        for k, v in saved.items():
            if v is None:
                os.environ.pop(k, None)
            else:
                os.environ[k] = v

