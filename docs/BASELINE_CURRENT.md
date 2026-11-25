# Current baseline — Revision 4 I-1, 2026-10-08

Restored from intake HEAD `1e3141cda7bc7dccc28d6974016f7a418415e297`. No protected production RTL or accepted tb_ni_n81/tb_noc_n81 edit. Backups preserve the overwritten NI bench and foreign camera files.

| Path | Before SHA-256/state | After SHA-256/state | Recovery |
|---|---|---|---|
| NOC_PQATTEST.srcs/sim_1/new/ni_tb.sv | 0fd6080fb5069298407c74babf6a2b0eaac44cb07c9f3fb5202c366b1e9fd107 | 52f78041ecfa9bc586643e94f79552ef19dc1fcfee7e0319d05186c06f0908c6 | _recovery_backup\ni_tb_OVERWRITTEN_2026-10-02.sv.txt |
| docs/STATUS.md | DELETED | 2d42da65b5954c60c7c6a0ef445ff8690283fab9165d806c7c864599a795fad4 | HEAD restoration |
| docs/HANDOFF_2026-09-26.md | DELETED | df5572d1212a1535dc78e41188034d1d09bf9ef007daf4101370d5962291ee47 | HEAD restoration |
| docs/PQ_ATTEST_AI_HANDOFF_2026-10-01.md | DELETED | 43069c13e7d0ccabc614c79fc06a5ddf41e2b4922de22a527ebdd54ac599612f | HEAD restoration |
| docs/decisions/M-F1-interface-freeze.md | DELETED | c1bb98df4f56682b4a4c4bfaeb5b13cc4ae100b663678fd14ad9314da7140c25 | HEAD restoration |
| docs/decisions/N-8.1-ni-endpoint-containment.md | DELETED | 85c2f4f2e8cca08816ca057267fc0acf488005620a8d0b95a5d57b603a964752 | HEAD restoration |
| docs/decisions/7c-flow-control.md | DELETED | f38ffdae655a16384c964c6451c282ec8b457c1786162d4551014b40f189805e | HEAD restoration |
| README.md | 4c144dc1f3c2b912e5247576be235c545ae3feb8702ca92d3499e491230ff749 | MOVED | _recovery_backup\foreign\README.md |
| Run_M9_2.ps1 | 07456d416f17019db41ced3ee63fc01f194f6bdf2bf8af4d3fdae14c35a3833e | MOVED | _recovery_backup\foreign\Run_M9_2.ps1 |

N-6 width debt: tb6_1.sv CPU1 address uses scalar logic'(TILE_CPU1). TILE_CPU1 = 1, so its scalar value is still 1 and the exercised selector is unchanged. No baseline fix is needed for this fixture; a higher tile ID would truncate and needs a correctly sized package cast plus requalification. No test count or exercised address was changed.

Historical NI OOC / mesh reports remain preserved; complete source/build identity is not established, so fresh isolated jobs are prepared. Current protected-source comparisons and Python results are recorded in I-1 evidence; no new FPGA PASS is asserted.
