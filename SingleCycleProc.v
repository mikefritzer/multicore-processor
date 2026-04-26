// Two-stage pipelined core: IF (fetch + register read) | EX (decode, execute, memory, writeback).
//
// Branch penalty   : 1 cycle (taken branch flushes the IF stage).
// Data forwarding  : EX result is forwarded to the IF/EX latch to resolve RAW hazards.
// Flag hazard      : flagz updates at end of EX; a CBZ/CSEL immediately after SUBS sees
//                    the new flag because the flag is registered and updated on posedge CLK,
//                    matching the IF/EX latch update.
// Stall sources    : BARRIER (wait for all cores) and ATOMIC_CAS (2-cycle RMW).
//
// Port notes:
//   - main_mem_* exposes the cache miss path; in single-core sim connect directly to DataMemory.
//   - In the SoC top, these ports connect to MemArbiter inputs.
//   - barrier_req / barrier_ack are open-collector style: core asserts req, SoC asserts ack.

`timescale 1ns/1ps

module core (
    input  wire        CLK,
    input  wire        resetl,
    input  wire [63:0] startpc,
    input  wire [31:0] core_id,

    // Memory arbiter interface
    output wire [63:0] main_mem_addr,
    output wire [63:0] main_mem_writedata,
    output wire        main_mem_read,
    output wire        main_mem_write,
    input  wire [63:0] main_mem_readdata,
    input  wire        main_mem_grant,   // unused in single-core; tie to 1

    // Synchronization (connect to SoC barrier register / CAS lock)
    output reg         barrier_req,
    input  wire        barrier_ack,
    output wire        cas_bus_req,      // request to hold the memory bus for CAS

    // Observation
    output wire [63:0] dmemout,
    output wire [63:0] currentpc
);

    // =========================================================
    //  IF STAGE — wires
    // =========================================================
    reg  [63:0] pc_reg;
    wire [31:0] if_instruction;

    wire [4:0]  if_rd = if_instruction[4:0];
    wire [4:0]  if_rm = if_instruction[9:5];
    wire [4:0]  if_rc = if_instruction[14:10];
    wire [10:0] if_op = if_instruction[31:21];

    // reg2loc for the IF instruction — needed to select the right RB port address
    // before full decode. We decode just this one signal combinationally.
    wire if_reg2loc;
    assign if_reg2loc = (if_op ==? 11'b?011010????) | // CBZ
                        (if_op ==? 11'b??111000000);  // STUR

    wire [4:0] if_rn = if_reg2loc ? if_instruction[4:0] : if_instruction[20:16];

    wire [63:0] if_regoutA, if_regoutB, if_regoutC;

    // =========================================================
    //  EX STAGE — signals from IF/EX pipeline register
    // =========================================================
    reg [31:0] ex_instruction;
    reg [63:0] ex_pc;
    reg [63:0] ex_regA, ex_regB, ex_regC;
    reg        ex_valid;        // 0 = bubble (no-op)

    // Extract EX instruction fields
    wire [4:0]  ex_rd     = ex_instruction[4:0];
    wire [4:0]  ex_rm     = ex_instruction[9:5];
    wire [10:0] ex_opcode = ex_instruction[31:21];

    // =========================================================
    //  EX STAGE — control signals
    // =========================================================
    wire ex_reg2loc, ex_alusrc, ex_mem2reg, ex_regwrite;
    wire ex_memread, ex_memwrite;
    wire ex_branch, ex_uncond_branch, ex_set_flags, ex_csel;
    wire ex_atomic_cas, ex_barrier;
    wire [3:0] ex_aluctrl;
    wire [2:0] ex_signop;

    control ex_ctrl (
        .reg2loc      (ex_reg2loc),
        .alusrc       (ex_alusrc),
        .mem2reg      (ex_mem2reg),
        .regwrite     (ex_regwrite),
        .memread      (ex_memread),
        .memwrite     (ex_memwrite),
        .branch       (ex_branch),
        .uncond_branch(ex_uncond_branch),
        .set_flags    (ex_set_flags),
        .csel         (ex_csel),
        .atomic_cas   (ex_atomic_cas),
        .barrier      (ex_barrier),
        .aluop        (ex_aluctrl),
        .signop       (ex_signop),
        .opcode       (ex_opcode)
    );

    // Suppress all control effects for a bubble
    wire ctrl_regwrite      = ex_valid & ex_regwrite;
    wire ctrl_memread       = ex_valid & ex_memread;
    wire ctrl_memwrite      = ex_valid & ex_memwrite;
    wire ctrl_branch        = ex_valid & ex_branch;
    wire ctrl_uncond_branch = ex_valid & ex_uncond_branch;
    wire ctrl_set_flags     = ex_valid & ex_set_flags;
    wire ctrl_csel          = ex_valid & ex_csel;
    wire ctrl_atomic_cas    = ex_valid & ex_atomic_cas;
    wire ctrl_barrier_sig   = ex_valid & ex_barrier;

    // =========================================================
    //  EX STAGE — sign extender
    // =========================================================
    wire [63:0] extimm;
    SignExtender SignExtender (
        .BusImm(extimm),
        .Instr (ex_instruction[25:0]),
        .Ctrl  (ex_signop)
    );

    // =========================================================
    //  EX STAGE — ALU
    // =========================================================
    wire [63:0] alu_inB   = ex_alusrc ? extimm : ex_regB;
    wire [63:0] aluout;
    wire        alu_zero;

    ALU alu (
        .BusW   (aluout),
        .BusA   (ex_regA),
        .BusB   (alu_inB),
        .BusC   (ex_regC),
        .ALUCtrl(ex_aluctrl),
        .Zero   (alu_zero)
    );

    // =========================================================
    //  EX STAGE — flagz (registered zero flag, gated by set_flags)
    // =========================================================
    reg flagz;

    // =========================================================
    //  EX STAGE — CAS state machine
    // =========================================================
    // Phase 0: CAS enters EX, do the read.
    // Phase 1: stall; do the conditional write.
    reg cas_phase;   // 0 = read phase, 1 = write phase
    reg [63:0] cas_read_val;

    wire cas_active = ctrl_atomic_cas;
    // Stall the pipeline when in CAS write phase or waiting for bus grant during CAS
    wire cas_stall  = cas_active && (cas_phase == 1'b0);
    // bus_req is raised during both CAS phases so the arbiter holds the lock
    assign cas_bus_req = cas_active;

    // =========================================================
    //  EX STAGE — barrier stall
    // =========================================================
    wire barrier_stall = barrier_req && !barrier_ack;

    // Combined stall
    wire stall = cas_stall || barrier_stall;

    // =========================================================
    //  EX STAGE — data memory (cache)
    // =========================================================
    wire [63:0] cas_write_data = (cas_phase == 1'b1) ?
                                  (cas_read_val == ex_regB ? ex_regC : 64'bx) :
                                  ex_regB;
    wire do_memread  = ctrl_memread  && !(cas_active && cas_phase == 1'b1);
    wire do_memwrite = ctrl_memwrite && !(cas_active && cas_phase == 1'b0);
    wire [63:0] mem_write_src = cas_active ? cas_write_data : ex_regB;

    DataCache #(.LOG2_LINES(6)) L1 (
        .Address      (aluout),
        .WriteData    (mem_write_src),
        .MemoryRead   (do_memread),
        .MemoryWrite  (do_memwrite),
        .Clock        (CLK),
        .ReadData     (dmemout),
        .MemAddress   (main_mem_addr),
        .MemWriteData (main_mem_writedata),
        .MemRead      (main_mem_read),
        .MemWrite     (main_mem_write),
        .MemReadData  (main_mem_readdata),
        .CacheHit     (),
        .CacheMiss    ()
    );

    // =========================================================
    //  EX STAGE — CSEL mux, writeback mux
    // =========================================================
    wire [63:0] csel_out  = flagz ? ex_regA : ex_regB;
    wire [63:0] wb_data   = ctrl_csel  ? csel_out :
                            ctrl_atomic_cas ? (cas_phase == 1'b1 ? cas_read_val : dmemout) :
                            ex_mem2reg ? dmemout : aluout;

    // =========================================================
    //  EX STAGE — register file
    // =========================================================
    RegisterFile RegFile (
        .BusA  (if_regoutA),
        .BusB  (if_regoutB),
        .BusC  (if_regoutC),
        .BusW  (wb_data),
        .RA    (if_rm),
        .RB    (if_rn),
        .RC    (if_rc),
        .RW    (ex_rd),
        .RegWr (ctrl_regwrite && !stall),
        .Clk   (CLK)
    );

    // =========================================================
    //  EX STAGE — next PC logic
    // =========================================================
    wire [63:0] nextpc;
    NextPClogic NextPClogic (
        .NextPC       (nextpc),
        .CurrentPC    (ex_pc),
        .SignExtImm64 (extimm),
        .Branch       (ctrl_branch),
        .ALUZero      (alu_zero),
        .Uncondbranch (ctrl_uncond_branch)
    );

    wire branch_taken = (ctrl_branch && alu_zero) || ctrl_uncond_branch;

    // =========================================================
    //  Forwarding: EX result -> IF/EX latch
    // =========================================================
    // If the instruction currently in EX writes a register that the
    // instruction currently in IF reads, substitute the EX result.
    wire fwd_cond_A = ctrl_regwrite && (ex_rd != 5'd31) && (ex_rd == if_rm);
    wire fwd_cond_B = ctrl_regwrite && (ex_rd != 5'd31) && (ex_rd == if_rn);
    wire fwd_cond_C = ctrl_regwrite && (ex_rd != 5'd31) && (ex_rd == if_rc);

    wire [63:0] latch_A = fwd_cond_A ? wb_data : if_regoutA;
    wire [63:0] latch_B = fwd_cond_B ? wb_data : if_regoutB;
    wire [63:0] latch_C = fwd_cond_C ? wb_data : if_regoutC;

    // =========================================================
    //  Instruction memory
    // =========================================================
    InstructionMemory imem (
        .Data   (if_instruction),
        .Address(pc_reg)
    );

    assign currentpc = pc_reg;

    // =========================================================
    //  Sequential: PC, IF/EX latch, flagz, CAS state
    // =========================================================
    always @(posedge CLK) begin
        if (!resetl) begin
            pc_reg         <= startpc;
            ex_instruction <= 32'b0;
            ex_pc          <= 64'b0;
            ex_regA        <= 64'b0;
            ex_regB        <= 64'b0;
            ex_regC        <= 64'b0;
            ex_valid       <= 1'b0;
            flagz          <= 1'b0;
            barrier_req    <= 1'b0;
            cas_phase      <= 1'b0;
        end else if (!stall) begin
            // --- PC update ---
            if (branch_taken)
                pc_reg <= nextpc;
            else
                pc_reg <= pc_reg + 64'd4;

            // --- IF/EX latch ---
            if (branch_taken) begin
                // Flush: insert bubble
                ex_instruction <= 32'b0;
                ex_valid       <= 1'b0;
            end else begin
                ex_instruction <= if_instruction;
                ex_pc          <= pc_reg;
                ex_regA        <= latch_A;
                ex_regB        <= latch_B;
                ex_regC        <= latch_C;
                ex_valid       <= 1'b1;
            end

            // --- flagz update (gated by set_flags) ---
            if (ctrl_set_flags)
                flagz <= alu_zero;

            // --- Barrier handshake ---
            if (ctrl_barrier_sig)
                barrier_req <= 1'b1;
            else if (barrier_ack)
                barrier_req <= 1'b0;

            // --- CAS phase advance ---
            if (cas_active) begin
                if (cas_phase == 1'b0) begin
                    cas_read_val <= dmemout;
                    cas_phase    <= 1'b1;
                end else begin
                    cas_phase <= 1'b0;
                end
            end
        end
        // On stall: PC and IF/EX register hold their values; writeback suppressed above.
    end

endmodule

// ---------------------------------------------------------------------------
// Backward-compatible single-core wrapper (used by SingleCycleProcTest.v).
// Instantiates core + DataMemory directly; no arbiter needed.
// ---------------------------------------------------------------------------
module singlecycle (
    input  wire        CLK,
    input  wire        resetl,
    input  wire [63:0] startpc,
    output wire [63:0] currentpc,
    output wire [63:0] dmemout
);
    wire [63:0] mm_addr, mm_wdata, mm_rdata;
    wire        mm_read, mm_write;

    core u_core (
        .CLK              (CLK),
        .resetl           (resetl),
        .startpc          (startpc),
        .core_id          (32'd0),
        .main_mem_addr    (mm_addr),
        .main_mem_writedata(mm_wdata),
        .main_mem_read    (mm_read),
        .main_mem_write   (mm_write),
        .main_mem_readdata(mm_rdata),
        .main_mem_grant   (1'b1),
        .barrier_req      (),
        .barrier_ack      (1'b1),
        .cas_bus_req      (),
        .dmemout          (dmemout),
        .currentpc        (currentpc)
    );

    DataMemory u_dmem (
        .ReadData   (mm_rdata),
        .Address    (mm_addr),
        .WriteData  (mm_wdata),
        .MemoryRead (mm_read),
        .MemoryWrite(mm_write),
        .Clock      (CLK)
    );
endmodule
