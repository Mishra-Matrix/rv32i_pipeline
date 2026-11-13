//-----------------------------------------------------------------------------
// imem : instruction ROM, asynchronous read, word addressed by pc[AW+1:2].
//   INIT_FILE is a $readmemh image (one 32-bit word per line), e.g. a RARS
//   ".text" dump with the "Compact, Text at Address 0" memory configuration.
//-----------------------------------------------------------------------------
module imem #(
  parameter int WORDS     = 1024,
  parameter     INIT_FILE = ""
) (
  input  logic [31:0] addr,
  output logic [31:0] rdata
);

  localparam int AW = $clog2(WORDS);

  logic [31:0] mem [WORDS];

  initial begin
    if (INIT_FILE != "") $readmemh(INIT_FILE, mem);
  end

  assign rdata = mem[addr[AW+1:2]];

endmodule
