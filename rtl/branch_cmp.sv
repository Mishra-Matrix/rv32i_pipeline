//-----------------------------------------------------------------------------
// branch_cmp : branch condition for BEQ/BNE/BLT/BGE/BLTU/BGEU (funct3)
//-----------------------------------------------------------------------------
module branch_cmp (
  input  logic [2:0]  funct3,
  input  logic [31:0] a,          // rs1
  input  logic [31:0] b,          // rs2
  output logic        taken
);

  always_comb begin
    case (funct3)
      3'b000:  taken = (a == b);                     // BEQ
      3'b001:  taken = (a != b);                     // BNE
      3'b100:  taken = ($signed(a) <  $signed(b));   // BLT
      3'b101:  taken = ($signed(a) >= $signed(b));   // BGE
      3'b110:  taken = (a <  b);                     // BLTU
      3'b111:  taken = (a >= b);                     // BGEU
      default: taken = 1'b0;
    endcase
  end

endmodule
