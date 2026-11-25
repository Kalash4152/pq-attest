/* status_regs.h -- STATUS block register map (brief v2 sec. B4, decision R-D4). Lane 1, 2026-11-06.
 * Single source of the named constants; must match rtl/riscv/tile_status.sv (tested by sim_riscv/tb_tile_status.sv).
 * Supersedes the TILE_STATUS_* definitions of docs/riscv_lane/MEMORY_MAP.h (old map). */
#ifndef STATUS_REGS_H
#define STATUS_REGS_H

#define STATUS_BASE            0x10002000u

#define STATUS_CTRL            (STATUS_BASE + 0x00u)
#define STATUS_FAULT_ADDR      (STATUS_BASE + 0x04u)   /* RO: first fault since BUS_FAULT was cleared */
#define STATUS_FAULT_CODE      (STATUS_BASE + 0x08u)   /* RO [3:0] */
#define STATUS_BUILD_ID        (STATUS_BASE + 0x0Cu)   /* RO */
#define STATUS_TILE_ID         (STATUS_BASE + 0x10u)   /* RO [3:0] (R-D4 addition) */

/* STATUS_CTRL bits */
#define STATUS_CTRL_ATTEST_REQ     (1u << 0)   /* W1: one-cycle attest_req pulse; reads 0 */
#define STATUS_CTRL_AUTHORIZED     (1u << 1)   /* RO */
#define STATUS_CTRL_GRANT_SEEN     (1u << 2)   /* RO sticky, W1C */
#define STATUS_CTRL_ATTEST_FAILED  (1u << 3)   /* RO sticky, W1C */
#define STATUS_CTRL_BUS_FAULT      (1u << 4)   /* RO sticky, W1C (A3) */

/* STATUS_FAULT_CODE values */
#define FAULT_DECODE         1u
#define FAULT_REFUSED        2u
#define FAULT_REMOTE_ERR     3u
#define FAULT_TIMEOUT        4u
#define FAULT_LOCAL_UNMAPPED 5u

/* A3: a faulting load returns BUS_POISON | code; bus faults raise PicoRV32 IRQ line BUS_ERR_IRQ */
#define BUS_POISON           0xBADBE000u
#define BUS_POISON_MASK      0xFFFFFFF0u
#define BUS_ERR_IRQ          3

#endif
