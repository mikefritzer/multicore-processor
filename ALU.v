`define AND   4'b0000
`define OR    4'b0001
`define ADD   4'b0010
`define SUB   4'b0110
`define PassB 4'b0111
`define MADD  4'b1001
`define VADD8 4'b1010
`define VMUL8 4'b1011


module ALU(BusW, BusA, BusB, ALUCtrl, Zero);
    
    parameter n = 64;

    output  [n-1:0] BusW;
    input   [n-1:0] BusA, BusB;
    input   [3:0] ALUCtrl;
    output  Zero;
    
    reg     [n-1:0] BusW;
    
    always @(ALUCtrl or BusA or BusB) begin
        case(ALUCtrl)
            `AND:   BusW = #20 BusA & BusB;
            `OR:    BusW = #20 BusA | BusB;
            `ADD:   BusW = #20 BusA + BusB;
            `SUB:   BusW = #20 BusA - BusB;
            `PassB: BusW = #20 BusB;
            `MADD:  BusW = #20 (BusA * BusB) + BusW;
            `VADD8: BusW = #20 { (BusA[7:0] + BusB[7:0]),
                                 (BusA[15:8] + BusB[15:8]),
                                 (BusA[23:16] + BusB[23:16]),
                                 (BusA[31:24] + BusB[31:24]),
                                 (BusA[39:32] + BusB[39:32]),
                                 (BusA[47:40] + BusB[47:40]),
                                 (BusA[55:48] + BusB[55:48]),
                                 (BusA[63:56] + BusB[63:56]) };
            `VMUL8: BusW = #20 { (BusA[7:0] * BusB[7:0]),
                                 (BusA[15:8] * BusB[15:8]),
                                 (BusA[23:16] * BusB[23:16]),
                                 (BusA[31:24] * BusB[31:24]),
                                 (BusA[39:32] * BusB[39:32]),
                                 (BusA[47:40] * BusB[47:40]),
                                 (BusA[55:48] * BusB[55:48]),
                                 (BusA[63:56] * BusB[63:56]) };
            default: BusW = 64'b0; // Prevent latches
        endcase
    end

    assign #1 Zero = (BusW == 0);
endmodule
