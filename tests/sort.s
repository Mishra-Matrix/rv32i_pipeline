# sort.s : bubble sort of 16 signed words, then self-check
#   The array is filled from a xorshift32 sequence; the sort uses signed
#   compares and exits early when a pass makes no swaps. The result must be
#   in ascending order with the same sum and XOR as the original data.
#
# Result at ECALL: a0 = 0 on pass, otherwise a0 = number of the failing check.
# Assemble in RARS with Settings > Memory Configuration > "Compact, Text at Address 0".

        .text
main:
        li    s1, 0x2000          # array base
        li    s2, 16              # element count
        li    s5, 0               # sum of original data
        li    s6, 0               # xor of original data

        # Fill: xorshift32 (x ^= x << 13; x ^= x >> 17; x ^= x << 5)
        li    t0, 0x12345678
        mv    t1, s1
        mv    t2, s2
fill:   slli  t3, t0, 13
        xor   t0, t0, t3
        srli  t3, t0, 17
        xor   t0, t0, t3
        slli  t3, t0, 5
        xor   t0, t0, t3
        sw    t0, 0(t1)
        add   s5, s5, t0
        xor   s6, s6, t0
        addi  t1, t1, 4
        addi  t2, t2, -1
        bnez  t2, fill

        # Bubble sort, ascending, signed
        addi  s3, s2, -1          # comparisons in the first pass
outer:  mv    t1, s1
        mv    t2, s3
        li    s4, 0               # swap flag
inner:  lw    t3, 0(t1)
        lw    t4, 4(t1)
        bge   t4, t3, noswap
        sw    t4, 0(t1)
        sw    t3, 4(t1)
        li    s4, 1
noswap: addi  t1, t1, 4
        addi  t2, t2, -1
        bnez  t2, inner
        beqz  s4, sorted
        addi  s3, s3, -1
        bnez  s3, outer
sorted:

        # 1: ascending order
        li    gp, 1
        mv    t1, s1
        addi  t2, s2, -1
check:  lw    t3, 0(t1)
        lw    t4, 4(t1)
        blt   t4, t3, fail
        addi  t1, t1, 4
        addi  t2, t2, -1
        bnez  t2, check

        # 2: same sum and xor as the original data (same elements)
        li    gp, 2
        mv    t1, s1
        mv    t2, s2
        li    t5, 0
        li    t6, 0
sum:    lw    t3, 0(t1)
        add   t5, t5, t3
        xor   t6, t6, t3
        addi  t1, t1, 4
        addi  t2, t2, -1
        bnez  t2, sum
        bne   t5, s5, fail
        bne   t6, s6, fail

pass:
        li    a0, 0
        j     done
fail:
        mv    a0, gp
done:
        li    a7, 10
        ecall
