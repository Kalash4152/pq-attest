# Revision 9 CPU software interface

Scope: the integrated CPU tiles at IDs 3 and 0. Addresses are byte addresses. The ten TMEM signals and NoC wire format are unchanged. C/GCC firmware is not required for the assembler-based release.

## Local map

| Range | Function |
|---|---|
| 0x00000000 through 0x00003fff | 16 KB IMEM, CPU data-bus writes refused |
| 0x00004000 through 0x00007fff | 16 KB DMEM |
| 0x10000000 page | UART MMIO |
| 0x10001000 page | GPIO MMIO |
| 0x10002000 page | STATUS below |
| 0x10003000 page | Read-only NI/bridge status below |
| 0x22000000 through 0x22003fff | Shared tile-2 memory, subject to bridge authorization and memory-side enforcement |

The bridge emits word-aligned remote addresses with byte-write enables. Adapter forwarding checks, bridge byte-lane checks and actual shared-memory checks are separate evidence layers. Unmapped or illegal local accesses complete with an error rather than hanging.

## STATUS at 0x10002000

| Offset | Read meaning | Write behavior |
|---|---|---|
| 0x00 | bit 0 reads zero; bit 1 AUTHORIZED; bit 2 GRANT_SEEN; bit 3 ATTEST_FAILED; bit 4 BUS_FAULT | Low-byte W1 bit 0 pulses local ATTEST_REQ; bits 2, 3, 4 are W1C |
| 0x04 | First fault address | Refused |
| 0x08 | First fault code in bits 3:0 | Refused |
| 0x0c | Build ID, 0x20261108 for the qualified v2 image | Refused |
| 0x10 | Tile ID, 3 or 0 | Refused |

A new event wins over a simultaneous W1C clear. The fault address/code remain the first latched fault until BUS_FAULT is cleared. CPU ATTEST_REQ can restart the local measurement reader but cannot initiate RoT verification or authorize a CPU. RoT/button-side requests own attestation initiation.

## NI status at 0x10003000

| Offset | Read meaning |
|---|---|
| 0x00 | Current last bridge error kind in low three bits; upper bits zero in the integrated wiring |
| 0x04 | 16-bit timeout counter, zero-extended |
| 0x08 | 16-bit refused counter, zero-extended |
| 0x0c | Profile version, 9 |

All writes and undefined offsets return a local error and have no register side effect. Counters are reset by reset, not by STATUS W1C; arithmetic is 16-bit wrapping, not promised saturation. NI last-kind and STATUS first-fault deliberately describe different observations.

Bridge kinds are 0 none, 1 decode, 2 refused, 3 remote/protocol/abort error, 4 timeout. The CPU adapter uses local fault code 5 for local errors; remote error code zero maps to 3. TMEM error data is zero with error asserted; CPU-visible error data is `0xBADBE000 | code`. Bus faults feed IRQ 3; handler entry also depends on CPU interrupt masking. The qualified v2 firmware unmasks this IRQ and returns through the tested handler.

## Measurement and reset

The qualified config is four little-endian words: tile 3, build ID 0x20261108, profile 9, zero reserved. Exactly 64 initial IMEM bytes are measured; the rest of the application is outside this measurement claim. NI_SLOT_TIMEOUT 8192 is forwarded to the NIs and both CPU bridges; BRIDGE_TIMEOUT is 4096 and late drain covers the NI timeout. Supported parameter guards and nondefault tests are recorded separately.

Shared and local RAM initialization/reset behavior is the FPGA contract, not an ASIC boot mechanism. The clock/reset and timing-exception review records the existing synchronization assumptions. Formal CDC/RDC and hardware validation remain NO.
