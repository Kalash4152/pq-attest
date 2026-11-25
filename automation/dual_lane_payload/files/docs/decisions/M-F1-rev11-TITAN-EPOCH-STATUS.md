# M-F1 revision 11 draft — TITAN epoch and status

Date: 2026-11-21. Authority: **Signed Kalash Bheda 2026-11-21; Arnav signature pending**.

HARDWARE_VALIDATED=NO, SOC_INTEGRATION_COMPLETE=NO, FORMAL_PROOF=NO.

Source: 02_INTERFACES_v2.md from the TITAN handoff. Kalash approved D1–D8 and authorized S4 and S5 while Arnav's signature is pending. Stop on any written objection to a frozen field. S6 and S8 await the 6 December G0 decision. D9 still requires approval.

## Wire fields proposed for freeze

The 11-bit control field retains the existing 32-bit flit, message types, virtual channels, and one-bit NI-owned tag. The profile requires TXN_TAG_WIDTH=1. The limits, device, pins, clocks, L2 attestation protocol and revision-10 measurement stay as specified by the earlier approved revisions.

| Message | [10:7] | [6:1] | [0] |
|---|---|---|---|
| Memory write request | Byte strobes | Requester epoch in modes 4/5 | NI transaction tag |
| Memory read request | Zero | Requester epoch in modes 4/5 | NI transaction tag |
| Memory write/read response | [10] ERR, [9:7] STATUS | Request epoch echo in modes 4/5 | Echoed transaction tag |

Modes 0–3 keep the B0 epoch/echo value of zero. In modes 4 and 5, the hardware captures the request epoch and replaces the app-provided epoch bits. A stalled valid HEAD holds its first-valid stamp. Revocation can remove valid under the existing admission rule.

| ERR | STATUS | Meaning |
|---:|---|---|
| 0 | 000 | SUCCESS. Nonzero STATUS with ERR=0 is invalid. |
| 1 | 000 | ERROR. With zero echo this is exactly the existing 11'h400 OR tag. |
| 1 | 001 | DENIED_UNAUTH at the final decision. |
| 1 | 010 | DENIED_STALE at the final decision. |
| 1 | 011 | DENIED_HEAD when authorization was already low at HEAD arrival. |
| 1 | 100 | DENIED_FILTER, local only. |
| 1 | 101–111 | Reserved. |

Modes 0 (B0), 1 (B1 explicit denial), 2 (B2 global drain), 3 (B3 read filter), 4 (B4 epoch guard), and 5 (TITAN) retain the agreed numbering. Mode 4 keeps silent drop on failed guard. Explicit denial responses are proposed for modes 1 and 5 and the applicable B2 path. A generated response follows final request consumption and uses the existing message type, payload length and flow control. Error read data is zero.

## Timing and interfaces proposed for freeze

| Handoff | Producer → consumer | Observable rule |
|---|---|---|
| H1 | Authenticated gate → per-tile epoch tracker | D10 advances the six-bit effective epoch on a 0→1 transition of the gate's registered authorized output. Reset clears both. REVOKE, redundant REVOKE, a held-high re-GRANT, trusted fail and timeout do not advance it. |
| H2 | Epoch tracker/stamp → NI | Epoch is sourced from hardware. Capture at first valid and hold across backpressure. Keep the NI-owned tag. |
| H3 | Front-end request latch and gate → guard | Compare the snapshot with current epoch and authorization at last word. Deny on same-cycle REVOKE. Preserve the existing tile-4 RoT bypass. |
| H4 | Front end → response NI | A denying mode emits one definitive response after consuming the final word. Priority is unauthorized, stale, illegal address, success. Preserve existing packet lengths. |
| H5 | NI receive and local authorization/epoch → read filter → CPU bridge | On read-response HEAD, B3 checks authority and TITAN checks authority and echo. A rejected read is locally mapped to zero data plus DENIED_FILTER. Valid-only app RX; last/abort retires the response. |
| H6 | Bridge → software and verification | Outcome codes on the observation interface are SUCCESS=00, DENIED=01, ERROR=10, UNKNOWN=11. UNKNOWN is local and excluded from definitive-response uniqueness. D5 maps DENIED to bridge last_err_kind=6, CPU FAULT_CODE=6 and poison 0xBADBE006. Codes 1–5 retain their existing meanings. |
| H7 | NI, front end, gate, bridge → monitor | Passive observation only. Monitor counts cover transaction finality and latency. Full credit/slot conservation needs separate evidence. |

Defaults carried into the draft are D1 same-module-name file swap, D2 deny before address error, D3 global drain until no in-flight transactions, D4 no epoch bump on trusted fail/timeout, D6 latch the filter decision on HEAD, D7 six-bit epoch and D8 same-cycle deny. D9 remains approval before inserting a register stage. The modular wrap/signature condition still requires the planned handshake/wrap evidence.

## D5 decision and signatures

Kalash chose a single software-visible DENIED code, 6. The bridge field is three bits. The existing adapter passes through nonzero codes. Wire STATUS and the monitor retain the detailed reason where applicable. DENIED_FILTER remains local as specified in H5. The firmware header adds FAULT_DENIED 6u, with no firmware behavior change. The approved mapping is implemented in the bridge at S9.

The firmware audit found no range, ordering or switch classification of the fault code. Demo v2/v3 test exact legacy refusal values (code 2 and poison 0xBADBE002). Their hexadecimal conversion orders generic digit values only. The NI status acceptance firmware records register words without classifying them.

Kalash Bheda signed on 2026-11-21. Arnav signature pending. Authorized sequence: S4 → S5 → planned stop for G0.

## D10 amendment

Council review authorized by Kalash in chat 21 Nov; edge-only refinement approved by Kalash 21 Nov. Arnav signature pending.

The tracker observes the existing gate's registered authorized output. The effective epoch is visible in the first authorized cycle, including an immediately eligible request. When GRANT coincides with trusted_fail, the actual gate output decides: a rise from low advances once, while a gate output that stays high does not advance. REVOKE denies through authorization; a subsequent rise advances the epoch. A-WRAP remains X pending the receiving-gate proof of 63·T_GG > 8,192 (integer T_GG ≥ 131 cycles) and validation of the relevant lifetime.
