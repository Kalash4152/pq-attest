# Proposal A: expected-diagnostic allow-list for assertion-tripping mutants (NOT implemented; awaiting Kalash)

**Status: APPROVED by Kalash 2026-10-21 ("Proposal A: approved with the listed constraints") and implemented in `scripts/dual_lane_verify.py` (`strip_expected_diag`, `diagnostic_scan`) with the unit tests below (`ExpectedDiagTests`).**

## Problem

Some mutants are meant to break an RTL contract that the RTL itself checks procedurally (`$error`):
- `ks_excl_mut_tag_during_kdf` (B-3);
- the planned step-c A1/A2/A3 mutants.

Their kill is correct: RESULT FAIL with the targeted oracle line. Example, run `010513`: `[FAIL] KSHARE_EXCLUSIVE violations=40`, normal end.

The judge still marks them INVALID. Its diagnostic scan (`dual_lane_verify.py`:129-131) rejects every `Error:`/assertion line, and these mutants **necessarily** produce the RTL's own check lines.

## Proposed rule (narrow; same pattern as the N-6 precedent `adjudicate_n6_mutant`)

1. New optional job field `expected_diag`: a list of **exact full-line regexes**, anchored `^…$`, one per expected diagnostic line.
2. It is allowed **only on mutant jobs** (`job['mutant']` set). The registry generator refuses it on any other job.
3. Before the diagnostic scan, the judge removes lines that fully match one of the listed regexes, from the simulate log only.
4. **Each** listed regex must match **at least once.** A missing expected line makes the job INVALID: the mutant did not exercise the contract as declared.
5. **Any other** `Error:` / `Fatal:` / assertion-failure / `TB_TIMEOUT` line still makes the job INVALID.
6. The kill rule is unchanged: RESULT FAIL, the targeted oracle line present, no timeout or fatal.
7. Registry-level: `expected_diag` is part of the job dict, and therefore of the job identity, and is frozen before the job's first run like a count.

## First use

`ks_excl_mut_tag_during_kdf`:

```
expected_diag = [
  r'^Error: pq_kmac_share: start while the shared kmac128 is busy$',
  r'^Error: pq_attestation_tag: kmac start asserted while kmac128 busy$',
]
```

## Unit tests required with the implementation (`scripts/test_dual_lane.py`)

| Test | Expected verdict |
|---|---|
| a mutant log with only the expected lines + RESULT FAIL + oracle | accepted (KILLED) |
| the same plus one unexpected `Error:` line | INVALID |
| the same with one expected line missing | INVALID |
| `expected_diag` on a non-mutant job | the generator refuses it |
| a regex that is not anchored `^…$` | the generator refuses it |
| an expected line that is only a substring of a longer line | not stripped, so INVALID |

## Decision needed

Kalash: approve, amend or reject. Until then, every such mutant is recorded as "killed by targeted check, judge-INVALID (expected RTL diagnostics), pending proposal A", and **never counted as accepted**.
