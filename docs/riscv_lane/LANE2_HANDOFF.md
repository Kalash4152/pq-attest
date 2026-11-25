# Lane 2 — Processor Tile Hardware Handoff

## 1. Processor Tile

The processor tile uses PicoRV32 with:

- COMPRESSED_ISA = 1
- ENABLE_MUL = 1

The tile is parameterized by:

- TILE_ID
- BUILD_ID
- IMEM_WORDS
- DMEM_WORDS
- HAS_UART

The tile exposes the processor-local memory interfaces and the TMEM interface.

---

## 2. Local Memory Map

| Region | Address Range | Size |
|---|---:|---:|
| IMEM | 0x00000000–0x00003FFF | 16 KB |
| DMEM | 0x00004000–0x00007FFF | 16 KB |
| UART | 0x10000000–0x10000FFF | 4 KB |
| GPIO | 0x10001000–0x10001FFF | 4 KB |
| STATUS | 0x10002000–0x10002FFF | 4 KB |
| Network/TMEM | 0x20000000–0x2FFFFFFF | Remote tiles |

---

## 3. TMEM Interface

The TMEM interface contains exactly 10 signals.

### Request side

- tmem_req
- tmem_we
- tmem_addr[31:0]
- tmem_wdata[31:0]
- tmem_wstrb[3:0]
- tmem_is_fetch

### Response/handshake side

- tmem_gnt
- tmem_rvalid
- tmem_rdata[31:0]
- tmem_err

Protocol:

- Address, write data, write strobes and control remain stable until grant.
- Grant may occur immediately or after multiple cycles.
- Response occurs one or more cycles after grant.
- One response is generated for every accepted transaction.
- Transactions remain ordered.
- One transaction may be outstanding at a time.

---

## 4. Remote Memory Address Format

Remote addresses use:

    [31:28] = 4'h2
    [27:24] = tile selector
    [23:0]  = byte offset

For example:

    Tile 0 = 0x20000000
    Tile 1 = 0x21000000
    Tile 2 = 0x22000000

The current memory_tile test target is Tile 2.

---

## 5. Memory Tile

`memory_tile.sv` is parameterized by:

- TILE_ID
- MEM_WORDS
- INIT_FILE

Current test configuration:

    TILE_ID   = 4'h2
    MEM_WORDS = 4096

Therefore:

    Memory size = 4096 × 4 = 16 KB

Valid Tile 2 addresses begin at:

    0x22000000

and extend through the configured memory window.

---

## 6. Memory Tile Behavior

Supported:

- word reads
- word writes
- byte write strobes
- zero write strobe no-op
- word-aligned accesses

Errors are generated for:

- misaligned accesses
- out-of-range accesses
- wrong tile ID
- non-remote addresses

Error reads return:

    0x00000000

---

## 7. Verification Completed

### TMEM conformance

    Transactions completed = 1000
    TMEM grants            = 1000
    TMEM responses         = 1000
    Stability errors       = 0
    Fetch flag errors      = 0
    Response errors        = 0
    Protocol errors        = 0

Result:

    PASS

### Random latency

Grant and response latency:

    1–100 cycles

Acceptance test:

    1000 randomized seeds
    Errors = 0

Result:

    PASS

### Memory tile

Verified:

- full-word write/read
- second memory location
- byte write strobes
- zero write strobe
- misaligned access error
- out-of-range error
- wrong tile error
- non-remote address error

Result:

    PASS
    Errors = 0

### Two-tile integration

Verified:

- two PicoRV32 tile instances
- independent tile parameters
- both CPUs execute
- no CPU traps
- TMEM write to Tile 2
- TMEM read from Tile 2
- readback data = 0xCAFEBABE

Result:

    PASS

---

## 8. Files Relevant to Hardware

Core hardware:

    rtl/picorv32.v
    rtl/picorv32_adapter.sv
    rtl/tile_top.sv
    rtl/addr_decode.sv
    rtl/tile_mem_wrapper.sv
    rtl/mem_bram.sv
    rtl/memory_tile.sv

Verification:

    rtl/tb_conformance.sv
    rtl/tb_random_latency.sv
    rtl/tb_memory_tile.sv
    rtl/tb_tile_top.sv
    rtl/tb_two_tiles.sv

---

## 9. Current Status

Completed:

    Step 1  — LED bring-up
    Step 2  — PicoRV32 integration/synthesis
    Step 3  — core + BRAM simulation
    Step 4  — toolchain/program execution
    Step 5  — UART
    Step 6  — adapter/address decoder
    Step 7  — parameterized tile/status/GPIO
    Step 8  — random latency acceptance
    Step 10 — memory_tile

Remaining:

    Step 9  — handoff/documentation
    Step 11 — traffic generator

---

## 10. Freeze Point

The following interfaces should not be changed without updating the
corresponding testbenches and handoff documentation:

- PicoRV32 adapter interface
- TMEM 10-signal interface
- local memory map
- remote address format
- memory_tile request/response behavior