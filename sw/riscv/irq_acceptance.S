# Dedicated real-core A3 acceptance program. Not the board image.
_start: j main
        .align_to 0x10
irq_vector: j handler
        .align_to 0x40
main:   li t0, -9
        .word 0x0602800B       # PicoRV32 maskirq x0,x5: enable only IRQ3
        li s0, 0x22000100
        li s1, 0x4000
        li s2, 0x55
fault:  lw a0, 0(s0)           # bench substitutes store or local-unmapped address
next:   sw a0, 0(s1)           # must NOT retire before handler entry
done:   j done
        .align_to 0x100
handler: li t1, 0x600D0001
        sw t1, 4(s1)
park:   j park
