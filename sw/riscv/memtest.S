# memtest.S -- A7 memory test for one CPU tile (Lane 1, 2026-11-07; assembled by scripts/rv32_asm.py, RV32I).
# Every naturally aligned access size on DMEM: bytes at offsets 0..3 (sb / lb / lbu), halfwords at offsets 0 and 2
# (sh / lh / lhu), words (sw / lw), sign extension, byte-lane composition, and a write/read walk over every DMEM word
# 0x4004..0x7FFC (pattern addr ^ 0x5A5A5A5A). Misaligned accesses are excluded: PicoRV32 traps on them (CATCH_MISALIGN).
# Result word at 0x4000: 0x600D0000 | last test id (17) on PASS, 0xBAD00000 | failing test id on FAIL. LEDs 0001 / 1000.

_start:     j main
            .align_to 0x40
main:       li s0, 0x4000           # result word
            li s1, 0x4100           # scratch word
            li s2, 0x10001000       # GPIO
            li a1, 1                # T1 word write / read
            li t0, 0x11223344
            sw t0, 0(s1)
            lw t1, 0(s1)
            bne t0, t1, fail
            li a1, 2                # T2..T5 byte writes at offsets 0..3
            li t0, 0xA1
            sb t0, 0(s1)
            li a1, 3
            li t0, 0xB2
            sb t0, 1(s1)
            li a1, 4
            li t0, 0xC3
            sb t0, 2(s1)
            li a1, 5
            li t0, 0xD4
            sb t0, 3(s1)
            li a1, 6                # T6 byte lanes compose little-endian
            lw t1, 0(s1)
            li t0, 0xD4C3B2A1
            bne t0, t1, fail
            li a1, 7                # T7..T10 lbu at offsets 0..3
            lbu t1, 0(s1)
            li t0, 0xA1
            bne t0, t1, fail
            li a1, 8
            lbu t1, 1(s1)
            li t0, 0xB2
            bne t0, t1, fail
            li a1, 9
            lbu t1, 2(s1)
            li t0, 0xC3
            bne t0, t1, fail
            li a1, 10
            lbu t1, 3(s1)
            li t0, 0xD4
            bne t0, t1, fail
            li a1, 11               # T11 lb sign-extends 0xD4
            lb t1, 3(s1)
            li t0, -44
            bne t0, t1, fail
            li a1, 12               # T12 halfword writes at offsets 0 and 2
            li t0, 0x8001
            sh t0, 0(s1)
            li t0, 0x7FFE
            sh t0, 2(s1)
            lw t1, 0(s1)
            li t0, 0x7FFE8001
            bne t0, t1, fail
            li a1, 13               # T13 lhu offset 0
            lhu t1, 0(s1)
            li t0, 0x8001
            bne t0, t1, fail
            li a1, 14               # T14 lh offset 0 sign-extends
            lh t1, 0(s1)
            li t0, 0xFFFF8001
            bne t0, t1, fail
            li a1, 15               # T15 lhu offset 2
            lhu t1, 2(s1)
            li t0, 0x7FFE
            bne t0, t1, fail
            li a1, 16               # T16 lb positive byte (0x01) stays positive
            lb t1, 0(s1)
            li t0, 1
            bne t0, t1, fail
            li a1, 17               # T17 walk every DMEM word 0x4004..0x7FFC
            li t2, 0x4004
            li t3, 0x8000
            li t4, 0x5A5A5A5A
walk_w:     xor t0, t2, t4
            sw t0, 0(t2)
            addi t2, t2, 4
            bne t2, t3, walk_w
            li t2, 0x4004
walk_r:     lw t1, 0(t2)
            xor t0, t2, t4
            bne t0, t1, fail
            addi t2, t2, 4
            bne t2, t3, walk_r
pass:       li t0, 0x600D0000
            or t0, t0, a1
            sw t0, 0(s0)
            li t0, 1
            sw t0, 0(s2)
            j done
fail:       li t0, 0xBAD00000
            or t0, t0, a1
            sw t0, 0(s0)
            li t0, 8
            sw t0, 0(s2)
done:       j done
