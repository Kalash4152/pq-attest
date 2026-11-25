_start: j main
        .align_to 0x10
irq_vector: j handler
        .align_to 0x40
main:   li s0,0x10002000
        li s1,0x4000
        li s2,0x22000100
        li s3,0x10001000
        li s4,0
        li s5,1000000
wait_auth: lw t0,0(s0)
        andi t0,t0,2
        bnez t0,loop
        addi s5,s5,-1
        bnez s5,wait_auth
        j failed
loop:   lw t0,4(s1)
        bnez t0,done
        addi s4,s4,1
        sw s4,0(s2)
        lw t0,0(s2)
        bne t0,s4,failed
        sw s4,0(s1)
        j loop
done:   li t0,1
        sw t0,0(s3)
park:   j park
failed: li t0,8
        sw t0,0(s3)
        j park
        .align_to 0x234
handler: j failed
