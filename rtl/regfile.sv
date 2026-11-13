//-----------------------------------------------------------------------------
// regfile : 32 x 32-bit register file, 2 asynchronous read ports, 1 write port.
//   - x0 always reads as zero; writes to x0 are ignored.
//   - Write-through: a read of the register being written in the same cycle
//     returns the new value (resolves the WB -> ID hazard).
//   - No reset, so the array maps onto LUT RAM; contents start at zero.
//-----------------------------------------------------------------------------
module regfile (
  input  logic        clk,

  input  logic [4:0]  rs1_addr,
  output logic [31:0] rs1_data,
  input  logic [4:0]  rs2_addr,
  output logic [31:0] rs2_data,

  input  logic        we,
  input  logic [4:0]  rd_addr,
  input  logic [31:0] rd_data
);

  logic [31:0] regs [32];

  initial begin
    for (int i = 0; i < 32; i++) regs[i] = '0;
  end

  always @(posedge clk) begin
    if (we && rd_addr != 5'd0) regs[rd_addr] <= rd_data;
  end

  assign rs1_data = (rs1_addr == 5'd0)              ? '0      :
                    (we && rd_addr == rs1_addr)     ? rd_data :
                                                      regs[rs1_addr];

  assign rs2_data = (rs2_addr == 5'd0)              ? '0      :
                    (we && rd_addr == rs2_addr)     ? rd_data :
                                                      regs[rs2_addr];

endmodule
