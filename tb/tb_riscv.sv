//-----------------------------------------------------------------------------
// tb_riscv : runs a program on riscv_top until ECALL / EBREAK.
//   The program reports its own result: a0 = 0 means pass, any other value is
//   the number of the failing check.
//
//   Plusargs
//     +PROG=<file>   instruction image ($readmemh), default program.hex
//     +TRACE         print every retired instruction
//     +PIPE          print the pipeline every cycle (PC in each stage + events)
//-----------------------------------------------------------------------------
`timescale 1ns/1ps

module tb_riscv;
  import riscv_pkg::*;

  localparam int IMEM_WORDS = 1024;
  localparam int MAX_CYCLES = 200_000;

  logic clk   = 1'b0;
  logic rst_n = 1'b0;
  logic halted, illegal_instr;

  always #5 clk = ~clk;

  riscv_top #(
    .IMEM_WORDS (IMEM_WORDS)
  ) dut (
    .clk           (clk),
    .rst_n         (rst_n),
    .halted        (halted),
    .illegal_instr (illegal_instr)
  );

  //---------------------------------------------------------------------------
  // Retirement trace and halt capture
  //---------------------------------------------------------------------------
  bit          trace;
  logic [31:0] halt_pc, halt_instr;

  always @(posedge clk) begin
    if (rst_n && dut.u_core.mem_wb.valid) begin
      if (dut.u_core.mem_wb.ctrl.halt || dut.u_core.mem_wb.ctrl.illegal) begin
        halt_pc    = dut.u_core.mem_wb.pc;
        halt_instr = dut.u_core.mem_wb.instr;
      end
      if (trace) begin
        if (dut.u_core.mem_wb.ctrl.reg_write && dut.u_core.mem_wb.rd != 0)
          $display("%8d  pc=%08h  instr=%08h  x%0d <= %08h", dut.u_core.cnt_cycles,
                   dut.u_core.mem_wb.pc, dut.u_core.mem_wb.instr,
                   dut.u_core.mem_wb.rd, dut.u_core.mem_wb.wb_data);
        else
          $display("%8d  pc=%08h  instr=%08h", dut.u_core.cnt_cycles,
                   dut.u_core.mem_wb.pc, dut.u_core.mem_wb.instr);
      end
    end
  end

  //---------------------------------------------------------------------------
  // Pipeline view: PC of the instruction in each stage, plus this cycle's
  // stall / flush / forwarding / register write
  //---------------------------------------------------------------------------
  bit pipe;

  function automatic string stage_pc(logic valid, logic [31:0] pc);
    return valid ? $sformatf("%08h", pc) : "   --   ";
  endfunction

  function automatic string fwd_name(fwd_sel_t f);
    return (f == FWD_MEM) ? "EX/MEM" : "MEM/WB";
  endfunction

  always @(posedge clk) begin
    if (pipe && rst_n && !halted) begin
      string ev;
      ev = "";
      if (dut.u_core.stall)
        ev = {ev, "STALL  "};
      if (dut.u_core.redirect)
        ev = {ev, $sformatf("FLUSH->%08h  ", dut.u_core.redirect_target)};
      if (dut.u_core.id_ex.valid && dut.u_core.fwd_a != FWD_NONE)
        ev = {ev, $sformatf("rs1<-%s  ", fwd_name(dut.u_core.fwd_a))};
      if (dut.u_core.id_ex.valid && dut.u_core.fwd_b != FWD_NONE)
        ev = {ev, $sformatf("rs2<-%s  ", fwd_name(dut.u_core.fwd_b))};
      if (dut.u_core.dmem_we)
        ev = {ev, $sformatf("mem[%08h]<=%08h  ", dut.u_core.dmem_addr, dut.u_core.dmem_wdata)};
      if (dut.u_core.rf_we && dut.u_core.rf_rd != 0)
        ev = {ev, $sformatf("x%0d<=%08h", dut.u_core.rf_rd, dut.u_core.rf_wdata)};
      $display("%5d | %s | %s | %s | %s | %s | %s",
               dut.u_core.cnt_cycles,
               stage_pc(!dut.u_core.halt_pending, dut.u_core.pc),
               stage_pc(dut.u_core.if_id.valid,  dut.u_core.if_id.pc),
               stage_pc(dut.u_core.id_ex.valid,  dut.u_core.id_ex.pc),
               stage_pc(dut.u_core.ex_mem.valid, dut.u_core.ex_mem.pc),
               stage_pc(dut.u_core.mem_wb.valid, dut.u_core.mem_wb.pc),
               ev);
    end
  end

  //---------------------------------------------------------------------------
  // Run
  //---------------------------------------------------------------------------
  string       prog = "program.hex";
  int          fd;
  int unsigned cycles;
  logic [31:0] a0, gp;
  real         cpi;
  bit          pass;

  initial begin
    $dumpfile("dump.vcd");
    $dumpvars(0, tb_riscv);

    void'($value$plusargs("PROG=%s", prog));
    trace = $test$plusargs("TRACE");
    pipe  = $test$plusargs("PIPE");

    fd = $fopen(prog, "r");
    if (fd == 0) $fatal(1, "Cannot open program file '%s'", prog);
    $fclose(fd);

    for (int i = 0; i < IMEM_WORDS; i++) dut.u_imem.mem[i] = '0;
    $readmemh(prog, dut.u_imem.mem);
    $display("Program: %s", prog);

    if (pipe) begin
      $display("");
      $display("cycle |    IF    |    ID    |    EX    |   MEM    |    WB    | events");
      $display("------+----------+----------+----------+----------+----------+-------");
    end

    repeat (5) @(posedge clk);
    @(negedge clk) rst_n = 1'b1;

    cycles = 0;
    while (!halted && cycles < MAX_CYCLES) begin
      @(posedge clk);
      cycles++;
    end
    @(negedge clk);

    a0   = dut.u_core.u_rf.regs[10];
    gp   = dut.u_core.u_rf.regs[3];
    cpi  = (dut.u_core.cnt_instret != 0) ?
           real'(dut.u_core.cnt_cycles) / real'(dut.u_core.cnt_instret) : 0.0;
    pass = halted && !illegal_instr && (a0 == 0);

    $display("");
    $display("================ RV32I PIPELINE RUN ================");
    if (!halted)
      $display(" Stopped          : TIMEOUT after %0d cycles", MAX_CYCLES);
    else if (illegal_instr)
      $display(" Stopped          : ILLEGAL instruction 0x%08h at pc 0x%08h", halt_instr, halt_pc);
    else
      $display(" Stopped          : 0x%08h at pc 0x%08h", halt_instr, halt_pc);
    $display(" a0 (result)      : %0d", a0);
    if (!pass && halted && !illegal_instr)
      $display(" Failing check    : %0d (gp = %0d)", a0, gp);
    $display(" Cycles           : %0d", dut.u_core.cnt_cycles);
    $display(" Instructions     : %0d", dut.u_core.cnt_instret);
    $display(" CPI              : %0.3f", cpi);
    $display(" Load-use stalls  : %0d", dut.u_core.cnt_stalls);
    $display(" Taken br/jumps   : %0d (flush 2 each)", dut.u_core.cnt_flushes);
    $display(" RESULT           : %s", pass ? "*** TEST PASSED ***" : "*** TEST FAILED ***");
    $display("====================================================");
    $finish;
  end

endmodule
