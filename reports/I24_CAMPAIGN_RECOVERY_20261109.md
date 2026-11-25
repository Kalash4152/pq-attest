# I24 campaign recovery and preserved attempts

This is a recovery record, not an acceptance gate. The frozen campaign requirement remains 1000 completed independent XSim seed processes, two existing acceptance conditions per seed, zero tool exit and a bounded bench finish. No failed or partial monolithic attempt is reclassified or imported.

Preserved history includes the compiler-banner check failure, Windows argument/path forwarding failure, the overall timeout after 626 completed seeds, and the later nonzero XSim exit after seed 457 printed PASS. A printed PASS does not override a failed process exit. Hardware logic and reference vectors were not changed for these recoveries.

The new registered layout has ten independently accepted 100-seed jobs followed by the original 1000-seed aggregate acceptance. The aggregate requires all ten jobs to be PASS_FRESH or identity-matched PASS_REUSED, rechecks every raw log and hash, checks identical source/tool provenance, and requires exactly ordered seed IDs 0 through 999. Failed jobs remain failed; only accepted complete chunks can be reused by the harness.

Each process now receives an explicit positive simulator seed, `sv_seed = bench_seed + 1`. The bench prints observed grant/response delay draws; the aggregate checks the 1 through 100 cycle range, correspondence to raw logs, and actual stream variation. This distinguishes simulator RNG initialization from the bench's seed label. The separate mixed-operation test in the next increment covers operation classes; this fetch-oriented latency campaign is not claimed to cover every memory operation.

A single fresh retry is permitted only when a nonzero tool exit follows a fully completed, otherwise valid PASS log. The failed shutdown attempt is recorded separately and never accepted. The retry must itself exit zero and pass all original checks. A bench failure, missing finish or timeout is terminal and is not retried by this rule. Synthetic controls test successful retry, no retry after a failed bench, no retry after timeout, and refusal after a second shutdown failure.

Before the new registry was generated, the harness unit suite passed 148 tests. It passed again afterward; preflight passed 226 guarded files and 595 source lists. The new shard controls pass 19 synthetic checks, in addition to the original 12 campaign controls and the version, command, delay and power-lifetime controls. New job ranges and markers were frozen before their first native run. All affected regression jobs must be accepted under the new registry identity.

Automatic sleep is temporarily inhibited during this authorized workflow; the display timeout is unchanged. The hold is released at completion or a hard stop, with a maximum lifetime. No hardware validation, formal proof, final FPGA result or I24 PASS is claimed by this record.

HARDWARE_VALIDATED=NO, SOC_INTEGRATION_COMPLETE=NO, FORMAL_PROOF=NO.
