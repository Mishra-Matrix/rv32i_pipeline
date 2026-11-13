# RV32I 5-Stage Pipelined Processor

A SystemVerilog implementation of the RISC-V RV32I base integer instruction set on a
classic five-stage in-order pipeline, with full forwarding, load-use hazard detection
and branch flushing. Verified with block-level unit tests and self-checking programs
assembled with RARS.

## Features

- All 37 RV32I computational, load/store, branch and jump instructions
- `FENCE` executes as a NOP; `ECALL` / `EBREAK` halt the core; unsupported encodings
  (CSR, M/C extensions, reserved funct3/funct7) are detected as illegal
- Pipeline: IF → ID → EX → MEM → WB
- Forwarding from EX/MEM and MEM/WB into EX; register file write-through covers WB → ID
- One-cycle load-use stall
- Branches and jumps resolved in EX; two-instruction flush when taken
- Separate instruction ROM and data RAM; byte, halfword and word loads/stores with
  sign/zero extension
- Performance counters: cycles, instructions retired, load-use stall cycles,
  taken branches/jumps

## Pipeline

```
   IF            ID              EX               MEM            WB
 ┌─────┐ IF/ID ┌──────────┐ ID/EX ┌──────────┐ EX/MEM ┌───────┐ MEM/WB ┌──────────┐
 │ PC  │──────►│ decode   │──────►│ ALU      │───────►│ data  │───────►│ register │
 │ ROM │       │ regfile  │       │ branch   │        │ RAM   │        │ write    │
 └─────┘       │ imm gen  │       │ forward  │        └───────┘        └──────────┘
    ▲          │ hazard   │       └────┬─────┘
    │          └──────────┘            │ taken branch / jump: redirect PC, flush IF/ID, ID/EX
    └──────────────────────────────────┘
```

## Source Files

| File | Description |
|------|-------------|
| `rtl/riscv_pkg.sv` | Opcodes, ALU operations, control word definition |
| `rtl/control.sv` | Instruction decoder |
| `rtl/alu.sv` | Integer ALU |
| `rtl/branch_cmp.sv` | Branch condition unit |
| `rtl/regfile.sv` | 32 × 32 register file, two read ports, write-through |
| `rtl/imm_gen.sv` | Immediate generation for I/S/B/U/J formats |
| `rtl/forward_unit.sv` | EX operand forwarding select |
| `rtl/hazard_unit.sv` | Load-use detection |
| `rtl/riscv_core.sv` | Five-stage pipeline, halt logic, performance counters |
| `rtl/imem.sv`, `rtl/dmem.sv` | Instruction ROM and data RAM |
| `rtl/riscv_top.sv` | Core with memories |
| `tb/tb_units.sv` | Unit tests for the datapath and decode blocks |
| `tb/tb_riscv.sv` | Program runner: loads a hex image, runs to `ECALL`, reports result and CPI |
| `tests/*.s` | Self-checking test programs (RARS assembly) |

## Verification

**Unit tests (`tb/tb_units.sv`)**: known-answer and randomized checks against
reference models.

| Block | Checks |
|-------|--------|
| ALU | 14 known-answer + 5,000 random |
| Branch comparator | 6 known-answer + 3,000 random |
| Register file | fill/readback, x0, write-through, 2,000 random cycles |
| Immediate generator | 2,000 random immediates × 5 formats |
| Decoder | all RV32I instructions + 15 reserved/unsupported encodings |

**Program tests (`tb/tb_riscv.sv`)**: each program checks its own results and ends
with `a0 = 0` on pass or `a0 = <failing check>` on failure. `+PIPE` prints the
pipeline every cycle (PC in each stage, stalls, flushes, forwarding, register and
memory writes); `+TRACE` prints each retired instruction.

## Results

| Program | Instructions | Cycles | CPI | Load-use stalls | Taken branches/jumps | Result |
|---------|--------------|--------|-----|-----------------|----------------------|--------|
| `smoke.s` | 135 | 159 | 1.178 | 4 | 8 | Pass |

Cycle count = instructions + stall cycles + 2 × taken branches/jumps + 4 (pipeline fill).
A cycle-by-cycle pipeline trace of `smoke.s` is in `sim/smoke_pipeline.txt`.

## Running

Programs are assembled with [RARS](https://github.com/TheThirdOne/rars) using
*Settings → Memory Configuration → Compact, Text at Address 0*, and the `.text`
segment is exported with *File → Dump Memory* (Hexadecimal Text).

```
cd sim
vsim -c -do run_units.do       # unit tests
vsim -c -do run_program.do     # runs tests/smoke.hex
```

Simulated with Questa 2025.2.
