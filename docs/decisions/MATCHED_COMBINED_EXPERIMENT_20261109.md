# Matched combined-system experiment

Status: preparation only; no measured results or acceptance implied.

Compare the production secure subsystem against a separately named fixed-admission ablation. The latter statically permits tile 3, retains the same two CPU tiles, 16 KB local memories, 16 KB shared memory, NI transaction handling, packet mesh, 20 ns clock and physical constraints, and removes attestation/L2 authentication/revocation. Tile 0 remains refused in both. This isolates the implemented security machinery under the declared admission workload; it is not a production security mode or a globally open network.

Use the same `matched_memory_fw` on CPU A in both simulations. Its measured 64-byte boot region equals the qualified v2 boot region. Initialize DMEM words 0 and 1 to zero in both benches. After secure attestation completes and background traffic drains, release DMEM word 1 as the start flag; use the same pre-workload condition in the ablation. CPU A performs 32 sequential write/read pairs at shared addresses 0x22000100 through 0x2200017c, checks returned data, records 32 completed pairs, then parks with GPIO 1. CPU B uses the same bounded refused program in both.

Record each TMEM acceptance cycle, response cycle, operation, address, returned data and error, then derive latency from the raw cycle records. Require exactly 64 requests/responses, 32 commits, all 32 final words, GPIO success and no CPU fault. Do not include initial attestation/setup duration in steady-state memory latency; report setup separately. Never infer power, maximum frequency, ASIC area or statistical performance beyond the measured workload.

Physical area comparison uses the same wrapper, firmware, pins, tool version, mesh-split flow and implementation directives. Retain source manifests and full utilization/timing/gate reports independently. The ablation must never overwrite the secure release image or be selected by the main project's default build command. Publish absolute secure/baseline numbers and the explicit denominator for every difference.
