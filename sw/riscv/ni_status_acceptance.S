_start: j main
        .align_to 0x40
main:   li s0,0x22000100
        sw zero,0(s0)
        lw t0,0(s0)
        li s1,0x10003000
        li s2,0x4000
        lw t0,0(s1)
        sw t0,0(s2)
        lw t0,4(s1)
        sw t0,4(s2)
        lw t0,8(s1)
        sw t0,8(s2)
        lw t0,12(s1)
        sw t0,12(s2)
        sw zero,12(s1)
        lw t0,12(s1)
        sw t0,16(s2)
        lw t0,16(s1)
        sw t0,20(s2)
        li t0,0x600D0009
        sw t0,24(s2)
done:   j done
