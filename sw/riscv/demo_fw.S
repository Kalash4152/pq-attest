# demo_fw.S -- board demo firmware for both CPU tiles (takeover plan R3.2; Lane 1, 2026-11-07). Assembled with
# scripts/rv32_asm.py (RV32I only). One image for both tiles; the tile reads its TILE_ID from STATUS +0x10.
#
#   tile 3 (CPU A, attested): wait for STATUS AUTHORIZED, write 0xC0DE5A5A to the tile-2 memory at 0x2200_0100 over the
#            NoC, read it back, check it and that no bus fault was latched -> UART "T3 PASS" + LED 0001, else "T3 FAIL" + LED 1000.
#   tile 0 (CPU B, never authorized): try the same write and read; the bridge refuses locally, the load returns the
#            A3 poison 0xBADB_E00x -> UART "T0 REFUSED" + LED 0010, else "T0 FAIL" + LED 1000.
#
# Measured window (D2): the first 64 IMEM bytes are a fixed boot stub (jump to main at 0x40, the IRQ vector at 0x10,
# NOPs), so the approved measurement does not change when the application below 0x40 changes.
# Memory map: STATUS 0x1000_2000 (sw/riscv/status_regs.h), UART 0x1000_0000 (+0 data, +4 status: bit0 full, bit1 busy),
# GPIO 0x1000_1000 (+0 LEDs[3:0]). Interrupts stay masked (PicoRV32 resets irq_mask to all ones).

_start:     j main                  # 0x00
            .align_to 0x10
irq_vec:    j irq_vec               # 0x10 (IRQs masked; never taken)
            .align_to 0x40          # end of the 64-byte measured window

main:       li s0, 0x10002000       # STATUS
            li s1, 0x10000000       # UART
            li s2, 0x10001000       # GPIO
            li s3, 0x22000100       # tile-2 memory word (remote window)
            lw t0, 0x10(s0)         # TILE_ID
            li t1, 3
            beq t0, t1, cpu_a

cpu_b:      li t3, 0xB0B0B0B0
            sw t3, 0(s3)            # refused locally (not authorized) -> bus fault, no network traffic
            lw t4, 0(s3)            # refused -> poison 0xBADB_E00x
            li t5, 0xFFFFFFF0
            and t6, t4, t5
            li t5, 0xBADBE000
            bne t6, t5, b_fail
            la a0, s_refused
            call puts
            li t0, 2
            sw t0, 0(s2)
            j done
b_fail:     la a0, s_t0fail
            call puts
            li t0, 8
            sw t0, 0(s2)
            j done

cpu_a:      lw t0, 0(s0)            # wait for AUTHORIZED (CTRL bit 1)
            andi t0, t0, 2
            beqz t0, cpu_a
            li t3, 0xC0DE5A5A
            sw t3, 0(s3)
            lw t4, 0(s3)
            bne t4, t3, a_fail
            lw t0, 0(s0)            # no BUS_FAULT (CTRL bit 4)
            andi t0, t0, 16
            bnez t0, a_fail
            la a0, s_pass
            call puts
            li t0, 1
            sw t0, 0(s2)
            j done
a_fail:     la a0, s_t3fail
            call puts
            li t0, 8
            sw t0, 0(s2)

done:       j done

# puts: a0 = address of a zero-terminated string; clobbers t0, t1
puts:       lbu t0, 0(a0)
            beqz t0, puts_end
puts_wait:  lw t1, 4(s1)            # UART status bit 0 = FIFO full
            andi t1, t1, 1
            bnez t1, puts_wait
            sw t0, 0(s1)
            addi a0, a0, 1
            j puts
puts_end:   ret

s_pass:     .asciz "T3 PASS\n"
s_t3fail:   .asciz "T3 FAIL\n"
s_refused:  .asciz "T0 REFUSED\n"
s_t0fail:   .asciz "T0 FAIL\n"
