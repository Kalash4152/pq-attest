# I-1.5 clean-clone identity check — 2026-10-19

Clone: `C:\npqc_79d184d` (commit `79d184d`, `core.longpaths=true`, system `core.autocrlf=true`).
Scripts: scratchpad `clonecheck.py`, `eolcat.py`. Nothing was re-hashed or fixed.

## Result: MISMATCH → stop (no track merged)

| Check | Result |
|---|---|
| Accepted-run repo sources (fresh + reused manifests) | 53 match, **3 differ**: `NOC_DATAPTAH.sv`, `NOC_XY_ROUTING.sv`, `synth/n25_mesh.xdc` |
| Accepted-run evidence artifacts | 868 match, 0 differ; 29 binaries intentionally not committed |
| All 4147 tracked files, clone bytes vs main working bytes | **66 differ**: 65 line-ending only, 1 content (`NOC_PQATTEST.xpr`, the known uncommitted local edit) |

## Cause of the 65 EOL-only differences

| Group | Count | Caused by I-1.5? | Mechanism |
|---|---|---|---|
| Pre-existing | 37 | No | Attributes unchanged since `a896c89`. 15 `sources_1` .sv files (incl. protected `NOC_DATAPTAH`, `NOC_XY_ROUTING`, `SHA3_*`, `kmac_*`, `pq_kdf*`) are CRLF in the main tree but `*.sv eol=lf` checks them out LF. `n25_mesh.xdc`, `golden/*.txt`, `*.memh`, `mut/*`, etc. are LF in main but checkout CRLF via `core.autocrlf=true`. |
| **Regression from I-1.5** | **28** | **Yes** | `logs/.gitattributes` `* -text` turned 26 previously-tracked legacy `logs/*.log` (CRLF in main, LF blobs) into raw LF checkouts; before, `*.log text`+autocrlf gave CRLF = main. `*.json text eol=lf` did the same to `rtl/dual_lane/variant_provenance.json` and `_recovery_backup/I1_RESTORATION_2026-10-08.json`. None is an accepted-run source. |

## Further findings

- **MAX_PATH:** a clone under the default temp path fails checkout ("Filename too long") on committed evidence paths. Clones need `core.longpaths=true` and a short root.
- **Identity digests embed absolute paths** (`dual_lane.py` `snapshot()` keys are absolute). A clone at another path can match file hashes but can never reproduce a job identity, so `PASS_REUSED` is impossible outside `C:\vivado_verilog_proj\NOC_PQATTEST`.
- The 3 accepted-source mismatches are pre-existing and depend on the cloning machine's `core.autocrlf`; the recorded hashes are of CRLF working copies whose committed form is LF.

## Second clone after the narrowed fix (`e8739db`, Kalash approved fix 1 and L-5)

Rules: `logs/.gitattributes` = `wp0_*/** -text`; root `*.json eol=lf` narrowed to `vectors/*.json` and
`automation/**/*.json`. Clones: `C:\npqc_e8739db` (HEAD) and baseline `C:\npqc_a896c89` (pre-I-1.5).

| Check | Result |
|---|---|
| Accepted-run sources | 53/56 match; the same 3 pre-existing mismatches (L-5) |
| Accepted-run artifacts | 868/868 match |
| Files tracked at `a896c89` that differ clone vs working tree | **91** at HEAD vs **127** at `a896c89` |
| Newly differing at HEAD (present at HEAD, absent at `a896c89`) | **0** |
| Content (non-EOL) differences | 1: `NOC_PQATTEST.xpr`, uncommitted local edit |
| New files differing | 2: `.gitattributes`, `logs/.gitattributes` (written LF, autocrlf checks out CRLF; not hashed by any job) |

The first clone's 28-file regression is gone. The legacy `logs/` set is mixed CRLF/LF on disk, so
no per-extension rule can match all of it; under the restored `*.log text` rule, these logs behave exactly as
they did at `a896c89`.

Checkout bytes still differ from `a896c89` for 26 previously tracked n25 report files under `reports/`
(`* -text`). All 26 now **equal** the working tree (they were in the old mismatch set). Revert
`reports/.gitattributes` only if you want the pre-I-1.5 behaviour back.

`eol=lf` on files that are already `-text` (payload copies, `*.ps1`) is inert: none of their checkout bytes changed.

## Proposed fixes (fix 1 applied in `e8739db`; 2 recorded as L-5; 3 open)

1. Revert the 28 regressions by narrowing my rules: `logs/.gitattributes` → `wp0_*/** -text` only; `*.json eol=lf` → `vectors/*.json` and `automation/**/*.json` only. Re-verify with a second clean clone.
2. Pre-existing 37 (decision): either (a) LF-normalize the CRLF working copies (changes 15 protected hashes → requalify every affected job), or (b) define release identity on LF-normalized content in `dual_lane_verify.sha`, or (c) accept working-tree-only reproducibility and record it as limitation L-5.
3. Make identities path-relative (repo-relative keys) before I-8 release.
