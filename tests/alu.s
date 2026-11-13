# alu.s : every RV32I register-register and register-immediate ALU instruction,
# with edge values (overflow wrap, immediate limits, sign extension, shift
# amounts above 31, signed vs unsigned compares).
#
# Result at ECALL: a0 = 0 on pass, otherwise a0 = number of the failing check.
# Assemble in RARS with Settings > Memory Configuration > "Compact, Text at Address 0".

        .text
main:
        # 1: ADD wraps on signed overflow
        li    gp, 1
        li    t0, 0x7FFFFFFF
        li    t1, 1
        add   t2, t0, t1
        li    t3, 0x80000000
        bne   t2, t3, fail

        # 2: SUB wraps the other way
        li    gp, 2
        sub   t2, t3, t1
        bne   t2, t0, fail

        # 3: negating the most negative number gives itself
        li    gp, 3
        sub   t2, zero, t3
        bne   t2, t3, fail

        # 4: mixed-sign add
        li    gp, 4
        li    t0, -5
        li    t1, 7
        add   t2, t0, t1
        li    t3, 2
        bne   t2, t3, fail

        # 5: ADDI immediate limits
        li    gp, 5
        addi  t2, zero, 2047
        li    t3, 2047
        bne   t2, t3, fail
        addi  t2, zero, -2048
        li    t3, -2048
        bne   t2, t3, fail

        # 6: AND / OR / XOR
        li    gp, 6
        li    t0, 0xF0F0F0F0
        li    t1, 0x0FF00FF0
        and   t2, t0, t1
        li    t3, 0x00F000F0
        bne   t2, t3, fail
        or    t2, t0, t1
        li    t3, 0xFFF0FFF0
        bne   t2, t3, fail
        xor   t2, t0, t1
        li    t3, 0xFF00FF00
        bne   t2, t3, fail

        # 7: ANDI / ORI / XORI with sign-extended immediates
        li    gp, 7
        li    t0, 0x12345678
        andi  t2, t0, -16
        li    t3, 0x12345670
        bne   t2, t3, fail
        ori   t2, t0, 0x7FF
        li    t3, 0x123457FF
        bne   t2, t3, fail
        xori  t2, t0, -1
        li    t3, 0xEDCBA987
        bne   t2, t3, fail

        # 8: register shifts use only rs2[4:0]
        li    gp, 8
        li    t0, 1
        li    t1, 31
        sll   t2, t0, t1
        li    t3, 0x80000000
        bne   t2, t3, fail
        li    t1, 33
        sll   t2, t0, t1
        li    t3, 2
        bne   t2, t3, fail
        li    t0, 0x80000000
        li    t1, 31
        srl   t2, t0, t1
        li    t3, 1
        bne   t2, t3, fail
        sra   t2, t0, t1
        li    t3, -1
        bne   t2, t3, fail
        sra   t2, t0, zero
        bne   t2, t0, fail

        # 9: immediate shifts
        li    gp, 9
        li    t0, 0x87654321
        slli  t2, t0, 4
        li    t3, 0x76543210
        bne   t2, t3, fail
        srli  t2, t0, 4
        li    t3, 0x08765432
        bne   t2, t3, fail
        srai  t2, t0, 4
        li    t3, 0xF8765432
        bne   t2, t3, fail
        srai  t2, t0, 31
        li    t3, -1
        bne   t2, t3, fail

        # 10: SLT / SLTU
        li    gp, 10
        li    t0, -1
        li    t1, 1
        li    t3, 1
        slt   t2, t0, t1
        bne   t2, t3, fail
        sltu  t2, t0, t1
        bnez  t2, fail
        slt   t2, t1, t1
        bnez  t2, fail
        sltu  t2, zero, t1
        bne   t2, t3, fail

        # 11: SLTI / SLTIU (both sign-extend the immediate)
        li    gp, 11
        li    t3, 1
        li    t0, -100
        slti  t2, t0, -99
        bne   t2, t3, fail
        slti  t2, t0, -100
        bnez  t2, fail
        li    t0, 5
        sltiu t2, t0, -1
        bne   t2, t3, fail
        sltiu t2, zero, 1
        bne   t2, t3, fail
        sltiu t2, t0, 1
        bnez  t2, fail

        # 12: LUI and AUIPC
        li    gp, 12
        lui   t0, 0xFFFFF
        li    t3, 0xFFFFF000
        bne   t0, t3, fail
a12:    auipc t0, 0x1
        la    t1, a12
        li    t2, 0x1000
        add   t1, t1, t2
        bne   t0, t1, fail

        # 13: dependent chain, every result feeds the next instruction
        li    gp, 13
        addi  t0, zero, 1
        add   t0, t0, t0
        add   t0, t0, t0
        add   t0, t0, t0
        slli  t0, t0, 2
        addi  t0, t0, -1
        xori  t0, t0, 0x1F
        bnez  t0, fail

pass:
        li    a0, 0
        j     done
fail:
        mv    a0, gp
done:
        li    a7, 10
        ecall
