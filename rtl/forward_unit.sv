//-----------------------------------------------------------------------------
// forward_unit : selects the source of each EX operand.
//   EX/MEM (the newer result) has priority over MEM/WB. x0 is never forwarded.
//   Loads in EX/MEM never need forwarding here: the hazard unit stalls the
//   dependent instruction until the load reaches MEM/WB.
//-----------------------------------------------------------------------------
module forward_unit
  import riscv_pkg::*;
(
  input  logic [4:0] ex_rs1,
  input  logic [4:0] ex_rs2,
  input  logic       mem_reg_write,     // EX/MEM instruction writes rd
  input  logic [4:0] mem_rd,
  input  logic       wb_reg_write,      // MEM/WB instruction writes rd
  input  logic [4:0] wb_rd,
  output fwd_sel_t   fwd_a,
  output fwd_sel_t   fwd_b
);

  function automatic fwd_sel_t select(logic [4:0] rs,
                                      logic mem_we, logic [4:0] mrd,
                                      logic wb_we,  logic [4:0] wrd);
    if (rs != 5'd0 && mem_we && mrd == rs) return FWD_MEM;
    if (rs != 5'd0 && wb_we  && wrd == rs) return FWD_WB;
    return FWD_NONE;
  endfunction

  assign fwd_a = select(ex_rs1, mem_reg_write, mem_rd, wb_reg_write, wb_rd);
  assign fwd_b = select(ex_rs2, mem_reg_write, mem_rd, wb_reg_write, wb_rd);

endmodule
