# hazard.s : pipeline hazard corner cases
#   - newest result wins when one register is in both EX/MEM and MEM/WB
#   - one producer feeding both operands
#   - store address and store data forwarded together
#   - load into x0 (no stall, no effect)
#   - chained loads where each loaded value is the next address
#   - AUIPC result forwarded
#   - branches and ECALL on the wrong path of a taken branch
#   - back-to-back taken branches
#   - long chain mixing ALU, load and store dependencies
#
# Result at ECALL: a0 = 0 on pass, otherwise a0 = number of the failing check.
# Assemble in RARS with Settings > Memory Configuration > "Compact, Text at Address 0".

        .text
main:
        li    s1, 0x2000

        # 1: same register in EX/MEM and MEM/WB, the newer value must be used
        li    gp, 1
        addi  t0, zero, 1
        addi  t0, zero, 2
        add   t1, t0, zero
        li    t2, 2
        bne   t1, t2, fail

        # 2: one producer feeds both operands
        li    gp, 2
        addi  t0, zero, 21
        add   t1, t0, t0
        li    t2, 42
        bne   t1, t2, fail

        # 3: store address and store data both from recent instructions
        li    gp, 3
        addi  t0, s1, 0
        li    t1, 0x0BADF00D
        sw    t1, 0(t0)
        lw    t2, 0(s1)
        bne   t2, t1, fail

        # 4: load into x0 is discarded
        li    gp, 4
        lw    zero, 0(s1)
        add   t0, zero, zero
        bnez  t0, fail

        # 5: chained loads, each loaded value is the next address
        li    gp, 5
        li    t0, 0x2004
        sw    t0, 4(s1)
        lw    t1, 4(s1)
        lw    t2, 0(t1)
        lw    t3, 0(t2)
        bne   t3, t0, fail

        # 6: load result used two and four instructions later (no stall needed)
        li    gp, 6
        lw    t1, 0(s1)
        addi  t4, zero, 1
        add   t2, t1, zero
        addi  t4, zero, 2
        addi  t4, zero, 3
        add   t3, t1, zero
        bne   t2, t3, fail
        li    t5, 0x0BADF00D
        bne   t2, t5, fail

        # 7: AUIPC result forwarded to the next instruction
        li    gp, 7
h7_pc:  auipc t0, 0
        addi  t1, t0, 4
        la    t2, h7_pc
        addi  t2, t2, 4
        bne   t1, t2, fail

        # 8: branches on the wrong path of a taken branch have no effect
        li    gp, 8
        beq   zero, zero, h8_a
        beq   zero, zero, fail
        j     fail
h8_a:

        # 9: ECALL on the wrong path must not stop the program
        li    gp, 9
        beq   zero, zero, h9_a
        ecall
        ecall
h9_a:

        # 10: back-to-back taken branches
        li    gp, 10
        li    t0, 0
        beq   zero, zero, h10_a
        addi  t0, t0, 1
h10_a:  beq   zero, zero, h10_b
        addi  t0, t0, 1
h10_b:  beq   zero, zero, h10_c
        addi  t0, t0, 1
h10_c:  bnez  t0, fail

        # 11: chain of load, ALU and store dependencies
        li    gp, 11
        li    t0, 3
        sw    t0, 8(s1)
        lw    t1, 8(s1)
        slli  t1, t1, 2
        sw    t1, 12(s1)
        lw    t2, 12(s1)
        add   t2, t2, t1
        sub   t2, t2, t0
        sw    t2, 16(s1)
        lw    t3, 16(s1)
        li    t4, 21
        bne   t3, t4, fail

pass:
        li    a0, 0
        j     done
fail:
        mv    a0, gp
done:
        li    a7, 10
        ecall
