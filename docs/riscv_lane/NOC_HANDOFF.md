# NoC Handoff — Gate 5

## 1. Frozen CPU/Tile Boundary

The tile exposes exactly these 10 TMEM signals:

### Request
- tmem_req_o
- tmem_we_o
- tmem_addr_o[31:0]
- tmem_wdata_o[31:0]
- tmem_wstrb_o[3:0]
- tmem_is_fetch_o

### Response
- tmem_gnt_i
- tmem_rvalid_i
- tmem_rdata_i[31:0]
- tmem_err_i

This interface is frozen. The CPU, PicoRV32 adapter, and tile_top must not be modified for NoC integration.

## 2. Request Semantics

A request is presented with:

- tmem_req_o = 1
- address = tmem_addr_o
- write enable = tmem_we_o
- write data = tmem_wdata_o
- byte enables = tmem_wstrb_o
- instruction/data indication = tmem_is_fetch_o

Address, write enable, write data, and byte strobes remain stable until grant.

The requester allows grant in the same cycle or a later cycle.

## 3. Response Semantics

After a request is granted:

- tmem_rvalid_i indicates completion.
- tmem_rdata_i contains read data.
- tmem_err_i indicates an error.

Response latency is not fixed.

There is at most one outstanding transaction.

Each accepted request receives exactly one response.

## 4. Remote Address Format

Remote addresses use:

[31:28] = 4'h2
[27:24] = destination tile ID
[23:0]  = offset

For processor-tile remote memory:

- remote target is DMEM
- offset must be within the processor tile DMEM window
- accesses must be word aligned
- A[1:0] must equal 2'b00

## 5. Remote Read Request

MEM_RD_REQ:

- word 0 = full 32-bit address
- wstrb = 0

The destination returns exactly one MEM_RD_RESP.

MEM_RD_RESP:

- word 0 = RDATA
- control[10] = error

## 6. Remote Write Request

MEM_WR_REQ:

- word 0 = full 32-bit address
- word 1 = WDATA
- control[10:7] = WSTRB

The destination returns exactly one MEM_WR_RESP.

MEM_WR_RESP:

- control[10] = error

## 7. Byte-Lane Convention

Little-endian byte lanes:

- wstrb[0] -> wdata[7:0]
- wstrb[1] -> wdata[15:8]
- wstrb[2] -> wdata[23:16]
- wstrb[3] -> wdata[31:24]

## 8. Error Semantics

An error is generated for:

- wrong remote region
- wrong destination tile
- misaligned address
- offset outside the target memory window

On a read error:

- returned data = 0

On a write error:

- destination memory is unchanged

Every accepted request, including an erroneous request, receives exactly one response.

## 9. Integration Rule

The NoC integration layer shall translate between:

    tile_top TMEM interface
            ↕
    Lane-1 NoC packet interface

The NoC internals are not modified.

The translation layer owns packet construction, packet decoding, request routing, and response generation.

## 10. Verification Requirement

Before Gate 5 is closed, deterministic vectors must verify:

1. local/non-remote transaction is not sent to the NoC
2. remote read request
3. remote write request
4. byte strobes
5. correct destination tile ID
6. response data
7. response error
8. misaligned address error
9. out-of-range error
10. one response per accepted request
11. delayed grant
12. delayed response
13. no request-field changes while waiting for grant

## 11. Ownership

CPU/Memory side owns:

- PicoRV32
- adapter
- tile_top
- local memories
- TMEM boundary
- TMEM verification

NoC side owns:

- packet transport
- routing
- packet-level request/response handling
- NoC integration

The TMEM interface above is the frozen handoff boundary.