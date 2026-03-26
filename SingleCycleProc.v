module singlecycle(
    input resetl,
    input [63:0] startpc,
    output reg [63:0] currentpc,
    output [63:0] dmemout,
    input CLK
);

    // Next PC connections
    wire [63:0] nextpc;       // The next PC, to be updated on clock cycle

    // Instruction Memory connections
    wire [31:0] instruction;  // The current instruction

    // Parts of instruction
    wire [4:0] rd;            // The destination register
    wire [4:0] rm;            // Operand 1
    wire [4:0] rn;            // Operand 2
    wire [4:0] rc;            // Operand 3
    wire [10:0] opcode;

    // Connect Cache to Main Memory
    wire [63:0] main_memaddr;
    wire [63:0] main_memwritedata;
    wire [63:0] main_memreaddata;
    wire main_memread;
    wire main_memwrite;
    wire cachehit;
    wire cachemiss;

    // Control wires
    wire reg2loc;
    wire alusrc;
    wire mem2reg;
    wire regwrite;
    wire memread;
    wire memwrite;
    wire branch;
    wire uncond_branch;
    wire set_flags;
    wire csel;
    wire [3:0] aluctrl;
    wire [2:0] signop;

    // Register file connections
    wire [63:0] regoutA;     // Output A
    wire [63:0] regoutB;     // Output B
    wire [63:0] regoutC;     // Output C

    // ALU connections
    wire [63:0] aluout;
    wire zero;

    // Sign Extender connections
    wire [63:0] extimm;

    // Stateful Zero flag
    reg flagz;

    // PC update logic
    always @(negedge CLK)
    begin
        if (resetl)
            currentpc <= nextpc;
            flagz <= zero; // update flagz with the current value of zero at the end of each cycle
        else
            currentpc <= startpc;
            flagz <= 1'b0; // reset flagz to 0 when reset is low
    end
    
    // Parts of instruction
    assign rd = instruction[4:0];
    assign rm = instruction[9:5];
    assign rn = reg2loc ? instruction[4:0] : instruction[20:16];
    assign rc = instruction[14:10];
    assign opcode = instruction[31:21];

    InstructionMemory imem(
        .Data(instruction),
        .Address(currentpc)
    );

    control control(
        .reg2loc(reg2loc),
        .alusrc(alusrc),
        .mem2reg(mem2reg),
        .regwrite(regwrite),
        .memread(memread),
        .memwrite(memwrite),
        .branch(branch),
        .uncond_branch(uncond_branch),
        .set_flags(set_flags),
        .csel(csel),
        .aluop(aluctrl),
        .signop(signop),
        .opcode(opcode)
    );

    /*
    * Connect the remaining datapath elements below.
    * Do not forget any additional multiplexers that may be required.
    */

    // sign extender
    SignExtender SignExtender(
        .BusImm(extimm),
        .Instr(instruction[25:0]),
        .Ctrl(signop)
    );

    // main ALU + corresponding mux
    wire [63:0] ALUMUX; // output of ALU's MUX
    assign ALUMUX = alusrc ? extimm : regoutB; // sign extender output if alusrc high, else regoutB
    ALU ALU(
        .BusW(aluout),
        .BusA(regoutA),
        .BusB(ALUMUX),
        .BusC(regoutC),
        .ALUCtrl(aluctrl),
        .Zero(zero)
    );

    // data memory + corresponding muxes
    wire [63:0] cselMUX; // output of CSEL MUX
    assign cselMUX = flagz ? regoutA : regoutB; // if flagz is 1, select regoutA, else select regoutB

    wire [63:0] dataMUX; // output of data memory MUX
    assign dataMUX = csel ? cselMUX : (mem2reg ? dmemout : aluout); // if csel is 1, select cselMUX, else select mem2reg output (which is either dmemout or aluout)
    
    DataCache L1_Cache(
        .Address(aluout),
        .WriteData(regoutB),
        .MemoryRead(memread),
        .MemoryWrite(memwrite),
        .Clock(CLK),
        .ReadData(dmemout),         // CPU gets data from cache
        
        // Connections to main memory
        .MemAddress(main_mem_addr),
        .MemWriteData(main_mem_writedata),
        .MemRead(main_mem_read),
        .MemWrite(main_mem_write),
        .MemReadData(main_mem_readdata),
        
        // Performance
        .CacheHit(cache_hit),
        .CacheMiss(cache_miss)
    );

    DataMemory DataMemory(
        .ReadData(main_mem_readdata),
        .Address(main_mem_addr),
        .WriteData(main_mem_writedata),
        .MemoryRead(main_mem_read),
        .MemoryWrite(main_mem_write),
        .Clock(CLK)
    );

    // register file + corresponding mux
    RegisterFile RegisterFile(
        .BusA(regoutA),
        .BusB(regoutB),
        .BusC(regoutC),
        .BusW(dataMUX),
        .RA(rm),
        .RB(rn),
        .RC(rc),
        .RW(rd),
        .RegWr(regwrite),
        .Clk(CLK)
    );

    // next PC logic
    NextPClogic NextPClogic(
        .NextPC(nextpc),
        .CurrentPC(currentpc),
        .SignExtImm64(extimm),
        .Branch(branch),
        .ALUZero(zero),
        .Uncondbranch(uncond_branch)
    );
endmodule

