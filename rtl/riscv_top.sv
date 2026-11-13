//-----------------------------------------------------------------------------
// riscv_top : core + instruction ROM + data RAM
//-----------------------------------------------------------------------------
module riscv_top #(
  parameter int IMEM_WORDS = 1024,     // 4 KB
  parameter int DMEM_WORDS = 1024,     // 4 KB
  parameter     IMEM_FILE  = ""
) (
  input  logic clk,
  input  logic rst_n,
  output logic halted,
  output logic illegal_instr
);

  logic [31:0] imem_addr, imem_rdata;
  logic        dmem_we;
  logic [3:0]  dmem_be;
  logic [31:0] dmem_addr, dmem_wdata, dmem_rdata;

  riscv_core u_core (
    .clk           (clk),
    .rst_n         (rst_n),
    .imem_addr     (imem_addr),
    .imem_rdata    (imem_rdata),
    .dmem_we       (dmem_we),
    .dmem_be       (dmem_be),
    .dmem_addr     (dmem_addr),
    .dmem_wdata    (dmem_wdata),
    .dmem_rdata    (dmem_rdata),
    .halted        (halted),
    .illegal_instr (illegal_instr)
  );

  imem #(
    .WORDS     (IMEM_WORDS),
    .INIT_FILE (IMEM_FILE)
  ) u_imem (
    .addr  (imem_addr),
    .rdata (imem_rdata)
  );

  dmem #(
    .WORDS (DMEM_WORDS)
  ) u_dmem (
    .clk   (clk),
    .we    (dmem_we),
    .be    (dmem_be),
    .addr  (dmem_addr),
    .wdata (dmem_wdata),
    .rdata (dmem_rdata)
  );

endmodule
