# D2: peer receive path backpressure, deadlock-freedom argument (written before the RTL)

**Decision D2** (Kalash 2026-10-21; M-F1 R7.7a): in `noc_l2_auth_p7`, a control packet from the peer is never dropped for occupancy. While slot P is busy, a new peer HEAD is held at the wrapper's mesh input (`noc_rx_ready = 0`). The same hold already applies to a data HEAD during a slot-P replay (M-F1 R7.10).

This document argues two things: the hold cannot take part in a deadlock, and its duration is bounded. It is an argument, not a formal proof (FORMAL_PROOF = NO). The evidence is the tests in M-F1 R7.7a and the end-to-end bound in R7.5a.

## 1. What a hold blocks

- The wrapper's mesh input is the router's LOCAL output (eject FIFO, M-F1 §8–§9).
- A hold stalls that output. Flits behind the held HEAD wait in the eject FIFO and, through wormhole reservation, in upstream router buffers.
- Other outputs of the same routers are not locked by it, because the allocator locks per output port (M-F1 §10).

## 2. What releasing the hold depends on

The hold ends when slot P returns to P_FREE. From each busy state, slot P needs only the following.

| Slot-P state | Needs | Bound |
|---|---|---|
| collecting (I_PCOL) | the rest of the peer packet's flits | That packet is *ahead of* the held HEAD on the same link, so the hold does not block it. A stalled sender is ended by the ingress watchdog (R7.5a, W_ING). |
| P_PREP | nothing | 1 cycle |
| P_REQ, P_WAIT | the shared engine `l2_kmac_engine` | R7.6a: wait ≤ 269 (class P) or ≤ 792 (class Q); job ≤ J_MAX 128 |
| P_RDY | the NI receive port to be free of a data pass-through | That data packet is ahead of the held HEAD, so it completes. A stalled sender is ended by W_ING. |
| P_PLAY | the NI to accept up to 26 replay flits | The NI owns the packet and consumes it without depending on the tile (FD-1 rule 2). The subsystem ties `rx_ready = 1` at tiles 3 and 4. |

**None of these needs the wrapper's own TX path, the other wrapper's TX path, or any mesh output.**

- The engine is a separate resource. Each requester has at most one request outstanding (A1). A requester never holds an engine job while it waits for something else. So the engine has no hold-and-wait.
- A TX job finishes within J_MAX regardless of the mesh. The TX FSM waits for the mesh only after its engine job, in T_ISSUE and T_SEND, and holds no engine resource while it waits.

## 3. No wait cycle

A deadlock needs a cycle of waits. Every wait edge out of a held wrapper input goes to the engine or to the NI receive side. Both make progress without the mesh (sec. 2), so no cycle passes through a held input.

Consider the candidate cycle: tile-3 RX hold → tile-3 TX (RESPONSE) → mesh → tile-4 RX hold → tile-4 TX → mesh → tile-3 RX.
- It cannot close, because its first edge does not exist: tile-3 RX never waits on tile-3 TX.
- The endpoint consumes the delivered CHALLENGE through the NI, which never waits on the endpoint's TX (`rx_ready = 1`).
- The endpoint sends its RESPONSE later through the separate TX path.

## 4. Duration of a hold

Worst case: a peer HEAD arrives just after slot P is taken by the previous peer packet.

| Phase | Cycles |
|---|---|
| Collect | ≤ 26 + W_ING (sender stall) |
| Pre-check | 1 |
| Engine wait | ≤ 792 at tile 4 (class Q); ≤ 269 at tile 3 (class P) |
| Engine job | ≤ 128 |
| Replay start | ≤ W_ING + 4 |
| Replay | ≤ 26 |

That gives at most ≈ 1,100 cycles at tile 4 and ≈ 580 cycles at tile 3. The tile-3 figure (without the collect stall, which W_ING already bounds in the transport term) enters the R7.5a REVOKE bound as 429 cycles.

- **Steady state:** the RoT is single-outstanding per transaction, so at most one earlier peer packet is ahead of a REVOKE.
- **Held `revoke` input:** it produces a stream of REVOKEs. They are served in order, so the hold throttles the stream and nothing is lost.

## 5. Interaction with containment (FD-1, N-8.1)

The earlier containment results assumed that the L2 wrapper never backpressures (`noc_rx_ready = 1`). That no longer holds at tiles 3 and 4, so the assumption is requalified rather than inherited.

- The new hold is bounded (sec. 4), and the bound depends on no application-tile behaviour. FD-1's property ("tile-side backpressure must not propagate into the NoC indefinitely") is kept.
- Step d reruns the containment and perf/hop subset on the P7 subsystem (C1 test 2). Earlier evidence is not reused for it.
