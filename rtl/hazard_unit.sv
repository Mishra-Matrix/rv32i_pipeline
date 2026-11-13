//-----------------------------------------------------------------------------
// hazard_unit : load-use detection.
//   A load in EX whose rd is a source of the instruction in ID cannot be
//   forwarded in time; the instruction in ID waits one cycle (PC and IF/ID
//   hold, a bubble enters ID/EX) and then receives the value from MEM/WB.
//   Source addresses of unused operands are zero, so they never match.
//-----------------------------------------------------------------------------
module hazard_unit (
  input  logic       id_valid,
  input  logic [4:0] id_rs1,
  input  logic [4:0] id_rs2,
  input  logic       ex_valid,
  input  logic       ex_mem_read,
  input  logic [4:0] ex_rd,
  output logic       load_use_stall
);

  assign load_use_stall = id_valid && ex_valid && ex_mem_read && (ex_rd != 5'd0) &&
                          ((ex_rd == id_rs1) || (ex_rd == id_rs2));

endmodule
