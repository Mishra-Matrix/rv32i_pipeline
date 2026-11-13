//-----------------------------------------------------------------------------
// control : RV32I instruction decoder
//   Supports the 37 RV32I computational, load/store, branch and jump
//   instructions. FENCE executes as a NOP (single in-order hart, no caches).
//   ECALL / EBREAK raise `halt`. Anything else, including CSR instructions and
//   reserved funct3/funct7 encodings, is flagged `illegal` and has no effect.
//-----------------------------------------------------------------------------
module control
  import riscv_pkg::*;
(
  input  logic [31:0] instr,
  output ctrl_t       ctrl
);

  logic [6:0] opcode;
  logic [2:0] funct3;
  logic [6:0] funct7;
  logic       illegal;

  assign opcode = instr[6:0];
  assign funct3 = instr[14:12];
  assign funct7 = instr[31:25];

  always_comb begin
    ctrl    = '0;
    illegal = 1'b0;

    case (opcode)
      OP_LUI: begin
        ctrl.reg_write = 1'b1;
        ctrl.src_a     = SRC_A_ZERO;
        ctrl.src_b_imm = 1'b1;
        ctrl.imm_sel   = IMM_U;
      end

      OP_AUIPC: begin
        ctrl.reg_write = 1'b1;
        ctrl.src_a     = SRC_A_PC;
        ctrl.src_b_imm = 1'b1;
        ctrl.imm_sel   = IMM_U;
      end

      OP_JAL: begin
        ctrl.reg_write = 1'b1;
        ctrl.jal       = 1'b1;
        ctrl.imm_sel   = IMM_J;
        ctrl.wb_sel    = WB_PC4;
      end

      OP_JALR: begin
        if (funct3 != 3'b000) illegal = 1'b1;
        ctrl.reg_write = 1'b1;
        ctrl.jalr      = 1'b1;
        ctrl.src_b_imm = 1'b1;
        ctrl.imm_sel   = IMM_I;
        ctrl.wb_sel    = WB_PC4;
      end

      OP_BRANCH: begin
        if (funct3 == 3'b010 || funct3 == 3'b011) illegal = 1'b1;
        ctrl.branch  = 1'b1;
        ctrl.imm_sel = IMM_B;
      end

      OP_LOAD: begin
        if (!(funct3 inside {3'b000, 3'b001, 3'b010, 3'b100, 3'b101})) illegal = 1'b1;
        ctrl.reg_write = 1'b1;
        ctrl.mem_read  = 1'b1;
        ctrl.src_b_imm = 1'b1;
        ctrl.imm_sel   = IMM_I;
        ctrl.wb_sel    = WB_MEM;
      end

      OP_STORE: begin
        if (!(funct3 inside {3'b000, 3'b001, 3'b010})) illegal = 1'b1;
        ctrl.mem_write = 1'b1;
        ctrl.src_b_imm = 1'b1;
        ctrl.imm_sel   = IMM_S;
      end

      OP_IMM: begin
        ctrl.reg_write = 1'b1;
        ctrl.src_b_imm = 1'b1;
        ctrl.imm_sel   = IMM_I;
        case (funct3)
          3'b000: ctrl.alu_op = ALU_ADD;
          3'b010: ctrl.alu_op = ALU_SLT;
          3'b011: ctrl.alu_op = ALU_SLTU;
          3'b100: ctrl.alu_op = ALU_XOR;
          3'b110: ctrl.alu_op = ALU_OR;
          3'b111: ctrl.alu_op = ALU_AND;
          3'b001: begin
            ctrl.alu_op = ALU_SLL;
            if (funct7 != 7'b0000000) illegal = 1'b1;
          end
          3'b101: begin
            if      (funct7 == 7'b0000000) ctrl.alu_op = ALU_SRL;
            else if (funct7 == 7'b0100000) ctrl.alu_op = ALU_SRA;
            else                           illegal     = 1'b1;
          end
          default: illegal = 1'b1;
        endcase
      end

      OP_REG: begin
        ctrl.reg_write = 1'b1;
        if (funct7 == 7'b0000000) begin
          case (funct3)
            3'b000: ctrl.alu_op = ALU_ADD;
            3'b001: ctrl.alu_op = ALU_SLL;
            3'b010: ctrl.alu_op = ALU_SLT;
            3'b011: ctrl.alu_op = ALU_SLTU;
            3'b100: ctrl.alu_op = ALU_XOR;
            3'b101: ctrl.alu_op = ALU_SRL;
            3'b110: ctrl.alu_op = ALU_OR;
            3'b111: ctrl.alu_op = ALU_AND;
            default: illegal = 1'b1;
          endcase
        end else if (funct7 == 7'b0100000 && funct3 == 3'b000) begin
          ctrl.alu_op = ALU_SUB;
        end else if (funct7 == 7'b0100000 && funct3 == 3'b101) begin
          ctrl.alu_op = ALU_SRA;
        end else begin
          illegal = 1'b1;
        end
      end

      OP_FENCE: begin
        if (funct3 != 3'b000) illegal = 1'b1;
      end

      OP_SYSTEM: begin
        if (instr == INSTR_ECALL || instr == INSTR_EBREAK) ctrl.halt = 1'b1;
        else                                               illegal   = 1'b1;
      end

      default: illegal = 1'b1;
    endcase

    // Base ISA instructions always have instr[1:0] = 2'b11
    if (instr[1:0] != 2'b11) illegal = 1'b1;

    // Illegal instructions are turned into a bubble that only reports the error
    if (illegal) begin
      ctrl         = '0;
      ctrl.illegal = 1'b1;
    end
  end

endmodule
