// ---- Opcode definitions ----
`define OPCODE_ANDREG  11'b?0001010???
`define OPCODE_ORRREG  11'b?0101010???
`define OPCODE_ADDREG  11'b?0?01011???
`define OPCODE_SUBREG  11'b?1?01011???
`define OPCODE_SUBS    11'b11101011???

`define OPCODE_ADDIMM  11'b?0?10001???
`define OPCODE_SUBIMM  11'b?1?10001???

`define OPCODE_MOVZ    11'b110100101??

`define OPCODE_B       11'b?00101?????
`define OPCODE_CBZ     11'b?011010????
`define OPCODE_CSEL    11'b10011010100

`define OPCODE_LDUR    11'b??111000010
`define OPCODE_STUR    11'b??111000000

`define OPCODE_MADD    11'b10011011000

// Vector / AI instructions
`define OPCODE_VADD8   11'b01001110000
`define OPCODE_VMUL8   11'b01001110001
`define OPCODE_VADD16  11'b01001110010
`define OPCODE_VMUL16  11'b01001110011
`define OPCODE_VADD32  11'b01001110100
`define OPCODE_VDOT8   11'b01001110101

// Synchronization instructions
`define OPCODE_CAS     11'b10000000001  // Atomic compare-and-swap
`define OPCODE_BARRIER 11'b10000000010  // Inter-core barrier

module control(
    output reg        reg2loc,
    output reg        alusrc,
    output reg        mem2reg,
    output reg        regwrite,
    output reg        memread,
    output reg        memwrite,
    output reg        branch,
    output reg        uncond_branch,
    output reg        set_flags,
    output reg        csel,
    output reg        atomic_cas,
    output reg        barrier,
    output reg [3:0]  aluop,
    output reg [2:0]  signop,
    input      [10:0] opcode
);

always @(*) begin
    // Safe defaults — prevents latches on any unhandled path
    reg2loc       = 1'b0;
    alusrc        = 1'b0;
    mem2reg       = 1'b0;
    regwrite      = 1'b0;
    memread       = 1'b0;
    memwrite      = 1'b0;
    branch        = 1'b0;
    uncond_branch = 1'b0;
    set_flags     = 1'b0;
    csel          = 1'b0;
    atomic_cas    = 1'b0;
    barrier       = 1'b0;
    aluop         = 4'b0010; // ADD
    signop        = 3'b000;

    casez (opcode)
        `OPCODE_ANDREG: begin
            regwrite  = 1'b1;
            aluop     = 4'b0000; // AND
        end

        `OPCODE_ORRREG: begin
            regwrite  = 1'b1;
            aluop     = 4'b0001; // OR
        end

        `OPCODE_ADDREG: begin
            regwrite  = 1'b1;
            aluop     = 4'b0010; // ADD
        end

        `OPCODE_SUBREG: begin
            regwrite  = 1'b1;
            aluop     = 4'b0110; // SUB
        end

        `OPCODE_SUBS: begin
            regwrite  = 1'b1;
            set_flags = 1'b1;
            aluop     = 4'b0110; // SUB
        end

        `OPCODE_ADDIMM: begin
            alusrc    = 1'b1;
            regwrite  = 1'b1;
            aluop     = 4'b0010; // ADD
            signop    = 3'b000;
        end

        `OPCODE_SUBIMM: begin
            alusrc    = 1'b1;
            regwrite  = 1'b1;
            aluop     = 4'b0110; // SUB
            signop    = 3'b000;
        end

        `OPCODE_MOVZ: begin
            alusrc    = 1'b1;
            regwrite  = 1'b1;
            aluop     = 4'b0111; // PassB (immediate)
            signop    = 3'b100;
        end

        `OPCODE_B: begin
            uncond_branch = 1'b1;
            signop        = 3'b010;
        end

        `OPCODE_CBZ: begin
            reg2loc = 1'b1;
            branch  = 1'b1;
            aluop   = 4'b0111; // PassB to get register value for zero check
            signop  = 3'b011;
        end

        `OPCODE_CSEL: begin
            regwrite = 1'b1;
            csel     = 1'b1;
            aluop    = 4'b0111; // PassB
        end

        `OPCODE_LDUR: begin
            alusrc   = 1'b1;
            memread  = 1'b1;
            mem2reg  = 1'b1;
            regwrite = 1'b1;
            aluop    = 4'b0010; // ADD (base + offset)
            signop   = 3'b001;
        end

        `OPCODE_STUR: begin
            reg2loc  = 1'b1;
            alusrc   = 1'b1;
            memwrite = 1'b1;
            aluop    = 4'b0010; // ADD (base + offset)
            signop   = 3'b001;
        end

        `OPCODE_MADD: begin
            regwrite = 1'b1;
            aluop    = 4'b1001; // MADD
        end

        `OPCODE_VADD8: begin
            regwrite = 1'b1;
            aluop    = 4'b1010;
        end

        `OPCODE_VMUL8: begin
            regwrite = 1'b1;
            aluop    = 4'b1011;
        end

        `OPCODE_VDOT8: begin
            regwrite = 1'b1;
            aluop    = 4'b1100;
        end

        `OPCODE_VADD16: begin
            regwrite = 1'b1;
            aluop    = 4'b1101;
        end

        `OPCODE_VMUL16: begin
            regwrite = 1'b1;
            aluop    = 4'b1110;
        end

        `OPCODE_VADD32: begin
            regwrite = 1'b1;
            aluop    = 4'b1111;
        end

        // CAS: address = regoutA (PassA through ALU), compare = regoutB,
        //      new value = regoutC, result written to rd
        `OPCODE_CAS: begin
            memread    = 1'b1;
            memwrite   = 1'b1;
            regwrite   = 1'b1;
            mem2reg    = 1'b1;
            atomic_cas = 1'b1;
            aluop      = 4'b0011; // PassA (address register goes straight through)
        end

        `OPCODE_BARRIER: begin
            barrier = 1'b1;
        end

        default: begin
            // All safe defaults already set above
        end
    endcase
end

endmodule
