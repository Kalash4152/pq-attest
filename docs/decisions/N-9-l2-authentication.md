# N-9 explicit wire freshness and authenticated NI boundary

Implements the offline profile approved by Kalash on 2026-10-08. This is an
opt-in subsystem build; historical M-F1 rev-5 sources remain preserved. Its
explicit source list substitutes prepared Q-C package and NI-preview variants.

Secure packet layout: HEAD, five freshness BODY words, application payload,
four trailing MAC words (last = TAIL). Freshness bits 0–63 are a per-directed-
peer sequence, 64–143 are an externally provisioned 80-bit boot epoch,
144–159 must be zero. Header length includes these five extra words, and
maximum length is 26. Nothing is hidden in unused header/control bits.

Transcript bytes: wire HEAD word (4, little endian), VC (1), version 1 (1),
boot epoch (10), sequence (8), application payload (`4*n` bytes). The fixed
prefix is 24 bytes; maximum transcript is 88 bytes. KMAC128 outputs 16 bytes
with customization `NOC-L2-AUTH-v1`. It does not truncate a 256-bit KMAC.

TX buffers the app payload, obtains a combinational preview of the NI's actual
header including its selected memory transaction tag, computes the final MAC,
then issues the NI request with that tag. If a concurrent trusted response
changes the available memory slot and therefore the preview, TX recomputes
before acceptance. The NI preview variant adds an output only; its accepted
state transitions remain unchanged. A network adapter inserts freshness words
after HEAD. The router remains unchanged.

RX consumes the entire network packet into a 26-flit quarantine before KMAC.
It validates framing, source/destination/VC/type/length, epoch, sequence and MAC.
Only after authentication does it replay the original packet to the actual NI,
removing the explicit extension and correcting length. Thus NI application
delivery AND memory-slot retirement occur after authentication. The receiver
always consumes network traffic; while its verification/playback buffer is busy,
additional packets are drained/dropped and counted. No router lock is held for
multicycle KMAC. This bounded overload policy is observable, not reliable
unlimited buffering. The app driver limits outstanding transactions accordingly.

Per-peer sequence begins at 1. Receiver accepts strictly greater sequence values,
allowing explicitly accounted network/overload drops. Sequence state commits
only on authentication. Wrap refuses new transmission until epoch/key renewal.
Reset clears authorization and requires a NEW trusted external boot epoch;
reset with unchanged provisioning is outside the secure profile. Hardware
persistent epoch provisioning is a release prerequisite, not implemented entropy.

Trusted wrappers receive directed-peer demo keys. Untrusted worker app ports
receive neither those keys nor the root. Only trusted RoT and the selected
CRYPTO endpoint receive the demo root. One Stage-8 endpoint is used. Two L2
KMAC engines per wrapper are explicit; OOC/integrated builds must measure the
actual 12 authentication engines plus controller children. Resource or timing
failure remains a failed feasibility/closure gate; no assumed affordability.

Required controls separately bypass MAC, sequence, epoch and identity checks
in test-only builds. Production source defaults enforce every check. Dropped
packets must demonstrate zero NI delivery and zero trusted side effects.
