# branch.s : every branch condition taken and not taken (including equal and
# extreme operands), a backward loop, branches on just-loaded and just-computed
# values, JAL forward and backward, JALR with an offset, a jump table and
# nested calls.
#
# Result at ECALL: a0 = 0 on pass, otherwise a0 = number of the failing check.
# Assemble in RARS with Settings > Memory Configuration > "Compact, Text at Address 0".

        .text
main:
        # 1: BEQ / BNE
        li    gp, 1
        li    t0, 5
        li    t1, 5
        li    t2, 6
        beq   t0, t2, fail
        bne   t0, t1, fail
        beq   t0, t1, b1_a
        j     fail
b1_a:   bne   t0, t2, b1_b
        j     fail
b1_b:

        # 2: BLT / BGE with the most negative and most positive values
        li    gp, 2
        li    t0, 0x80000000
        li    t1, 0x7FFFFFFF
        bge   t0, t1, fail
        blt   t1, t0, fail
        blt   t0, t1, b2_a
        j     fail
b2_a:   bge   t1, t0, b2_b
        j     fail
b2_b:   bge   t0, t0, b2_c
        j     fail
b2_c:   blt   t0, t0, fail

        # 3: BLTU / BGEU, same operands compared as unsigned
        li    gp, 3
        bltu  t1, t0, b3_a
        j     fail
b3_a:   bgeu  t1, t0, fail
        bgeu  t0, t1, b3_b
        j     fail
b3_b:   bltu  t0, zero, fail
        bgeu  t0, zero, b3_c
        j     fail
b3_c:

        # 4: backward branch loop, sum 10 + 9 + ... + 1 = 55
        li    gp, 4
        li    t0, 0
        li    t1, 10
b4_loop:
        add   t0, t0, t1
        addi  t1, t1, -1
        bnez  t1, b4_loop
        li    t2, 55
        bne   t0, t2, fail

        # 5: branch on a value loaded by the previous instruction
        li    gp, 5
        li    s1, 0x2000
        li    t0, 7
        sw    t0, 0(s1)
        lw    t1, 0(s1)
        bne   t1, t0, fail
        lw    t1, 0(s1)
        beq   t1, t0, b5_a
        j     fail
b5_a:

        # 6: branch on a value computed by the previous instruction
        li    gp, 6
        addi  t0, zero, 3
        addi  t0, t0, -3
        bnez  t0, fail

        # 7: JAL link value, forward call and backward call
        li    gp, 7
        jal   ra, b7_fwd
b7_ret: j     b7_after
b7_back:
        addi  t5, t5, 1
        ret
b7_fwd: la    t0, b7_ret
        bne   ra, t0, fail
        mv    s0, ra
        li    t5, 0
        jal   ra, b7_back
        li    t1, 1
        bne   t5, t1, fail
        mv    ra, s0
        ret
b7_after:

        # 8: JALR with an offset and rd = x0
        li    gp, 8
        la    t0, b8_base
        jalr  zero, t0, 8
b8_base:
        j     fail
        j     fail
        nop

        # 9: jump table through JALR
        li    gp, 9
        la    t0, b9_table
        li    t1, 2
        slli  t1, t1, 2
        add   t0, t0, t1
        jalr  ra, t0, 0
        j     b9_check
b9_table:
        j     b9_e0
        j     b9_e1
        j     b9_e2
b9_e0:  li    t2, 10
        ret
b9_e1:  li    t2, 11
        ret
b9_e2:  li    t2, 12
        ret
b9_check:
        li    t3, 12
        bne   t2, t3, fail

        # 10: calls nested three levels deep
        li    gp, 10
        li    t0, 0
        jal   ra, b10_f1
        li    t1, 111
        bne   t0, t1, fail
        j     pass
b10_f1: mv    s2, ra
        addi  t0, t0, 1
        jal   ra, b10_f2
        mv    ra, s2
        ret
b10_f2: mv    s3, ra
        addi  t0, t0, 10
        jal   ra, b10_f3
        mv    ra, s3
        ret
b10_f3: addi  t0, t0, 100
        ret

pass:
        li    a0, 0
        j     done
fail:
        mv    a0, gp
done:
        li    a7, 10
        ecall
