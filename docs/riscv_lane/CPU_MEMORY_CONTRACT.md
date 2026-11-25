# CPU / Memory Contract — Frozen

## 1. CPU Configuration

CPU:
- PicoRV32
- RV32IMC configuration
- COMPRESSED_ISA = 1
- ENABLE_MUL = 1

The upstream `rtl/picorv32.v` is not modified.

## 2. Local Memory Map

| Region | Address Range |
|---|---|
| IMEM | 0x00000000 – 0x00003FFF |
| DMEM | 0x00004000 – 0x00007FFF |
| UART | 0x10000000 – 0x10000FFF |
| GPIO | 0x10001000 – 0x10001FFF |
| STATUS | 0x10002000 – 0x10002FFF |
| NI | 0x10003000 – 0x10003FFF |

IMEM size: 16 KB  
DMEM size: 16 KB

## 3. Local CPU Memory Transaction

CPU request:
- `mem_valid`
- `mem_instr`
- `mem_addr`
- `mem_wdata`
- `mem_wstrb`

Write:
- `mem_wstrb != 0`

Read:
- `mem_wstrb == 0`

The adapter holds the transaction information stable until the transaction is granted.

## 4. TMEM Interface

Exactly 10 signals:

### Requester → responder

- `tmem_req`
- `tmem_we`
- `tmem_addr[31:0]`
- `tmem_wdata[31:0]`
- `tmem_wstrb[3:0]`
- `tmem_is_fetch`

### Responder → requester

- `tmem_gnt`
- `tmem_rvalid`
- `tmem_rdata[31:0]`
- `tmem_err`

## 5. TMEM Protocol

1. Address, write-enable, write-data and byte strobes remain stable until grant.
2. Grant may occur in the same cycle as the request or later.
3. Response occurs one or more cycles after grant.
4. Exactly one response corresponds to each granted transaction.
5. Transactions remain ordered.
6. Only one transaction may be outstanding at a time for the current adapter.
7. No fixed response latency may be assumed.
8. Read errors return `0`.
9. Write errors do not modify memory.

## 6. WSTRB

Little-endian byte lanes:

- `wstrb[0]` → bits `[7:0]`
- `wstrb[1]` → bits `[15:8]`
- `wstrb[2]` → bits `[23:16]`
- `wstrb[3]` → bits `[31:24]`

`wstrb = 4'b0000` is a legal no-op write for the remote memory interface.

## 7. Remote Memory Addressing

Remote addresses use:

- `addr[31:28] = 4'h2`
- `addr[27:24]` = tile selector
- `addr[23:0]` = offset

For the memory tile:

- Tile ID = `2`
- Valid base = `0x22000000`
- Processor local DMEM corresponds to the remote memory window.

`addr[1:0]` must be `00`.

## 8. Remote Memory Errors

An access produces `err = 1` when:

- offset is outside the configured memory window
- address is misaligned
- region is invalid
- tile ID is invalid

On an error:
- read data = `0`
- write must not modify memory

Every accepted request receives exactly one response, including errors.

## 9. Reset

Reset places transaction state into an idle state and clears response/handshake state.

No transaction may be duplicated because of reset.

## 10. Verification Status Before Gate 1

Already completed:

- TMEM conformance: 1000/1000 PASS
- Randomized 1–100 cycle latency: 1000/1000 PASS
- Memory-tile functional tests: PASS
- Two-tile + memory-tile integration: PASS

These tests are retained as evidence and will not be unnecessarily repeated.