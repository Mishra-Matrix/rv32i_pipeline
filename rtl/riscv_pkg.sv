//-----------------------------------------------------------------------------
// riscv_pkg : shared definitions for the RV32I pipeline
//-----------------------------------------------------------------------------
package riscv_pkg;

  // Major opcodes (instr[6:0])
  localparam logic [6:0] OP_LUI    = 7'b0110111;
  localparam logic [6:0] OP_AUIPC  = 7'b0010111;
  localparam logic [6:0] OP_JAL    = 7'b1101111;
  localparam logic [6:0] OP_JALR   = 7'b1100111;
  localparam logic [6:0] OP_BRANCH = 7'b1100011;
  localparam logic [6:0] OP_LOAD   = 7'b0000011;
  localparam logic [6:0] OP_STORE  = 7'b0100011;
  localparam logic [6:0] OP_IMM    = 7'b0010011;
  localparam logic [6:0] OP_REG    = 7'b0110011;
  localparam logic [6:0] OP_FENCE  = 7'b0001111;
  localparam logic [6:0] OP_SYSTEM = 7'b1110011;

  localparam logic [31:0] INSTR_NOP    = 32'h0000_0013;   // addi x0, x0, 0
  localparam logic [31:0] INSTR_ECALL  = 32'h0000_0073;
  localparam logic [31:0] INSTR_EBREAK = 32'h0010_0073;

  typedef enum logic [3:0] {
    ALU_ADD, ALU_SUB, ALU_SLL, ALU_SLT, ALU_SLTU,
    ALU_XOR, ALU_SRL, ALU_SRA, ALU_OR,  ALU_AND
  } alu_op_t;

  typedef enum logic [2:0] {IMM_I, IMM_S, IMM_B, IMM_U, IMM_J} imm_sel_t;

  typedef enum logic [1:0] {SRC_A_RS1, SRC_A_PC, SRC_A_ZERO} src_a_t;

  typedef enum logic [1:0] {WB_ALU, WB_MEM, WB_PC4} wb_sel_t;

  // Operand source in EX: register file value, EX/MEM result or MEM/WB result
  typedef enum logic [1:0] {FWD_NONE, FWD_WB, FWD_MEM} fwd_sel_t;

  // Decoded control word. All-zero is a bubble (no architectural effect).
  typedef struct packed {
    logic     reg_write;    // write rd
    logic     mem_read;     // load
    logic     mem_write;    // store
    logic     branch;       // conditional branch
    logic     jal;
    logic     jalr;
    logic     src_b_imm;    // ALU operand B: 1 = immediate, 0 = rs2
    src_a_t   src_a;        // ALU operand A: rs1 / pc / zero
    alu_op_t  alu_op;
    imm_sel_t imm_sel;
    wb_sel_t  wb_sel;       // write-back source
    logic     halt;         // ecall / ebreak
    logic     illegal;      // unsupported or malformed instruction
  } ctrl_t;

endpackage
