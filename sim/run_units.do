# Unit tests. Usage (from the sim/ folder):  vsim -c -do run_units.do
vlib work
vlog -sv -mfcu -timescale 1ns/1ps \
  ../rtl/riscv_pkg.sv ../rtl/alu.sv ../rtl/branch_cmp.sv ../rtl/regfile.sv \
  ../rtl/imm_gen.sv ../rtl/control.sv ../tb/tb_units.sv
vsim work.tb_units
run -all
quit -f
