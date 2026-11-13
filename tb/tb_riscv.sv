//-----------------------------------------------------------------------------
// tb_riscv : runs test programs on riscv_top and reports a results table.
//   Each program reports its own result: a0 = 0 means pass, any other value
//   is the number of the failing check. Before every program the instruction
//   memory, data memory and registers are cleared and the core is reset.
//
//   Plusargs
//     +PROG=<file>   run only this image (default: the full test list)
//     +DIR=<path>    prefix for image files, e.g. +DIR=../tests/
//     +TRACE         print every retired instruction
//     +PIPE          print the pipeline every cycle (PC in each stage + events)
//-----------------------------------------------------------------------------
`timescale 1ns/1ps

module tb_riscv;
  import riscv_pkg::*;

  localparam int IMEM_WORDS = 1024;
  localparam int DMEM_WORDS = 1024;
  localparam int MAX_CYCLES = 200_000;

  logic clk   = 1'b0;
  logic rst_n = 1'b0;
  logic halted, illegal_instr;

  always #5 clk = ~clk;

  riscv_top #(
    .IMEM_WORDS (IMEM_WORDS),
    .DMEM_WORDS (DMEM_WORDS)
  ) dut (
    .clk           (clk),
    .rst_n         (rst_n),
    .halted        (halted),
    .illegal_instr (illegal_instr)
  );

  //---------------------------------------------------------------------------
  // Retirement trace and halt capture
  //---------------------------------------------------------------------------
  bit          trace, pipe;
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
  // Pipeline view
  //---------------------------------------------------------------------------
  function automatic string stage_pc(logic valid, logic [31:0] pc);
    return valid ? $sformatf("%08h", pc) : "   --   ";
  endfunction

  function automatic string pad(string s, int width);
    string t = s;
    while (t.len() < width) t = {t, " "};
    return t;
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
  // Run one program
  //---------------------------------------------------------------------------
  typedef struct {
    string       name;
    bit          found;
    bit          pass;
    string       status;
    logic [31:0] a0;
    int unsigned cycles;
    int unsigned instret;
    int unsigned stalls;
    int unsigned flushes;
  } result_t;

  task automatic run_program(input string dir, input string name, output result_t r);
    string       path;
    int          fd;
    int unsigned cyc;

    r.name  = name;
    r.found = 1'b0;
    r.pass  = 1'b0;
    path    = {dir, name};

    fd = $fopen(path, "r");
    if (fd == 0) begin
      r.status = "FILE NOT FOUND";
      $display("[%s] cannot open %s", name, path);
      return;
    end
    $fclose(fd);
    r.found = 1'b1;

    // Clean start: reset the core, clear memories and registers, load the image
    @(negedge clk) rst_n = 1'b0;
    for (int i = 0; i < IMEM_WORDS; i++) dut.u_imem.mem[i] = '0;
    for (int i = 0; i < DMEM_WORDS; i++) dut.u_dmem.mem[i] = '0;
    for (int i = 1; i < 32; i++)         dut.u_core.u_rf.regs[i] = '0;
    $readmemh(path, dut.u_imem.mem);

    $display("");
    $display("---- %s ----", name);
    if (pipe) begin
      $display("cycle |    IF    |    ID    |    EX    |   MEM    |    WB    | events");
      $display("------+----------+----------+----------+----------+----------+-------");
    end

    repeat (5) @(posedge clk);
    @(negedge clk) rst_n = 1'b1;

    cyc = 0;
    while (!halted && cyc < MAX_CYCLES) begin
      @(posedge clk);
      cyc++;
    end
    @(negedge clk);

    r.a0      = dut.u_core.u_rf.regs[10];
    r.cycles  = dut.u_core.cnt_cycles;
    r.instret = dut.u_core.cnt_instret;
    r.stalls  = dut.u_core.cnt_stalls;
    r.flushes = dut.u_core.cnt_flushes;

    if (!halted)
      r.status = "TIMEOUT";
    else if (illegal_instr)
      r.status = $sformatf("ILLEGAL 0x%08h at pc 0x%08h", halt_instr, halt_pc);
    else if (r.a0 != 0)
      r.status = $sformatf("check %0d failed", r.a0);
    else begin
      r.status = "PASS";
      r.pass   = 1'b1;
    end
    $display("[%s] %s", name, r.status);
  endtask

  //---------------------------------------------------------------------------
  // Test list and summary
  //---------------------------------------------------------------------------
  string   dir = "";
  string   one_prog;
  string   programs[$];
  result_t results[$];
  result_t r;
  int      n_pass;
  real     cpi;

  initial begin
    $dumpfile("dump.vcd");
    $dumpvars(0, tb_riscv);

    trace = $test$plusargs("TRACE");
    pipe  = $test$plusargs("PIPE");
    void'($value$plusargs("DIR=%s", dir));

    if ($value$plusargs("PROG=%s", one_prog))
      programs = '{one_prog};
    else
      programs = '{"smoke.hex", "alu.hex", "mem.hex", "branch.hex", "hazard.hex", "sort.hex"};

    foreach (programs[i]) begin
      run_program(dir, programs[i], r);
      results.push_back(r);
    end

    n_pass = 0;
    $display("");
    $display("========================= RV32I TEST RESULTS =========================");
    $display(" Program       Instr   Cycles    CPI   Stalls  Br/Jmp   Result");
    $display(" -----------  ------  -------  -----  -------  ------   ------");
    foreach (results[i]) begin
      if (results[i].found) begin
        cpi = (results[i].instret != 0) ?
              real'(results[i].cycles) / real'(results[i].instret) : 0.0;
        $display(" %s  %6d  %7d  %5.3f  %7d  %6d   %s",
                 pad(results[i].name, 11), results[i].instret, results[i].cycles, cpi,
                 results[i].stalls, results[i].flushes, results[i].status);
      end else begin
        $display(" %s  %6s  %7s  %5s  %7s  %6s   %s",
                 pad(results[i].name, 11), "-", "-", "-", "-", "-", results[i].status);
      end
      if (results[i].pass) n_pass++;
    end
    $display(" -----------------------------------------------------------------------");
    $display(" %0d of %0d programs passed", n_pass, results.size());
    if (n_pass == results.size())
      $display(" RESULT : *** ALL TESTS PASSED ***");
    else
      $display(" RESULT : *** TEST FAILED ***");
    $display("=======================================================================");
    $display(" Any assertion failure is reported above as an \"SVA:\" error.");
    $finish;
  end

endmodule
