# Dual-lane contract and decision packet

Prepared 2026-10-08. Kalash accepted the proposed offline profile in this chat:
"Approve the proposed offline profile; work through the L2/NI revision and
document it before implementation." OD-1/2/3/5/6 are accepted; OD-4's concrete
adapter revision is documented in N-9-l2-authentication.md before RTL. Live HEAD at
intake: `1e3141cda7bc7dccc28d6974016f7a418415e297`, branch
`noc/credit-integration`. The six original decision/status documents were locally
deleted at intake. Their Git contents are historical evidence; this change does
not restore or override those deletions.

## Decisions requiring Kalash's acceptance

**OD-1: Q-C + R-B (recommended).** A challenge contains seven little-endian
32-bit words: epoch bits 0–79, nonce bits 80–207, zero padding bits 208–223.
Its transport length is 8 / 12 flits in framing MAC-off/on mode, before a
separately approved freshness extension. A response contains sixteen words:
measurement bits 0–255 followed by tag bits 256–511. The trusted verifier
reconstructs the 56-bit tile ID, 80-bit epoch and 128-bit nonce from authenticated
source identity and its outstanding record. The internal controller response
remains 97 bytes / 776 bits. R-A requires 25 payload words and NI capacity
requalification; it is not a routine edit.

**OD-2: fixed-length errors (recommended).** Response success status = 1;
reject = 2; busy = 3; stale = 4; malformed = 5; tag failure = 6;
measurement failure = 7; identity failure = 8; epoch failure = 9;
internal failure = 10. Error responses retain sixteen payload words, all zero.
No non-success status may grant authorization. The loose protocol package's
table is an unaccepted candidate, not proof of this decision.

**OD-3: offline trust/provisioning profile (recommended).** Only trusted RoT
and the trusted CRYPTO boundary receive the demo root. Untrusted worker logic
does not receive it. One crypto endpoint is instantiated. Measured config/imem
bytes are offline inputs, not live processor-memory measurement. Coordinate
index `y*3+x` maps 0–5 to seven-byte ASCII IDs `TILE_00` … `TILE_05`.
Nonces are supplied by trusted RoT, unique per epoch/challenge, retired on
completion, timeout or reset; no response survives reset. Reset requires a new
externally provisioned boot epoch. Deterministic keys/nonces are demo-only.

**OD-4: L2 freshness and commit revision (proposal requiring detailed review).**
Use KMAC128 with 16 output bytes and a distinct `NOC-L2-AUTH-v1` domain.
Authenticate source, destination, message, VC, control, explicit length, payload,
boot epoch and a 64-bit per-directed-peer sequence. Do not repurpose header
bits or the one-bit transaction tag. Counter carriage needs an explicit wire
revision and NI length/commit changes. Receive quarantines must precede both
application delivery and memory-slot retirement. Counter advances commit only
after authentication; wrap refuses transmission until trusted epoch/key renewal.
This proposal is deliberately not implemented against M-F1 rev 5.

**OD-5: policy and consumption (recommended for offline profile).** One
outstanding challenge per target; second challenge is drained/rejected while
crypto or TX is busy. Trusted RoT alone issues challenge/grant/revoke and clears
fault state. Reset, timeout, failed measurement and revoke block protected
traffic. A fresh trusted challenge can retry after failure. Re-attestation detects
changes at its explicit trigger/interval, not instantaneously. FD-1 per-output
locks, 3 VCs, credits, allocator and router remain frozen. W=16 and 64 are test
profiles; production stall budget remains open.

**OD-6: N-8 matrix (recommended).** Preserve uniform, transpose, hotspot to
MEMORY and neighbor. Exact rectangular mappings and measurement definitions
are in `N-8-performance-plan.md`. This approval is distinct from finite-run
deadlock evidence and from production watchdog selection.

## Work that does not depend on these choices

Baseline/evidence audit; isolated guarded D7; full 776-bit internal Python
oracle and controller golden/mutation tests; four existing crypto/controller
OOC builds; current M-F1 performance/framing bench and reporting; automation
failure tests and installation protection. Acceptance of dependent packages
still follows the handoff dependency graph.

## Fixed build scope

Vivado/XSim 2024.1, `xc7a100tcsg324-1`, one clock domain, 20 ns.
No board programming, pin changes, production entropy claim or Lane-2 claim.
Explicit source lists exclude the zero-byte request/response placeholders and
the unaccepted loose package. GUI project state is preserved by child builds.
Source identity changes invalidate the affected gates. No unproven incremental
checkpoint is used. Timing failure is FAIL.

## Decision recording

Acceptance must identify the human instruction and exact selected fields in
`dual_lane_config.json`. Changing a proposal to accepted merely to make a job
run is forbidden. Pending decisions block only their dependent gates.
