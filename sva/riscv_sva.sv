//-----------------------------------------------------------------------------
// riscv_sva : pipeline assertions for riscv_core, attached with `bind`
//   Fetch / redirect  - PC alignment, redirect lands on the target, flushed
//                       slots become bubbles
//   Load-use          - stall holds PC and IF/ID, inserts a bubble, and a load
//                       result is never consumed from EX/MEM
//   Bubbles           - an invalid slot carries no control (no side effects)
//   Architectural     - x0 stays zero, no X on operands / write-back data,
//                       aligned memory accesses
//   Halt              - fetch stops, PC freezes, no writes once halted
//-----------------------------------------------------------------------------
module riscv_sva
  import riscv_pkg::*;
(
  input logic        clk,
  input logic        rst_n,
  input logic [31:0] pc,
  input logic        stall,
  input logic        redirect,
  input logic [31:0] redirect_target,
  input logic        halt_pending,
  input logic        halted,
  input logic        if_id_valid,
  input logic [31:0] if_id_pc,
  input logic [31:0] if_id_instr,
  input logic        id_ex_valid,
  input var ctrl_t   id_ex_ctrl,
  input logic [4:0]  id_ex_rs1,
  input logic [4:0]  id_ex_rs2,
  input logic        ex_mem_valid,
  input var ctrl_t   ex_mem_ctrl,
  input logic [4:0]  ex_mem_rd,
  input logic [2:0]  ex_mem_funct3,
  input logic [31:0] ex_mem_addr,
  input fwd_sel_t    fwd_a,
  input fwd_sel_t    fwd_b,
  input logic [31:0] ex_rs1_val,
  input logic [31:0] ex_rs2_val,
  input logic        rf_we,
  input logic [4:0]  rf_rd,
  input logic [31:0] rf_wdata,
  input logic [31:0] x0_value,
  input logic        dmem_we
);

  default clocking cb @(posedge clk); endclocking

  logic access_aligned;
  always_comb begin
    case (ex_mem_funct3[1:0])
      2'b00:   access_aligned = 1'b1;                       // byte
      2'b01:   access_aligned = (ex_mem_addr[0]   == 1'b0); // halfword
      default: access_aligned = (ex_mem_addr[1:0] == 2'b00);// word
    endcase
  end

  //---------------------------------------------------------------------------
  // Fetch and redirect
  //---------------------------------------------------------------------------
  a_pc_aligned: assert property (disable iff (!rst_n)
    pc[1:0] == 2'b00)
    else $error("SVA: PC 0x%08h not word aligned", pc);

  a_target_aligned: assert property (disable iff (!rst_n)
    redirect |-> redirect_target[1:0] == 2'b00)
    else $error("SVA: branch/jump target 0x%08h not word aligned", redirect_target);

  a_redirect_from_valid: assert property (disable iff (!rst_n)
    redirect |-> id_ex_valid)
    else $error("SVA: redirect from a bubble");

  a_redirect_sets_pc: assert property (disable iff (!rst_n)
    redirect |=> pc == $past(redirect_target))
    else $error("SVA: PC did not move to the branch/jump target");

  a_redirect_flushes: assert property (disable iff (!rst_n)
    redirect |=> (!if_id_valid && !id_ex_valid))
    else $error("SVA: wrong-path instructions not flushed");

  //---------------------------------------------------------------------------
  // Load-use stall and forwarding
  //---------------------------------------------------------------------------
  a_stall_redirect_exclusive: assert property (disable iff (!rst_n)
    !(stall && redirect))
    else $error("SVA: stall and redirect in the same cycle");

  a_stall_holds_pc: assert property (disable iff (!rst_n)
    stall |=> $stable(pc))
    else $error("SVA: PC advanced during a load-use stall");

  a_stall_holds_if_id: assert property (disable iff (!rst_n)
    stall |=> (if_id_valid && $stable(if_id_pc) && $stable(if_id_instr)))
    else $error("SVA: IF/ID changed during a load-use stall");

  a_stall_inserts_bubble: assert property (disable iff (!rst_n)
    stall |=> !id_ex_valid)
    else $error("SVA: no bubble inserted after a load-use stall");

  a_no_forward_from_load: assert property (disable iff (!rst_n)
    (fwd_a == FWD_MEM || fwd_b == FWD_MEM) |-> !ex_mem_ctrl.mem_read)
    else $error("SVA: load result forwarded from EX/MEM before it was read");

  a_load_use_resolved: assert property (disable iff (!rst_n)
    !(id_ex_valid && ex_mem_valid && ex_mem_ctrl.mem_read && ex_mem_rd != 5'd0 &&
      (ex_mem_rd == id_ex_rs1 || ex_mem_rd == id_ex_rs2)))
    else $error("SVA: unresolved load-use hazard reached EX");

  //---------------------------------------------------------------------------
  // Bubbles have no effect
  //---------------------------------------------------------------------------
  a_id_ex_bubble: assert property (disable iff (!rst_n)
    !id_ex_valid |-> (id_ex_ctrl == '0))
    else $error("SVA: ID/EX bubble carries control signals");

  a_ex_mem_bubble: assert property (disable iff (!rst_n)
    !ex_mem_valid |-> (ex_mem_ctrl == '0))
    else $error("SVA: EX/MEM bubble carries control signals");

  //---------------------------------------------------------------------------
  // Architectural state
  //---------------------------------------------------------------------------
  a_x0_zero: assert property (disable iff (!rst_n)
    x0_value == '0)
    else $error("SVA: x0 is not zero");

  a_instr_known: assert property (disable iff (!rst_n)
    if_id_valid |-> !$isunknown(if_id_instr))
    else $error("SVA: X/Z instruction fetched at 0x%08h", if_id_pc);

  a_operands_known: assert property (disable iff (!rst_n)
    id_ex_valid |-> !$isunknown({ex_rs1_val, ex_rs2_val}))
    else $error("SVA: X/Z operand in EX");

  a_wb_known: assert property (disable iff (!rst_n)
    rf_we |-> !$isunknown({rf_rd, rf_wdata}))
    else $error("SVA: X/Z register write-back");

  a_store_aligned: assert property (disable iff (!rst_n)
    dmem_we |-> access_aligned)
    else $error("SVA: misaligned store to 0x%08h", ex_mem_addr);

  a_load_aligned: assert property (disable iff (!rst_n)
    (ex_mem_valid && ex_mem_ctrl.mem_read) |-> access_aligned)
    else $error("SVA: misaligned load from 0x%08h", ex_mem_addr);

  //---------------------------------------------------------------------------
  // Halt
  //---------------------------------------------------------------------------
  a_halt_stops_fetch: assert property (disable iff (!rst_n)
    halt_pending |-> !if_id_valid)
    else $error("SVA: instruction fetched after ECALL/EBREAK");

  a_halt_freezes_pc: assert property (disable iff (!rst_n)
    halt_pending |=> $stable(pc))
    else $error("SVA: PC changed after ECALL/EBREAK");

  a_halted_sticky: assert property (disable iff (!rst_n)
    halted |=> halted)
    else $error("SVA: halted deasserted without reset");

  a_no_write_after_halt: assert property (disable iff (!rst_n)
    halted |-> (!rf_we && !dmem_we))
    else $error("SVA: register or memory written after halt");

  //---------------------------------------------------------------------------
  // Coverage
  //---------------------------------------------------------------------------
  c_stall:           cover property (disable iff (!rst_n) stall);
  c_redirect:        cover property (disable iff (!rst_n) redirect);
  c_fwd_a_ex_mem:    cover property (disable iff (!rst_n) id_ex_valid && fwd_a == FWD_MEM);
  c_fwd_a_mem_wb:    cover property (disable iff (!rst_n) id_ex_valid && fwd_a == FWD_WB);
  c_fwd_b_ex_mem:    cover property (disable iff (!rst_n) id_ex_valid && fwd_b == FWD_MEM);
  c_fwd_b_mem_wb:    cover property (disable iff (!rst_n) id_ex_valid && fwd_b == FWD_WB);
  c_stall_on_store:  cover property (disable iff (!rst_n) stall ##1 (id_ex_valid && id_ex_ctrl.mem_write));
  c_back_to_back_br: cover property (disable iff (!rst_n) redirect ##3 redirect);
  c_halted:          cover property (disable iff (!rst_n) halted);

endmodule

//-----------------------------------------------------------------------------
// Bind into every riscv_core instance
//-----------------------------------------------------------------------------
bind riscv_core riscv_sva u_riscv_sva (
  .clk             (clk),
  .rst_n           (rst_n),
  .pc              (pc),
  .stall           (stall),
  .redirect        (redirect),
  .redirect_target (redirect_target),
  .halt_pending    (halt_pending),
  .halted          (halted),
  .if_id_valid     (if_id.valid),
  .if_id_pc        (if_id.pc),
  .if_id_instr     (if_id.instr),
  .id_ex_valid     (id_ex.valid),
  .id_ex_ctrl      (id_ex.ctrl),
  .id_ex_rs1       (id_ex.rs1),
  .id_ex_rs2       (id_ex.rs2),
  .ex_mem_valid    (ex_mem.valid),
  .ex_mem_ctrl     (ex_mem.ctrl),
  .ex_mem_rd       (ex_mem.rd),
  .ex_mem_funct3   (ex_mem.funct3),
  .ex_mem_addr     (ex_mem.result),
  .fwd_a           (fwd_a),
  .fwd_b           (fwd_b),
  .ex_rs1_val      (ex_rs1_val),
  .ex_rs2_val      (ex_rs2_val),
  .rf_we           (rf_we),
  .rf_rd           (rf_rd),
  .rf_wdata        (rf_wdata),
  .x0_value        (u_rf.regs[0]),
  .dmem_we         (dmem_we)
);
