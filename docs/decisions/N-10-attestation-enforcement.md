# N-10 trusted authorization

The trusted gate surrounds the application request interface before the secure
NI. Protected memory request/response classes remain blocked after reset.
Authenticated challenge/response transport is allowed to avoid VC2 dependency.
Only an authenticated grant/revoke from RoT (coordinate index 4) may alter the
local authorization state. A MAC-valid worker grant is rejected by issuer policy.
Status 1 is required for grant. RoT's outstanding challenge record/independent
measurement whitelist governs whether it emits a grant; L2 freshness governs
replayed control packets. Revoke, failed attestation and challenge timeout block
data. A trusted new challenge can retry. Fault counters and reason are
observable; trusted clear is separate from worker app ports.

The gate checks operation classes explicitly, including memory responses.
The synthesizable integration must connect it at every untrusted app boundary;
testing an unattached gate does not establish integrated enforcement.
