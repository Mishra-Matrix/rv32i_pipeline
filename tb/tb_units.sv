//-----------------------------------------------------------------------------
// tb_units : unit tests for the datapath and decode blocks
//   alu        - known-answer vectors + random vectors against a reference model
//   branch_cmp - known-answer vectors + random vectors
//   regfile    - fill/readback, x0, write-through, random read/write traffic
//   imm_gen    - immediates encoded into each format and decoded back
//   control    - every RV32I instruction plus reserved encodings
// Run with +SEED=<n> to change the random seed.
//-----------------------------------------------------------------------------
`timescale 1ns/1ps

module tb_units;
  import riscv_pkg::*;

  int unsigned n_checks, n_errors;

  function automatic void check(bit ok, string msg);
    n_checks++;
    if (!ok) begin
      n_errors++;
      $error("[%0t] %s", $time, msg);
    end
  endfunction

  task automatic report(string block, int unsigned err_before, int unsigned chk_before);
    $display("[%0t] %s: %0d checks, %0d errors -> %s", $time, block,
             n_checks - chk_before, n_errors - err_before,
             (n_errors == err_before) ? "PASS" : "FAIL");
  endtask

  //---------------------------------------------------------------------------
  // Instruction encoders (used to build test vectors)
  //---------------------------------------------------------------------------
  function automatic logic [31:0] enc_r(logic [6:0] f7, logic [4:0] rs2, logic [4:0] rs1,
                                        logic [2:0] f3, logic [4:0] rd, logic [6:0] op);
    return {f7, rs2, rs1, f3, rd, op};
  endfunction

  function automatic logic [31:0] enc_i(logic [11:0] imm, logic [4:0] rs1, logic [2:0] f3,
                                        logic [4:0] rd, logic [6:0] op);
    return {imm, rs1, f3, rd, op};
  endfunction

  function automatic logic [31:0] enc_s(logic [11:0] imm, logic [4:0] rs2, logic [4:0] rs1,
                                        logic [2:0] f3, logic [6:0] op);
    return {imm[11:5], rs2, rs1, f3, imm[4:0], op};
  endfunction

  function automatic logic [31:0] enc_b(logic [12:0] imm, logic [4:0] rs2, logic [4:0] rs1,
                                        logic [2:0] f3, logic [6:0] op);
    return {imm[12], imm[10:5], rs2, rs1, f3, imm[4:1], imm[11], op};
  endfunction

  function automatic logic [31:0] enc_u(logic [31:0] imm, logic [4:0] rd, logic [6:0] op);
    return {imm[31:12], rd, op};
  endfunction

  function automatic logic [31:0] enc_j(logic [20:0] imm, logic [4:0] rd, logic [6:0] op);
    return {imm[20], imm[10:1], imm[11], imm[19:12], rd, op};
  endfunction

  //---------------------------------------------------------------------------
  // DUTs
  //---------------------------------------------------------------------------
  logic clk = 1'b0;
  always #5 clk = ~clk;

  // ALU
  alu_op_t     alu_op;
  logic [31:0] alu_a, alu_b, alu_y;
  alu u_alu (.op(alu_op), .a(alu_a), .b(alu_b), .y(alu_y));

  // Branch comparator
  logic [2:0]  br_f3;
  logic [31:0] br_a, br_b;
  logic        br_taken;
  branch_cmp u_br (.funct3(br_f3), .a(br_a), .b(br_b), .taken(br_taken));

  // Register file
  logic [4:0]  rs1_addr = '0, rs2_addr = '0, rd_addr = '0;
  logic [31:0] rs1_data, rs2_data, rd_data = '0;
  logic        we = 1'b0;
  regfile u_rf (.clk(clk), .rs1_addr(rs1_addr), .rs1_data(rs1_data),
                .rs2_addr(rs2_addr), .rs2_data(rs2_data),
                .we(we), .rd_addr(rd_addr), .rd_data(rd_data));

  // Immediate generator
  logic [31:0] ig_instr, ig_imm;
  imm_sel_t    ig_sel;
  imm_gen u_imm (.instr(ig_instr), .sel(ig_sel), .imm(ig_imm));

  // Decoder
  logic [31:0] dec_instr;
  ctrl_t       dec_ctrl;
  control u_ctrl (.instr(dec_instr), .ctrl(dec_ctrl));

  //---------------------------------------------------------------------------
  // ALU
  //---------------------------------------------------------------------------
  function automatic logic [31:0] alu_ref(alu_op_t op, logic [31:0] a, logic [31:0] b);
    int sa;
    sa = int'(a);
    case (op)
      ALU_ADD:  return a + b;
      ALU_SUB:  return a - b;
      ALU_SLL:  return a << b[4:0];
      ALU_SLT:  return (int'(a) < int'(b)) ? 32'd1 : 32'd0;
      ALU_SLTU: return (a < b) ? 32'd1 : 32'd0;
      ALU_XOR:  return a ^ b;
      ALU_SRL:  return a >> b[4:0];
      ALU_SRA:  return 32'(sa >>> b[4:0]);
      ALU_OR:   return a | b;
      ALU_AND:  return a & b;
      default:  return '0;
    endcase
  endfunction

  task automatic alu_vec(alu_op_t op, logic [31:0] a, logic [31:0] b, logic [31:0] exp);
    alu_op = op; alu_a = a; alu_b = b;
    #1;
    check(alu_y === exp, $sformatf("ALU %s 0x%08h, 0x%08h: got 0x%08h, expected 0x%08h",
                                   op.name(), a, b, alu_y, exp));
  endtask

  task automatic test_alu();
    int unsigned e = n_errors, c = n_checks;
    alu_op_t op;
    logic [31:0] a, b;
    // Known answers
    alu_vec(ALU_ADD,  32'hFFFF_FFFF, 32'h0000_0001, 32'h0000_0000);
    alu_vec(ALU_SUB,  32'h0000_0000, 32'h0000_0001, 32'hFFFF_FFFF);
    alu_vec(ALU_SLL,  32'h0000_0001, 32'h0000_001F, 32'h8000_0000);
    alu_vec(ALU_SLL,  32'h0000_0001, 32'h0000_0020, 32'h0000_0001);   // only b[4:0] used
    alu_vec(ALU_SLT,  32'hFFFF_FFFF, 32'h0000_0001, 32'h0000_0001);   // -1 < 1
    alu_vec(ALU_SLTU, 32'hFFFF_FFFF, 32'h0000_0001, 32'h0000_0000);
    alu_vec(ALU_SLT,  32'h8000_0000, 32'h7FFF_FFFF, 32'h0000_0001);
    alu_vec(ALU_SLTU, 32'h8000_0000, 32'h7FFF_FFFF, 32'h0000_0000);
    alu_vec(ALU_SRL,  32'h8000_0000, 32'h0000_0004, 32'h0800_0000);
    alu_vec(ALU_SRA,  32'h8000_0000, 32'h0000_0004, 32'hF800_0000);
    alu_vec(ALU_SRA,  32'h7000_0000, 32'h0000_0004, 32'h0700_0000);
    alu_vec(ALU_XOR,  32'hF0F0_F0F0, 32'hFFFF_0000, 32'h0F0F_F0F0);
    alu_vec(ALU_OR,   32'hF0F0_0000, 32'h0000_0F0F, 32'hF0F0_0F0F);
    alu_vec(ALU_AND,  32'hF0F0_F0F0, 32'hFF00_FF00, 32'hF000_F000);
    // Random against the reference model
    repeat (5000) begin
      op = alu_op_t'($urandom_range(0, 9));
      a  = $urandom();
      b  = ($urandom_range(3) == 0) ? 32'($urandom_range(0, 40)) : $urandom();
      alu_vec(op, a, b, alu_ref(op, a, b));
    end
    report("ALU", e, c);
  endtask

  //---------------------------------------------------------------------------
  // Branch comparator
  //---------------------------------------------------------------------------
  function automatic logic br_ref(logic [2:0] f3, logic [31:0] a, logic [31:0] b);
    case (f3)
      3'b000:  return a == b;
      3'b001:  return a != b;
      3'b100:  return int'(a) <  int'(b);
      3'b101:  return int'(a) >= int'(b);
      3'b110:  return a <  b;
      3'b111:  return a >= b;
      default: return 1'b0;
    endcase
  endfunction

  task automatic br_vec(logic [2:0] f3, logic [31:0] a, logic [31:0] b, logic exp);
    br_f3 = f3; br_a = a; br_b = b;
    #1;
    check(br_taken === exp, $sformatf("BRANCH f3=%03b 0x%08h, 0x%08h: got %0b, expected %0b",
                                      f3, a, b, br_taken, exp));
  endtask

  task automatic test_branch();
    int unsigned e = n_errors, c = n_checks;
    logic [2:0]  f3;
    logic [31:0] a, b;
    br_vec(3'b100, 32'hFFFF_FFFF, 32'h0000_0001, 1'b1);   // BLT  -1 < 1
    br_vec(3'b110, 32'hFFFF_FFFF, 32'h0000_0001, 1'b0);   // BLTU
    br_vec(3'b101, 32'h0000_0005, 32'h0000_0005, 1'b1);   // BGE  equal
    br_vec(3'b111, 32'h0000_0000, 32'hFFFF_FFFF, 1'b0);   // BGEU
    br_vec(3'b000, 32'h1234_5678, 32'h1234_5678, 1'b1);   // BEQ
    br_vec(3'b001, 32'h1234_5678, 32'h1234_5678, 1'b0);   // BNE
    repeat (3000) begin
      case ($urandom_range(5))
        0: f3 = 3'b000;  1: f3 = 3'b001;  2: f3 = 3'b100;
        3: f3 = 3'b101;  4: f3 = 3'b110;  default: f3 = 3'b111;
      endcase
      a = $urandom();
      b = ($urandom_range(3) == 0) ? a : $urandom();    // force some equal operands
      br_vec(f3, a, b, br_ref(f3, a, b));
    end
    report("BRANCH_CMP", e, c);
  endtask

  //---------------------------------------------------------------------------
  // Register file
  //---------------------------------------------------------------------------
  task automatic test_regfile();
    int unsigned e = n_errors, c = n_checks;
    logic [31:0] shadow [32];
    logic [31:0] exp1, exp2;

    foreach (shadow[i]) shadow[i] = '0;

    // Fill every register, including an attempted write to x0
    for (int r = 0; r < 32; r++) begin
      @(negedge clk);
      we = 1'b1; rd_addr = 5'(r); rd_data = $urandom();
      if (r != 0) shadow[r] = rd_data;
    end
    @(negedge clk) we = 1'b0;

    // Read back on both ports
    for (int r = 0; r < 32; r++) begin
      rs1_addr = 5'(r); rs2_addr = 5'(31 - r);
      #1;
      check(rs1_data === shadow[r],      $sformatf("RF rs1 x%0d: got 0x%08h, expected 0x%08h", r, rs1_data, shadow[r]));
      check(rs2_data === shadow[31 - r], $sformatf("RF rs2 x%0d: got 0x%08h, expected 0x%08h", 31 - r, rs2_data, shadow[31 - r]));
    end

    // Write-through: new value visible before the clock edge; x0 never bypasses
    @(negedge clk);
    we = 1'b1; rd_addr = 5'd5; rd_data = 32'hA5A5_5A5A; rs1_addr = 5'd5; rs2_addr = 5'd0;
    #1;
    check(rs1_data === 32'hA5A5_5A5A, "RF write-through to rs1 failed");
    check(rs2_data === 32'h0,         "RF x0 not zero");
    @(posedge clk) shadow[5] = 32'hA5A5_5A5A;
    @(negedge clk);
    rd_addr = 5'd0; rd_data = 32'hFFFF_FFFF; rs1_addr = 5'd0;
    #1;
    check(rs1_data === 32'h0, "RF write to x0 bypassed onto read port");
    @(negedge clk) we = 1'b0;

    // Random traffic
    repeat (2000) begin
      @(negedge clk);
      we       = $urandom_range(1);
      rd_addr  = $urandom();
      rd_data  = $urandom();
      rs1_addr = $urandom();
      rs2_addr = ($urandom_range(3) == 0) ? rd_addr : 5'($urandom());
      #1;
      exp1 = (rs1_addr == 0) ? '0 : (we && rd_addr == rs1_addr) ? rd_data : shadow[rs1_addr];
      exp2 = (rs2_addr == 0) ? '0 : (we && rd_addr == rs2_addr) ? rd_data : shadow[rs2_addr];
      check(rs1_data === exp1, $sformatf("RF rs1 x%0d: got 0x%08h, expected 0x%08h", rs1_addr, rs1_data, exp1));
      check(rs2_data === exp2, $sformatf("RF rs2 x%0d: got 0x%08h, expected 0x%08h", rs2_addr, rs2_data, exp2));
      @(posedge clk);
      if (we && rd_addr != 0) shadow[rd_addr] = rd_data;
    end
    @(negedge clk) we = 1'b0;
    report("REGFILE", e, c);
  endtask

  //---------------------------------------------------------------------------
  // Immediate generator
  //---------------------------------------------------------------------------
  task automatic imm_vec(logic [31:0] instr, imm_sel_t sel, logic [31:0] exp);
    ig_instr = instr; ig_sel = sel;
    #1;
    check(ig_imm === exp, $sformatf("IMM %s instr 0x%08h: got 0x%08h, expected 0x%08h",
                                    sel.name(), instr, ig_imm, exp));
  endtask

  task automatic test_imm();
    int unsigned e = n_errors, c = n_checks;
    logic [11:0] i12;
    logic [12:0] i13;
    logic [20:0] i21;
    logic [31:0] i32;
    // Known answer from RARS: addi x1, x0, 5 = 0x00500093
    imm_vec(32'h0050_0093, IMM_I, 32'd5);
    repeat (2000) begin
      i12 = $urandom();
      imm_vec(enc_i(i12, $urandom(), $urandom(), $urandom(), OP_IMM), IMM_I, {{20{i12[11]}}, i12});
      imm_vec(enc_s(i12, $urandom(), $urandom(), 3'b010, OP_STORE),  IMM_S, {{20{i12[11]}}, i12});
      i13 = {$urandom(), 1'b0};
      imm_vec(enc_b(i13, $urandom(), $urandom(), 3'b000, OP_BRANCH), IMM_B, {{19{i13[12]}}, i13});
      i32 = {$urandom(), 12'b0};
      imm_vec(enc_u(i32, $urandom(), OP_LUI),                         IMM_U, i32);
      i21 = {$urandom(), 1'b0};
      imm_vec(enc_j(i21, $urandom(), OP_JAL),                         IMM_J, {{11{i21[20]}}, i21});
    end
    report("IMM_GEN", e, c);
  endtask

  //---------------------------------------------------------------------------
  // Decoder
  //---------------------------------------------------------------------------
  function automatic ctrl_t mk(bit rw, bit mr, bit mw, bit br, bit jal, bit jalr, bit bimm,
                               src_a_t sa, alu_op_t op, imm_sel_t is, wb_sel_t wb,
                               bit halt = 1'b0, bit ill = 1'b0);
    ctrl_t c;
    c.reg_write = rw;   c.mem_read = mr;   c.mem_write = mw;
    c.branch    = br;   c.jal      = jal;  c.jalr      = jalr;
    c.src_b_imm = bimm; c.src_a    = sa;   c.alu_op    = op;
    c.imm_sel   = is;   c.wb_sel   = wb;   c.halt      = halt;
    c.illegal   = ill;
    return c;
  endfunction

  task automatic dec_vec(string name, logic [31:0] instr, ctrl_t exp);
    dec_instr = instr;
    #1;
    check(dec_ctrl === exp, $sformatf("DECODE %s (0x%08h):\n  got      %p\n  expected %p",
                                      name, instr, dec_ctrl, exp));
  endtask

  task automatic test_control();
    int unsigned e = n_errors, c = n_checks;
    ctrl_t BUBBLE, ILLEGAL, HALT;
    BUBBLE  = '0;
    ILLEGAL = '0; ILLEGAL.illegal = 1'b1;
    HALT    = '0; HALT.halt       = 1'b1;

    // Encoder sanity check against RARS output
    check(enc_i(12'd5, 5'd0, 3'b000, 5'd1, OP_IMM) === 32'h0050_0093, "enc_i does not match RARS");
    check(enc_r(7'd0, 5'd2, 5'd1, 3'b000, 5'd3, OP_REG) === 32'h0020_81B3, "enc_r does not match RARS");

    //            name    instruction                                         rw mr mw br jal jalr imm  srcA        alu       imm    wb
    dec_vec("LUI",   enc_u(32'h1234_5000, 5'd1, OP_LUI),          mk(1, 0, 0, 0, 0, 0, 1, SRC_A_ZERO, ALU_ADD,  IMM_U, WB_ALU));
    dec_vec("AUIPC", enc_u(32'h1234_5000, 5'd1, OP_AUIPC),        mk(1, 0, 0, 0, 0, 0, 1, SRC_A_PC,   ALU_ADD,  IMM_U, WB_ALU));
    dec_vec("JAL",   enc_j(21'h0_0010, 5'd1, OP_JAL),             mk(1, 0, 0, 0, 1, 0, 0, SRC_A_RS1,  ALU_ADD,  IMM_J, WB_PC4));
    dec_vec("JALR",  enc_i(12'h004, 5'd2, 3'b000, 5'd1, OP_JALR), mk(1, 0, 0, 0, 0, 1, 1, SRC_A_RS1,  ALU_ADD,  IMM_I, WB_PC4));

    for (int k = 0; k < 6; k++) begin
      logic [2:0] f3;
      f3 = (k == 0) ? 3'b000 : (k == 1) ? 3'b001 : (k == 2) ? 3'b100 :
           (k == 3) ? 3'b101 : (k == 4) ? 3'b110 : 3'b111;
      dec_vec($sformatf("BRANCH f3=%03b", f3), enc_b(13'h010, 5'd2, 5'd1, f3, OP_BRANCH),
              mk(0, 0, 0, 1, 0, 0, 0, SRC_A_RS1, ALU_ADD, IMM_B, WB_ALU));
    end

    dec_vec("LB",  enc_i(12'h004, 5'd2, 3'b000, 5'd1, OP_LOAD), mk(1, 1, 0, 0, 0, 0, 1, SRC_A_RS1, ALU_ADD, IMM_I, WB_MEM));
    dec_vec("LH",  enc_i(12'h004, 5'd2, 3'b001, 5'd1, OP_LOAD), mk(1, 1, 0, 0, 0, 0, 1, SRC_A_RS1, ALU_ADD, IMM_I, WB_MEM));
    dec_vec("LW",  enc_i(12'h004, 5'd2, 3'b010, 5'd1, OP_LOAD), mk(1, 1, 0, 0, 0, 0, 1, SRC_A_RS1, ALU_ADD, IMM_I, WB_MEM));
    dec_vec("LBU", enc_i(12'h004, 5'd2, 3'b100, 5'd1, OP_LOAD), mk(1, 1, 0, 0, 0, 0, 1, SRC_A_RS1, ALU_ADD, IMM_I, WB_MEM));
    dec_vec("LHU", enc_i(12'h004, 5'd2, 3'b101, 5'd1, OP_LOAD), mk(1, 1, 0, 0, 0, 0, 1, SRC_A_RS1, ALU_ADD, IMM_I, WB_MEM));

    dec_vec("SB",  enc_s(12'h004, 5'd3, 5'd2, 3'b000, OP_STORE), mk(0, 0, 1, 0, 0, 0, 1, SRC_A_RS1, ALU_ADD, IMM_S, WB_ALU));
    dec_vec("SH",  enc_s(12'h004, 5'd3, 5'd2, 3'b001, OP_STORE), mk(0, 0, 1, 0, 0, 0, 1, SRC_A_RS1, ALU_ADD, IMM_S, WB_ALU));
    dec_vec("SW",  enc_s(12'h004, 5'd3, 5'd2, 3'b010, OP_STORE), mk(0, 0, 1, 0, 0, 0, 1, SRC_A_RS1, ALU_ADD, IMM_S, WB_ALU));

    dec_vec("ADDI",  enc_i(12'h7FF, 5'd2, 3'b000, 5'd1, OP_IMM),               mk(1, 0, 0, 0, 0, 0, 1, SRC_A_RS1, ALU_ADD,  IMM_I, WB_ALU));
    dec_vec("SLTI",  enc_i(12'h800, 5'd2, 3'b010, 5'd1, OP_IMM),               mk(1, 0, 0, 0, 0, 0, 1, SRC_A_RS1, ALU_SLT,  IMM_I, WB_ALU));
    dec_vec("SLTIU", enc_i(12'h001, 5'd2, 3'b011, 5'd1, OP_IMM),               mk(1, 0, 0, 0, 0, 0, 1, SRC_A_RS1, ALU_SLTU, IMM_I, WB_ALU));
    dec_vec("XORI",  enc_i(12'hFFF, 5'd2, 3'b100, 5'd1, OP_IMM),               mk(1, 0, 0, 0, 0, 0, 1, SRC_A_RS1, ALU_XOR,  IMM_I, WB_ALU));
    dec_vec("ORI",   enc_i(12'h0F0, 5'd2, 3'b110, 5'd1, OP_IMM),               mk(1, 0, 0, 0, 0, 0, 1, SRC_A_RS1, ALU_OR,   IMM_I, WB_ALU));
    dec_vec("ANDI",  enc_i(12'h0F0, 5'd2, 3'b111, 5'd1, OP_IMM),               mk(1, 0, 0, 0, 0, 0, 1, SRC_A_RS1, ALU_AND,  IMM_I, WB_ALU));
    dec_vec("SLLI",  enc_r(7'b0000000, 5'd3, 5'd2, 3'b001, 5'd1, OP_IMM),      mk(1, 0, 0, 0, 0, 0, 1, SRC_A_RS1, ALU_SLL,  IMM_I, WB_ALU));
    dec_vec("SRLI",  enc_r(7'b0000000, 5'd3, 5'd2, 3'b101, 5'd1, OP_IMM),      mk(1, 0, 0, 0, 0, 0, 1, SRC_A_RS1, ALU_SRL,  IMM_I, WB_ALU));
    dec_vec("SRAI",  enc_r(7'b0100000, 5'd3, 5'd2, 3'b101, 5'd1, OP_IMM),      mk(1, 0, 0, 0, 0, 0, 1, SRC_A_RS1, ALU_SRA,  IMM_I, WB_ALU));

    dec_vec("ADD",  enc_r(7'b0000000, 5'd3, 5'd2, 3'b000, 5'd1, OP_REG), mk(1, 0, 0, 0, 0, 0, 0, SRC_A_RS1, ALU_ADD,  IMM_I, WB_ALU));
    dec_vec("SUB",  enc_r(7'b0100000, 5'd3, 5'd2, 3'b000, 5'd1, OP_REG), mk(1, 0, 0, 0, 0, 0, 0, SRC_A_RS1, ALU_SUB,  IMM_I, WB_ALU));
    dec_vec("SLL",  enc_r(7'b0000000, 5'd3, 5'd2, 3'b001, 5'd1, OP_REG), mk(1, 0, 0, 0, 0, 0, 0, SRC_A_RS1, ALU_SLL,  IMM_I, WB_ALU));
    dec_vec("SLT",  enc_r(7'b0000000, 5'd3, 5'd2, 3'b010, 5'd1, OP_REG), mk(1, 0, 0, 0, 0, 0, 0, SRC_A_RS1, ALU_SLT,  IMM_I, WB_ALU));
    dec_vec("SLTU", enc_r(7'b0000000, 5'd3, 5'd2, 3'b011, 5'd1, OP_REG), mk(1, 0, 0, 0, 0, 0, 0, SRC_A_RS1, ALU_SLTU, IMM_I, WB_ALU));
    dec_vec("XOR",  enc_r(7'b0000000, 5'd3, 5'd2, 3'b100, 5'd1, OP_REG), mk(1, 0, 0, 0, 0, 0, 0, SRC_A_RS1, ALU_XOR,  IMM_I, WB_ALU));
    dec_vec("SRL",  enc_r(7'b0000000, 5'd3, 5'd2, 3'b101, 5'd1, OP_REG), mk(1, 0, 0, 0, 0, 0, 0, SRC_A_RS1, ALU_SRL,  IMM_I, WB_ALU));
    dec_vec("SRA",  enc_r(7'b0100000, 5'd3, 5'd2, 3'b101, 5'd1, OP_REG), mk(1, 0, 0, 0, 0, 0, 0, SRC_A_RS1, ALU_SRA,  IMM_I, WB_ALU));
    dec_vec("OR",   enc_r(7'b0000000, 5'd3, 5'd2, 3'b110, 5'd1, OP_REG), mk(1, 0, 0, 0, 0, 0, 0, SRC_A_RS1, ALU_OR,   IMM_I, WB_ALU));
    dec_vec("AND",  enc_r(7'b0000000, 5'd3, 5'd2, 3'b111, 5'd1, OP_REG), mk(1, 0, 0, 0, 0, 0, 0, SRC_A_RS1, ALU_AND,  IMM_I, WB_ALU));

    dec_vec("FENCE",  32'h0FF0_000F,     BUBBLE);
    dec_vec("NOP",    INSTR_NOP,         mk(1, 0, 0, 0, 0, 0, 1, SRC_A_RS1, ALU_ADD, IMM_I, WB_ALU));
    dec_vec("ECALL",  INSTR_ECALL,       HALT);
    dec_vec("EBREAK", INSTR_EBREAK,      HALT);

    // Reserved / unsupported encodings
    dec_vec("all zeros",        32'h0000_0000,                                        ILLEGAL);
    dec_vec("all ones",         32'hFFFF_FFFF,                                        ILLEGAL);
    dec_vec("compressed (C)",   32'h0000_4501,                                        ILLEGAL);
    dec_vec("CSRRW",            32'h3400_9073,                                        ILLEGAL);
    dec_vec("MUL (M ext)",      enc_r(7'b0000001, 5'd3, 5'd2, 3'b000, 5'd1, OP_REG),  ILLEGAL);
    dec_vec("SUB-style SLL",    enc_r(7'b0100000, 5'd3, 5'd2, 3'b001, 5'd1, OP_REG),  ILLEGAL);
    dec_vec("SLLI funct7!=0",   enc_r(7'b0100000, 5'd3, 5'd2, 3'b001, 5'd1, OP_IMM),  ILLEGAL);
    dec_vec("SRxI funct7 bad",  enc_r(7'b0000001, 5'd3, 5'd2, 3'b101, 5'd1, OP_IMM),  ILLEGAL);
    dec_vec("BRANCH f3=010",    enc_b(13'h010, 5'd2, 5'd1, 3'b010, OP_BRANCH),        ILLEGAL);
    dec_vec("BRANCH f3=011",    enc_b(13'h010, 5'd2, 5'd1, 3'b011, OP_BRANCH),        ILLEGAL);
    dec_vec("LOAD f3=011 (LD)", enc_i(12'h004, 5'd2, 3'b011, 5'd1, OP_LOAD),          ILLEGAL);
    dec_vec("LOAD f3=110",      enc_i(12'h004, 5'd2, 3'b110, 5'd1, OP_LOAD),          ILLEGAL);
    dec_vec("STORE f3=011 (SD)",enc_s(12'h004, 5'd3, 5'd2, 3'b011, OP_STORE),         ILLEGAL);
    dec_vec("JALR f3=001",      enc_i(12'h004, 5'd2, 3'b001, 5'd1, OP_JALR),          ILLEGAL);
    dec_vec("FENCE.I",          32'h0000_100F,                                        ILLEGAL);
    report("CONTROL", e, c);
  endtask

  //---------------------------------------------------------------------------
  // Sequence
  //---------------------------------------------------------------------------
  int unsigned seed;

  initial begin
    if ($value$plusargs("SEED=%d", seed)) void'($urandom(seed));
    $display("Running RV32I unit tests");

    test_alu();
    test_branch();
    test_regfile();
    test_imm();
    test_control();

    $display("");
    $display("================ RV32I UNIT TEST SUMMARY ================");
    $display(" Checks : %0d", n_checks);
    $display(" Errors : %0d", n_errors);
    if (n_errors == 0) $display(" RESULT : *** TEST PASSED ***");
    else               $display(" RESULT : *** TEST FAILED ***");
    $display("=========================================================");
    $finish;
  end

endmodule
