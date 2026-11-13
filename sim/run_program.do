# Run a program on the core. Usage (from the sim/ folder):  vsim -c -do run_program.do
# Change +PROG below to run a different test image.
vlib work
vlog -sv -mfcu -timescale 1ns/1ps \
  ../rtl/riscv_pkg.sv ../rtl/alu.sv ../rtl/branch_cmp.sv ../rtl/regfile.sv \
  ../rtl/imm_gen.sv ../rtl/control.sv ../rtl/forward_unit.sv ../rtl/hazard_unit.sv \
  ../rtl/imem.sv ../rtl/dmem.sv ../rtl/riscv_core.sv ../rtl/riscv_top.sv \
  ../tb/tb_riscv.sv
vsim work.tb_riscv +PROG=../tests/smoke.hex
run -all
quit -f
