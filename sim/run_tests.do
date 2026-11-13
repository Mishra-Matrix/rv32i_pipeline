# Program tests with assertions. Usage (from the sim/ folder):  vsim -c -do run_tests.do
# Expects the assembled images (*.hex) in ../tests/
vlib work
vlog -sv -mfcu -timescale 1ns/1ps \
  ../rtl/riscv_pkg.sv ../rtl/alu.sv ../rtl/branch_cmp.sv ../rtl/regfile.sv \
  ../rtl/imm_gen.sv ../rtl/control.sv ../rtl/forward_unit.sv ../rtl/hazard_unit.sv \
  ../rtl/imem.sv ../rtl/dmem.sv ../rtl/riscv_core.sv ../rtl/riscv_top.sv \
  ../sva/riscv_sva.sv ../tb/tb_riscv.sv
vsim -assertdebug work.tb_riscv +DIR=../tests/
run -all
assertion report -verbose
quit -f
