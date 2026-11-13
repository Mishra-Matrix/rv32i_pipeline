//-----------------------------------------------------------------------------
// dmem : data RAM with byte enables, asynchronous read, synchronous write.
//   Word addressed by addr[AW+1:2]; higher address bits are not decoded, so
//   the RARS data segment at 0x2000 maps to word 0.
//-----------------------------------------------------------------------------
module dmem #(
  parameter int WORDS = 1024
) (
  input  logic        clk,
  input  logic        we,
  input  logic [3:0]  be,
  input  logic [31:0] addr,
  input  logic [31:0] wdata,
  output logic [31:0] rdata
);

  localparam int AW = $clog2(WORDS);

  logic [31:0]   mem [WORDS];
  logic [AW-1:0] idx;

  assign idx = addr[AW+1:2];

  initial begin
    for (int i = 0; i < WORDS; i++) mem[i] = '0;
  end

  always @(posedge clk) begin
    if (we) begin
      for (int b = 0; b < 4; b++)
        if (be[b]) mem[idx][8*b +: 8] <= wdata[8*b +: 8];
    end
  end

  assign rdata = mem[idx];

endmodule
