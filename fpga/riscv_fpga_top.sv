//-----------------------------------------------------------------------------
// riscv_fpga_top : synthesis top level
//   Core with an instruction ROM initialised from IMEM_FILE and a data RAM.
//   Data-memory writes are registered onto output ports, so every result the
//   program produces is observable and the full datapath is kept by synthesis.
//-----------------------------------------------------------------------------
module riscv_fpga_top #(
  parameter int IMEM_WORDS = 1024,       // 4 KB instruction ROM
  parameter int DMEM_WORDS = 256,        // 1 KB data RAM
  parameter     IMEM_FILE  = "sort.mem"
) (
  input  logic        clk,
  input  logic        rst_n,
  output logic        halted,
  output logic        illegal_instr,
  output logic        store_valid,       // a store completed last cycle
  output logic [31:0] store_addr,
  output logic [31:0] store_data
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

  always_ff @(posedge clk) begin
    if (!rst_n) begin
      store_valid <= 1'b0;
      store_addr  <= '0;
      store_data  <= '0;
    end else begin
      store_valid <= dmem_we;
      if (dmem_we) begin
        store_addr <= dmem_addr;
        store_data <= dmem_wdata;
      end
    end
  end

endmodule
