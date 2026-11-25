# S8.2 endpoint

Approved offline Q-C/R-B profile, one trusted CRYPTO endpoint at coordinate
(0,1), cryptographic ID TILE_03. Actual controller synchronous active-low reset
is `!rst` in the same clock domain. Only authenticated RoT challenges reach
this parser. Seven words, zero upper padding, complete final payload and valid
length are required before crypto start. Reply-to is latched at HEAD.

RX always consumes. An independent parser drains wrong-type/wrong-issuer,
aborted, malformed or busy packets and records them. Busy challenges receive
no queued response; the issuer's bounded timeout retires the rejected request.
The existing outstanding request/response remains intact. TX request and each
word remain stable through backpressure. Status follows OD-2 / R4 K-2 (M-F1 rev 6
§R6.3): 4 bits in tx_control[10:7]; 1 success, 2 reject, 3 busy, 4 stale,
5 malformed, 6 tag, 7 measurement, 8 identity, 9 epoch, 10 internal. Every
error response keeps sixteen payload words, all zero. The endpoint emits only
the codes it can detect: 2, 3, 5 and 10 (besides 1); 4 and 6-9 are verifier
verdicts. Correction 2026-10-19: this document previously said "all errors use
status 10"; that was the unqualified prepared RTL, not the accepted decision.
The prepared RTL still emits only 1/10 (pq_attest_endpoint.sv:87), which is open
conflict C-1 in M-F1-rev6-conflicts.md, to be resolved in PQ-2.
Successful response uses byte offsets 33 and 65 from all 776 bits.
Reset cancels parser/controller/TX state and pending replies.

Tests must check valid oracle bytes, every abort boundary, malformed padding,
wrong issuer/type/length, busy drain, TX stalls, reset states and independent
word-offset/reply-to/busy-drain controls. An endpoint result alone is functional
framing evidence; secure acceptance requires the N-9 boundary.
