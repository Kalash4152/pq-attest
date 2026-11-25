/* ============================================================
 * hello.c — SW3
 * Prints "Tile N, build 0xXXXXXXXX" over UART, reading both
 * values from tile_status.sv (fixed offsets, SPEC_02 §C3 —
 * not Person-A-dependent; these registers exist regardless
 * of IMEM/DMEM size).
 * ============================================================ */

#include "print.h"
#include "status_regs.h"   /* B4 map (2026-11-06); MEMORY_MAP.h lives in docs/riscv_lane */

#define REG32(addr) (*(volatile uint32_t *)(addr))

int main(void)
{
    uint32_t build_id = REG32(STATUS_BUILD_ID);
    uint32_t tile_id_r = REG32(STATUS_TILE_ID);
    uint32_t tile_id    = tile_id_r & 0xF;

    print_str("Tile ");
    print_int((int32_t)tile_id);
    print_str(", build ");
    print_hex(build_id);
    print_str("\n");

    while (1) { /* spin forever, per build-order Step 5 exit criterion */ }
    return 0;
}
