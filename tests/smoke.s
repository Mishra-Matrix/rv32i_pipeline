# smoke.s : first program for the RV32I pipeline
# Covers forwarding from each stage, the load-use stall, branch flushes
# (including a squashed store), JAL/JALR, LUI/AUIPC, byte/halfword memory
# accesses, shifts, compares and writes to x0.
#
# Result at ECALL: a0 = 0 on pass, otherwise a0 = number of the failing check.
# Assemble in RARS with Settings > Memory Configuration > "Compact, Text at Address 0".

        .text
main:
        # 1: operand produced by the previous instruction (EX/MEM forwarding)
        li    gp, 1
        addi  t0, zero, 5
        addi  t1, t0, 3
        li    t2, 8
        bne   t1, t2, fail

        # 2: operand produced two instructions earlier (MEM/WB forwarding)
        li    gp, 2
        addi  t0, zero, 10
        addi  s0, zero, 1
        add   t1, t0, t0
        li    t2, 20
        bne   t1, t2, fail

        # 3: operand produced three instructions earlier (register file write-through)
        li    gp, 3
        addi  t0, zero, 11
        addi  s0, zero, 1
        addi  s0, zero, 2
        addi  t1, t0, 0
        li    t2, 11
        bne   t1, t2, fail

        # 4: both operands forwarded, from different stages
        li    gp, 4
        addi  t0, zero, 7
        addi  t1, zero, 9
        sub   t2, t1, t0
        li    t3, 2
        bne   t2, t3, fail

        # 5: store with forwarded data, then load-use stall
        li    gp, 5
        li    s1, 0x2000
        li    t0, 0x12345678
        sw    t0, 0(s1)
        lw    t1, 0(s1)
        addi  t2, t1, 1
        li    t3, 0x12345679
        bne   t2, t3, fail

        # 6: load followed by a store of the loaded value
        li    gp, 6
        lw    t0, 0(s1)
        sw    t0, 4(s1)
        lw    t1, 4(s1)
        bne   t0, t1, fail

        # 7: byte / halfword loads, sign and zero extension
        li    gp, 7
        li    t0, 0x80FF7F01
        sw    t0, 8(s1)
        lb    t1, 10(s1)
        li    t2, -1
        bne   t1, t2, fail
        lbu   t1, 10(s1)
        li    t2, 0xFF
        bne   t1, t2, fail
        lb    t1, 9(s1)
        li    t2, 0x7F
        bne   t1, t2, fail
        lh    t1, 10(s1)
        li    t2, 0xFFFF80FF
        bne   t1, t2, fail
        lhu   t1, 10(s1)
        li    t2, 0x80FF
        bne   t1, t2, fail
        lh    t1, 8(s1)
        li    t2, 0x7F01
        bne   t1, t2, fail

        # 8: byte and halfword stores only change their own bytes
        li    gp, 8
        li    t0, 0xAA
        sb    t0, 9(s1)
        li    t0, 0x1234
        sh    t0, 10(s1)
        lw    t1, 8(s1)
        li    t2, 0x1234AA01
        bne   t1, t2, fail

        # 9: signed and unsigned branch conditions
        li    gp, 9
        li    t0, -1
        li    t1, 1
        blt   t0, t1, t9_a
        j     fail
t9_a:   bltu  t0, t1, fail
        bge   t1, t0, t9_b
        j     fail
t9_b:   bgeu  t1, t0, fail
        beq   t0, t0, t9_c
        j     fail
t9_c:   bne   t1, t1, fail

        # 10: instructions behind a taken branch have no effect
        li    gp, 10
        li    t0, 0
        li    t3, 0x55
        beq   zero, zero, t10_a
        sw    t3, 12(s1)
        addi  t0, t0, 1
t10_a:  bnez  t0, fail
        lw    t1, 12(s1)
        bnez  t1, fail

        # 11: JAL / JALR link and return
        li    gp, 11
        li    t0, 0
        jal   ra, t11_func
t11_ret:
        j     t11_after
t11_func:
        addi  t0, zero, 42
        ret
t11_after:
        li    t1, 42
        bne   t0, t1, fail
        la    t2, t11_ret
        bne   ra, t2, fail

        # 12: LUI and AUIPC
        li    gp, 12
        lui   t0, 0x12345
        li    t1, 0x12345000
        bne   t0, t1, fail
t12_pc: auipc t0, 0
        la    t1, t12_pc
        bne   t0, t1, fail

        # 13: shifts and set-less-than
        li    gp, 13
        li    t0, 0x80000000
        srai  t1, t0, 4
        li    t2, 0xF8000000
        bne   t1, t2, fail
        srli  t1, t0, 4
        li    t2, 0x08000000
        bne   t1, t2, fail
        slti  t1, t0, 0
        li    t2, 1
        bne   t1, t2, fail
        sltu  t1, zero, t0
        bne   t1, t2, fail

        # 14: writes to x0 are discarded
        li    gp, 14
        addi  zero, zero, 5
        add   t0, zero, zero
        bnez  t0, fail

pass:
        li    a0, 0
        j     done
fail:
        mv    a0, gp
done:
        li    a7, 10            # RARS exit call; the core halts on ECALL
        ecall
