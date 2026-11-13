# mem.s : loads and stores of every size and byte lane, sign/zero extension,
# negative offsets, load-use stalls on data and on addresses, and
# store-then-load of the same location.
#
# Result at ECALL: a0 = 0 on pass, otherwise a0 = number of the failing check.
# Assemble in RARS with Settings > Memory Configuration > "Compact, Text at Address 0".

        .text
main:
        li    s1, 0x2000

        # 1: word stores and loads
        li    gp, 1
        li    t0, 0xDEADBEEF
        sw    t0, 0(s1)
        li    t1, 0x01234567
        sw    t1, 4(s1)
        lw    t2, 0(s1)
        bne   t2, t0, fail
        lw    t2, 4(s1)
        bne   t2, t1, fail

        # 2: negative offset
        li    gp, 2
        addi  s2, s1, 16
        sw    t0, -8(s2)
        lw    t2, 8(s1)
        bne   t2, t0, fail

        # 3: every byte lane, LBU and LB
        li    gp, 3
        lbu   t2, 0(s1)
        li    t3, 0xEF
        bne   t2, t3, fail
        lbu   t2, 1(s1)
        li    t3, 0xBE
        bne   t2, t3, fail
        lbu   t2, 2(s1)
        li    t3, 0xAD
        bne   t2, t3, fail
        lbu   t2, 3(s1)
        li    t3, 0xDE
        bne   t2, t3, fail
        lb    t2, 3(s1)
        li    t3, 0xFFFFFFDE
        bne   t2, t3, fail
        lb    t2, 4(s1)
        li    t3, 0x67
        bne   t2, t3, fail

        # 4: halfword lanes, LHU and LH
        li    gp, 4
        lhu   t2, 0(s1)
        li    t3, 0xBEEF
        bne   t2, t3, fail
        lh    t2, 2(s1)
        li    t3, 0xFFFFDEAD
        bne   t2, t3, fail
        lh    t2, 4(s1)
        li    t3, 0x4567
        bne   t2, t3, fail

        # 5: SB into each lane builds a word
        li    gp, 5
        sw    zero, 12(s1)
        li    t0, 0x11
        sb    t0, 12(s1)
        li    t0, 0x22
        sb    t0, 13(s1)
        li    t0, 0x33
        sb    t0, 14(s1)
        li    t0, 0x44
        sb    t0, 15(s1)
        lw    t2, 12(s1)
        li    t3, 0x44332211
        bne   t2, t3, fail

        # 6: SB / SH store only the low bits of rs2
        li    gp, 6
        li    t0, 0xAABBCCDD
        sw    zero, 16(s1)
        sb    t0, 16(s1)
        sh    t0, 18(s1)
        lw    t2, 16(s1)
        li    t3, 0xCCDD00DD
        bne   t2, t3, fail

        # 7: load-use on rs1, load-use on rs2, and a use one instruction later
        li    gp, 7
        lw    t0, 4(s1)
        addi  t1, t0, 1
        li    t3, 0x01234568
        bne   t1, t3, fail
        lw    t0, 4(s1)
        add   t1, zero, t0
        li    t3, 0x01234567
        bne   t1, t3, fail
        lw    t0, 4(s1)
        nop
        addi  t1, t0, 0
        bne   t1, t3, fail

        # 8: loaded value used as the address of the next load and store
        li    gp, 8
        li    t0, 0x2020
        sw    t0, 20(s1)
        li    t1, 0x5A5A5A5A
        sw    t1, 32(s1)
        lw    t2, 20(s1)
        lw    t4, 0(t2)
        bne   t4, t1, fail
        lw    t2, 20(s1)
        sw    t0, 4(t2)
        lw    t4, 36(s1)
        bne   t4, t0, fail

        # 9: store followed immediately by a load of the same address
        li    gp, 9
        li    t0, 0x13579BDF
        sw    t0, 40(s1)
        lw    t1, 40(s1)
        bne   t1, t0, fail
        sb    zero, 40(s1)
        lw    t1, 40(s1)
        li    t3, 0x13579B00
        bne   t1, t3, fail

pass:
        li    a0, 0
        j     done
fail:
        mv    a0, gp
done:
        li    a7, 10
        ecall
