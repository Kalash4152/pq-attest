# M F1 revision 9 RTL closure

Date: 2026-11-08. Authority: Kalash approved the A–F final roadmap and its proposed decisions in chat before dependent implementation. Additive to signed revision 8; historical contracts and evidence are retained.

## Frozen release decisions

1. RoT/button-only attestation initiation. CPU ATTEST_REQ does not initiate verifier work. Its local measurement-reader effect must be documented/tested; it does not grant authority.
2. Config is 16 little-endian bytes: word 0 = tile identity (3), word 1 = CPU_BUILD_ID, word 2 = closure profile version (9), word 3 = zero reserved. This replaces demo bytes 00..0f only for the new closure profile; generate new provisioned values and new vectors from the pinned software reference, never edit historical vectors. Measurement remains exactly 64 IMEM bytes.
3. Original A3 acceptance remains required: real-core remote-read/write/local-unmapped error IRQ handling and RVFI ordering. Stock PicoRV32 is protected from edits. Test the current mechanism before firmware depends on it. A demonstrated architectural conflict triggers the project hard stop; no weaker substitute is silently accepted.
4. First fault address/code remains sticky until BUS_FAULT W1C; set wins over simultaneous clear. TMEM error data is zero with err asserted; the CPU adapter converts it to BADBE000 | code. Attestation error payload semantics are unchanged.
5. NI status MMIO window 0x10003000..0x10003fff: read-only word offsets +0x00 last bridge error kind [2:0], +0x04 timeout count [15:0], +0x08 refused count [15:0], +0x0c profile version 9. Undefined offsets/writes error, no side effects. Additional internal status wires may be added to tile_top/decoder; the ten TMEM signals and external packet formats remain unchanged.
6. Debug address means last accepted instruction-fetch address, not retired PC or arbitrary data address. RVFI is the retirement evidence.
7. Firmware v2 uses the in-repository assembler, bounded authorization/UART waits, PASS/FAIL-first UART output, active post-revoke access and defined cycle observations. IRQ handler code must not be placed inside the measured boot stub unless new provisioning explicitly accounts for it. C/GCC installation is not needed.
8. Forward the configured NI_SLOT_TIMEOUT to both CPU tiles and bridges. Supported timeout must fit the existing 16-bit NI age counter and late drain must cover it. Validate boundaries without changing signed default values 4096/8192.

## Boundaries retained

Part xc7a100tcsg324-1, single 20 ns design clock, existing board pins and clock/reset architecture, authorization F4/Q2 rules, wire/message formats, MAC/freshness/VC rules, protected originals and pinned reference remain unchanged. Shared memory 16 KB, each CPU IMEM/DMEM 16 KB. Signed merged ceiling 52,000 LUT and subsystem stop 47,550 remain distinct; stricter existing registered gates are not loosened silently.

Revocation correctness is measured from authorization-low at the enforcement point under the signed propagation bound, not instantaneous cancellation at raw button input. Write commit and read-response suppression are checked separately.

## Milestones and evidence

I-18 first qualifies the real CPU IRQ/retirement behavior before dependent RTL/firmware work. Later logical groups cover RTL/firmware, merged adversarial cases, final regression, release automation/implementation, matched research measurements and reproducible packaging. New jobs freeze counts before their first run. Each increment gets a gate report and commit. No registry/identity changes during an active batch.

Final completion requires the approved scope, all mandatory registered checks or explicitly approved deviations, final full FPGA gate and source/image provenance, reproducible documentation/package, and owner-supplied exact-image board observations. Until then SOC_INTEGRATION_COMPLETE=NO. Agent hardware validation and formal proof remain NO. ASIC/GDS part G and optional extensions H are not authorized by this work package.
