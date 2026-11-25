/* ============================================================
 * link.ld
 * PQ-Attest RISC-V tile — bare-metal linker script
 *
 * >>> PERSON-A DATA <<<
 * LENGTH values below (8K/8K) are PLACEHOLDERS matching the
 * default in MEMORY_MAP.h. Do NOT trust these for real hardware
 * runs — get Person A's actual synthesized IMEM_KB/DMEM_KB
 * (their Step 1/2 gate) and update BOTH this file and
 * MEMORY_MAP.h together, or .text/.data can silently overflow
 * into unmapped space.
 * ============================================================ */

MEMORY
{
    /* >>> PERSON-A DATA <<< placeholder sizes, confirm before real build */
    IMEM (rx)  : ORIGIN = 0x00000000, LENGTH = 16K   /* A7 (Lane 1 2026-11-07): matches RTL IMEM_WORDS = 4096 */
    DMEM (rwx) : ORIGIN = 0x00004000, LENGTH = 16K   /* A7: matches RTL DMEM_WORDS = 4096 */
}

ENTRY(_start)

SECTIONS
{
    .text : {
        *(.text.start)   /* _start must land first */
        *(.text*)
        *(.rodata*)
    } > IMEM

    .data : {
        _data_start = .;
        *(.data*)
        _data_end = .;
    } > DMEM

    .bss : {
        _bss_start = .;
        *(.bss*)
        *(COMMON)
        _bss_end = .;
    } > DMEM

    /* Stack grows down from the top of DMEM. */
    _stack_top = ORIGIN(DMEM) + LENGTH(DMEM);
}
