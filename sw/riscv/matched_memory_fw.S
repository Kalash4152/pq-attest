# Matched secure/fixed-admission experiment only. Same measured first 64 bytes as firmware v2.
_start: j main
        .align_to 0x10
irq_vector: j handler
        .align_to 0x40
main:   li s0,0x4000
        li s1,0x22000100
        li s2,32
        li s3,0x10001000
        li s4,0
        li s5,1000000
wait_start: lw t0,4(s0)
        bnez t0,loop
        addi s5,s5,-1
        bnez s5,wait_start
        j failed
loop:   addi s4,s4,1
        sw s4,0(s1)
        lw t0,0(s1)
        bne t0,s4,failed
        addi s1,s1,4
        bltu s4,s2,loop
        sw s4,0(s0)
        li t0,1
        sw t0,0(s3)
park:   j park
failed: li t0,8
        sw t0,0(s3)
        j park
        .align_to 0x234
handler: j failed
