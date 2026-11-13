//-----------------------------------------------------------------------------
// riscv_core : 5-stage in-order RV32I pipeline (IF, ID, EX, MEM, WB)
//
//   Hazards
//   - Data:     forwarding from EX/MEM and MEM/WB into EX; the register file
//               writes through, covering WB -> ID.
//   - Load-use: one-cycle stall (PC and IF/ID hold, bubble into ID/EX).
//   - Control:  branches and jumps resolve in EX; when taken, the two younger
//               instructions in IF/ID and ID/EX are flushed.
//
//   Halt
//   - ECALL / EBREAK (or an illegal instruction) stops fetch once it is in
//     ID, so no younger instruction can change state. `halted` is raised
//     when it reaches WB; every older instruction has completed by then.
//
//   Memories are external: asynchronous-read instruction ROM and data RAM.
//   Misaligned loads, stores and jump targets are not supported.
//-----------------------------------------------------------------------------
module riscv_core
  import riscv_pkg::*;
#(
  parameter logic [31:0] RESET_PC = 32'h0000_0000
) (
  input  logic        clk,
  input  logic        rst_n,          // synchronous, active low

  // Instruction memory
  output logic [31:0] imem_addr,
  input  logic [31:0] imem_rdata,

  // Data memory
  output logic        dmem_we,
  output logic [3:0]  dmem_be,
  output logic [31:0] dmem_addr,
  output logic [31:0] dmem_wdata,
  input  logic [31:0] dmem_rdata,

  // Status
  output logic        halted,
  output logic        illegal_instr
);

  //===========================================================================
  // Pipeline registers
  //===========================================================================
  typedef struct packed {
    logic        valid;
    logic [31:0] pc;
    logic [31:0] instr;
  } if_id_t;

  typedef struct packed {
    logic        valid;
    logic [31:0] pc;
    logic [31:0] instr;
    ctrl_t       ctrl;
    logic [4:0]  rs1;
    logic [4:0]  rs2;
    logic [4:0]  rd;
    logic [2:0]  funct3;
    logic [31:0] rs1_data;
    logic [31:0] rs2_data;
    logic [31:0] imm;
  } id_ex_t;

  typedef struct packed {
    logic        valid;
    logic [31:0] pc;
    logic [31:0] instr;
    ctrl_t       ctrl;
    logic [4:0]  rd;
    logic [2:0]  funct3;
    logic [31:0] result;        // ALU result, or pc + 4 for JAL / JALR
    logic [31:0] store_data;
  } ex_mem_t;

  typedef struct packed {
    logic        valid;
    logic [31:0] pc;
    logic [31:0] instr;
    ctrl_t       ctrl;
    logic [4:0]  rd;
    logic [31:0] wb_data;
  } mem_wb_t;

  if_id_t  if_id;
  id_ex_t  id_ex;
  ex_mem_t ex_mem;
  mem_wb_t mem_wb;

  // Pipeline control
  logic        stall;            // load-use
  logic        redirect;         // taken branch / jump in EX
  logic [31:0] redirect_target;
  logic        id_halt;          // ECALL / EBREAK / illegal in ID
  logic        halt_pending;     // fetch stopped

  //===========================================================================
  // IF
  //===========================================================================
  logic [31:0] pc;

  assign imem_addr = pc;

  always_ff @(posedge clk) begin
    if (!rst_n)
      pc <= RESET_PC;
    else if (redirect)
      pc <= redirect_target;
    else if (!stall && !id_halt && !halt_pending)
      pc <= pc + 32'd4;
  end

  always_ff @(posedge clk) begin
    if (!rst_n || redirect || id_halt || halt_pending) begin
      if_id <= '0;                                   // bubble
    end else if (!stall) begin
      if_id.valid <= 1'b1;
      if_id.pc    <= pc;
      if_id.instr <= imem_rdata;
    end
  end

  //===========================================================================
  // ID
  //===========================================================================
  ctrl_t       id_ctrl_dec, id_ctrl;
  logic [6:0]  id_opcode;
  logic        id_uses_rs1, id_uses_rs2;
  logic [4:0]  id_rs1, id_rs2, id_rd;
  logic [31:0] id_rs1_data, id_rs2_data, id_imm;

  // Write-back port (driven in WB)
  logic        rf_we;
  logic [4:0]  rf_rd;
  logic [31:0] rf_wdata;

  control u_control (
    .instr (if_id.instr),
    .ctrl  (id_ctrl_dec)
  );

  assign id_ctrl   = if_id.valid ? id_ctrl_dec : '0;
  assign id_opcode = if_id.instr[6:0];

  // Only real source operands take part in forwarding and hazard checks
  assign id_uses_rs1 = id_opcode inside {OP_JALR, OP_BRANCH, OP_LOAD, OP_STORE, OP_IMM, OP_REG};
  assign id_uses_rs2 = id_opcode inside {OP_BRANCH, OP_STORE, OP_REG};
  assign id_rs1      = id_uses_rs1       ? if_id.instr[19:15] : 5'd0;
  assign id_rs2      = id_uses_rs2       ? if_id.instr[24:20] : 5'd0;
  assign id_rd       = id_ctrl.reg_write ? if_id.instr[11:7]  : 5'd0;

  regfile u_rf (
    .clk      (clk),
    .rs1_addr (id_rs1),
    .rs1_data (id_rs1_data),
    .rs2_addr (id_rs2),
    .rs2_data (id_rs2_data),
    .we       (rf_we),
    .rd_addr  (rf_rd),
    .rd_data  (rf_wdata)
  );

  imm_gen u_imm_gen (
    .instr (if_id.instr),
    .sel   (id_ctrl_dec.imm_sel),
    .imm   (id_imm)
  );

  hazard_unit u_hazard (
    .id_valid       (if_id.valid),
    .id_rs1         (id_rs1),
    .id_rs2         (id_rs2),
    .ex_valid       (id_ex.valid),
    .ex_mem_read    (id_ex.ctrl.mem_read),
    .ex_rd          (id_ex.rd),
    .load_use_stall (stall)
  );

  // A halting instruction on the wrong path of a taken branch is discarded;
  // one held in ID by a load-use stall takes effect once the stall clears
  assign id_halt = if_id.valid && (id_ctrl.halt || id_ctrl.illegal) && !redirect && !stall;

  always_ff @(posedge clk) begin
    if (!rst_n)       halt_pending <= 1'b0;
    else if (id_halt) halt_pending <= 1'b1;
  end

  always_ff @(posedge clk) begin
    if (!rst_n || redirect || stall) begin
      id_ex <= '0;                                   // bubble
    end else begin
      id_ex.valid    <= if_id.valid;
      id_ex.pc       <= if_id.pc;
      id_ex.instr    <= if_id.instr;
      id_ex.ctrl     <= id_ctrl;
      id_ex.rs1      <= id_rs1;
      id_ex.rs2      <= id_rs2;
      id_ex.rd       <= id_rd;
      id_ex.funct3   <= if_id.instr[14:12];
      id_ex.rs1_data <= id_rs1_data;
      id_ex.rs2_data <= id_rs2_data;
      id_ex.imm      <= id_imm;
    end
  end

  //===========================================================================
  // EX
  //===========================================================================
  fwd_sel_t    fwd_a, fwd_b;
  logic [31:0] ex_rs1_val, ex_rs2_val;
  logic [31:0] alu_a, alu_b, alu_y;
  logic        br_taken;
  logic [31:0] ex_pc4, ex_result;

  forward_unit u_fwd (
    .ex_rs1        (id_ex.rs1),
    .ex_rs2        (id_ex.rs2),
    .mem_reg_write (ex_mem.valid && ex_mem.ctrl.reg_write),
    .mem_rd        (ex_mem.rd),
    .wb_reg_write  (mem_wb.valid && mem_wb.ctrl.reg_write),
    .wb_rd         (mem_wb.rd),
    .fwd_a         (fwd_a),
    .fwd_b         (fwd_b)
  );

  always_comb begin
    case (fwd_a)
      FWD_MEM: ex_rs1_val = ex_mem.result;
      FWD_WB:  ex_rs1_val = mem_wb.wb_data;
      default: ex_rs1_val = id_ex.rs1_data;
    endcase
    case (fwd_b)
      FWD_MEM: ex_rs2_val = ex_mem.result;
      FWD_WB:  ex_rs2_val = mem_wb.wb_data;
      default: ex_rs2_val = id_ex.rs2_data;
    endcase
  end

  always_comb begin
    case (id_ex.ctrl.src_a)
      SRC_A_PC:   alu_a = id_ex.pc;
      SRC_A_ZERO: alu_a = '0;
      default:    alu_a = ex_rs1_val;
    endcase
  end

  assign alu_b = id_ex.ctrl.src_b_imm ? id_ex.imm : ex_rs2_val;

  alu u_alu (
    .op (id_ex.ctrl.alu_op),
    .a  (alu_a),
    .b  (alu_b),
    .y  (alu_y)
  );

  branch_cmp u_branch_cmp (
    .funct3 (id_ex.funct3),
    .a      (ex_rs1_val),
    .b      (ex_rs2_val),
    .taken  (br_taken)
  );

  assign ex_pc4    = id_ex.pc + 32'd4;
  assign ex_result = (id_ex.ctrl.wb_sel == WB_PC4) ? ex_pc4 : alu_y;

  assign redirect        = id_ex.valid &&
                           ((id_ex.ctrl.branch && br_taken) || id_ex.ctrl.jal || id_ex.ctrl.jalr);
  assign redirect_target = id_ex.ctrl.jalr ? {alu_y[31:1], 1'b0}       // (rs1 + imm) & ~1
                                           : (id_ex.pc + id_ex.imm);   // branch / JAL

  always_ff @(posedge clk) begin
    if (!rst_n) begin
      ex_mem <= '0;
    end else begin
      ex_mem.valid      <= id_ex.valid;
      ex_mem.pc         <= id_ex.pc;
      ex_mem.instr      <= id_ex.instr;
      ex_mem.ctrl       <= id_ex.ctrl;
      ex_mem.rd         <= id_ex.rd;
      ex_mem.funct3     <= id_ex.funct3;
      ex_mem.result     <= ex_result;
      ex_mem.store_data <= ex_rs2_val;
    end
  end

  //===========================================================================
  // MEM
  //===========================================================================
  logic [1:0]  byte_off;
  logic [31:0] load_shifted, load_data, mem_wb_data;

  assign byte_off  = ex_mem.result[1:0];
  assign dmem_addr = ex_mem.result;
  assign dmem_we   = ex_mem.valid && ex_mem.ctrl.mem_write;

  // Store: byte enables and lane-replicated data
  always_comb begin
    case (ex_mem.funct3[1:0])
      2'b00: begin                                   // SB
        dmem_be    = 4'b0001 << byte_off;
        dmem_wdata = {4{ex_mem.store_data[7:0]}};
      end
      2'b01: begin                                   // SH
        dmem_be    = byte_off[1] ? 4'b1100 : 4'b0011;
        dmem_wdata = {2{ex_mem.store_data[15:0]}};
      end
      default: begin                                 // SW
        dmem_be    = 4'b1111;
        dmem_wdata = ex_mem.store_data;
      end
    endcase
  end

  // Load: select byte / halfword and extend
  assign load_shifted = dmem_rdata >> {byte_off, 3'b000};

  always_comb begin
    case (ex_mem.funct3)
      3'b000:  load_data = {{24{load_shifted[7]}},  load_shifted[7:0]};    // LB
      3'b001:  load_data = {{16{load_shifted[15]}}, load_shifted[15:0]};   // LH
      3'b100:  load_data = {24'b0, load_shifted[7:0]};                     // LBU
      3'b101:  load_data = {16'b0, load_shifted[15:0]};                    // LHU
      default: load_data = dmem_rdata;                                     // LW
    endcase
  end

  assign mem_wb_data = ex_mem.ctrl.mem_read ? load_data : ex_mem.result;

  always_ff @(posedge clk) begin
    if (!rst_n) begin
      mem_wb <= '0;
    end else begin
      mem_wb.valid   <= ex_mem.valid;
      mem_wb.pc      <= ex_mem.pc;
      mem_wb.instr   <= ex_mem.instr;
      mem_wb.ctrl    <= ex_mem.ctrl;
      mem_wb.rd      <= ex_mem.rd;
      mem_wb.wb_data <= mem_wb_data;
    end
  end

  //===========================================================================
  // WB
  //===========================================================================
  assign rf_we    = mem_wb.valid && mem_wb.ctrl.reg_write;
  assign rf_rd    = mem_wb.rd;
  assign rf_wdata = mem_wb.wb_data;

  always_ff @(posedge clk) begin
    if (!rst_n) begin
      halted        <= 1'b0;
      illegal_instr <= 1'b0;
    end else if (mem_wb.valid && (mem_wb.ctrl.halt || mem_wb.ctrl.illegal)) begin
      halted        <= 1'b1;
      illegal_instr <= mem_wb.ctrl.illegal;
    end
  end

  //===========================================================================
  // Performance counters
  //===========================================================================
  logic [31:0] cnt_cycles;     // cycles from reset release until halt
  logic [31:0] cnt_instret;    // instructions completed
  logic [31:0] cnt_stalls;     // load-use stall cycles
  logic [31:0] cnt_flushes;    // taken branches / jumps (2 cycles each)

  always_ff @(posedge clk) begin
    if (!rst_n) begin
      cnt_cycles  <= '0;
      cnt_instret <= '0;
      cnt_stalls  <= '0;
      cnt_flushes <= '0;
    end else if (!halted) begin
      cnt_cycles <= cnt_cycles + 1;
      if (mem_wb.valid && !mem_wb.ctrl.illegal) cnt_instret <= cnt_instret + 1;
      if (stall && !redirect)                   cnt_stalls  <= cnt_stalls  + 1;
      if (redirect)                             cnt_flushes <= cnt_flushes + 1;
    end
  end

endmodule
