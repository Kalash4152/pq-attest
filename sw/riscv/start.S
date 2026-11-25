/* ============================================================
 * start.S — PQ-Attest RISC-V tile, SW2
 * Boots to main(): set sp, zero .bss, call main, spin/ebreak if
 * main ever returns (there is no OS to return to).
 * No Person-A-dependent values here — pure ABI/link-script glue.
 * ============================================================ */

    .section .text.start
    .global _start

_start:
    /* Set stack pointer from the symbol link.ld exports */
    la      sp, _stack_top

    /* Zero .bss: la a0=start, a1=end, loop storing zero word by word */
    la      a0, _bss_start
    la      a1, _bss_end
bss_zero_loop:
    bge     a0, a1, bss_zero_done
    sw      zero, 0(a0)
    addi    a0, a0, 4
    j       bss_zero_loop
bss_zero_done:

    call    main

    /* main() should never return on bare metal. If it does: trap. */
hang:
    ebreak
    j       hang
