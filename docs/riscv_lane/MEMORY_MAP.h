/* ============================================================
 * MEMORY_MAP.h
 * PQ-Attest — RISC-V Processing Tile — shared memory map
 *
 * SHARED FILE: must match Person A's addr_decode.sv exactly.
 * Base addresses below come directly from SPEC_02 §C3 (frozen) —
 * these are NOT placeholders, do not change them.
 *
 * Sizes marked >>> PERSON-A DATA <<< are placeholders until
 * Person A reports real synthesized IMEM_KB/DMEM_KB numbers
 * (their Step 1/Step 2 gate). Update both here and in link.ld
 * together — they must never drift apart.
 * ============================================================ */

#ifndef MEMORY_MAP_H
#define MEMORY_MAP_H

/* ---- Local memory (BRAM) ---- */
#define IMEM_BASE       0x00000000u
#define IMEM_SIZE_KB    16          /* A7 (Lane 1 2026-11-07): RTL IMEM_WORDS = 4096 x 32 bit; decoder window 0x0000-0x3FFF */

#define DMEM_BASE       0x00004000u
#define DMEM_SIZE_KB    16          /* A7: RTL DMEM_WORDS = 4096 x 32 bit; decoder window 0x4000-0x7FFF */

/* ---- Local peripherals (fixed by SPEC_02, not Person-A-dependent) ---- */
#define UART_BASE           0x10000000u
#define UART_REG_DATA       (UART_BASE + 0x00)   /* write: send byte | read: unused */
#define UART_REG_STATUS     (UART_BASE + 0x04)   /* bit0 = busy */

#define GPIO_BASE            0x10001000u
#define GPIO_REG_LED         (GPIO_BASE + 0x00)  /* write: LEDs[3:0] */
#define GPIO_REG_SW          (GPIO_BASE + 0x04)  /* read: switches[3:0] */

/* STATUS block: register map moved to sw/riscv/status_regs.h (brief v2 B4, R-D4, 2026-11-06).
   The old map (BUILD_ID +0, STATUS +4 with tile_id[7:4], ATTEST_REQ +8) is gone from the RTL. */
#define TILE_STATUS_BASE          0x10002000u

/* ---- Remote (network) ---- */
#define REMOTE_BASE     0x20000000u

/* Everything else: unmapped -> bus error (tmem_err), per SPEC_02 §C3 */

#endif /* MEMORY_MAP_H */