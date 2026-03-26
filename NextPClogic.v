module NextPClogic(NextPC, CurrentPC, SignExtImm64, Branch, ALUZero, Uncondbranch); 

       input [63:0] CurrentPC, SignExtImm64; // SignExtImm64 is the output of the sign extender

       // Branch is true if the current instruction is a conditional branch instruction
       // Uncondbranch is true if the current instruction is an Unconditional Branch (B)
       // ALUZero is the Zero output of the ALU
       input Branch, ALUZero, Uncondbranch;
       output [63:0] NextPC; 

       // additions with a constant should have a delay of 1
       // general addition should have a delay of 2
       // any multiplexers should have a delay of 1 (includes statements inside if/else statements)
       wire [63:0] shiftSignExt = SignExtImm64; // shift left 2

       wire muxControl = (Branch && ALUZero) || Uncondbranch; // gate logic

       wire [63:0] muxOutput; // result of MUX
       assign muxOutput = muxControl ? shiftSignExt : 4;

       wire [63:0] sum = CurrentPC + muxOutput;
       assign NextPC = muxControl ? #3 sum : #2 sum;
endmodule