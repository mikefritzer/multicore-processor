// ALUCtrl encodings
`define AND    4'b0000
`define OR     4'b0001
`define ADD    4'b0010
`define PassA  4'b0011
`define SUB    4'b0110
`define PassB  4'b0111
`define MADD   4'b1001
`define VADD8  4'b1010
`define VMUL8  4'b1011
`define VDOT8  4'b1100   // 8x8-bit dot product -> 32-bit scalar in [31:0]
`define VADD16 4'b1101   // 4x16-bit SIMD add
`define VMUL16 4'b1110   // 4x16-bit SIMD multiply (lower 16 bits of each product)
`define VADD32 4'b1111   // 2x32-bit SIMD add

module ALU(BusW, BusA, BusB, BusC, ALUCtrl, Zero);

    parameter n = 64;

    output reg [n-1:0] BusW;
    input  [n-1:0] BusA, BusB, BusC;
    input  [3:0]   ALUCtrl;
    output         Zero;

    // --- VMUL8 partial products (8x 8-bit -> 16-bit each) ---
    wire [15:0] v8p0 = BusA[7:0]   * BusB[7:0];
    wire [15:0] v8p1 = BusA[15:8]  * BusB[15:8];
    wire [15:0] v8p2 = BusA[23:16] * BusB[23:16];
    wire [15:0] v8p3 = BusA[31:24] * BusB[31:24];
    wire [15:0] v8p4 = BusA[39:32] * BusB[39:32];
    wire [15:0] v8p5 = BusA[47:40] * BusB[47:40];
    wire [15:0] v8p6 = BusA[55:48] * BusB[55:48];
    wire [15:0] v8p7 = BusA[63:56] * BusB[63:56];

    // --- VMUL16 partial products (4x 16-bit -> 32-bit each) ---
    wire [31:0] v16p0 = BusA[15:0]  * BusB[15:0];
    wire [31:0] v16p1 = BusA[31:16] * BusB[31:16];
    wire [31:0] v16p2 = BusA[47:32] * BusB[47:32];
    wire [31:0] v16p3 = BusA[63:48] * BusB[63:48];

    // --- VDOT8: sum of 8 byte products into 32-bit accumulator ---
    wire [31:0] dot_sum =
        {16'b0, v8p0} + {16'b0, v8p1} + {16'b0, v8p2} + {16'b0, v8p3} +
        {16'b0, v8p4} + {16'b0, v8p5} + {16'b0, v8p6} + {16'b0, v8p7};

    always @(ALUCtrl or BusA or BusB or BusC) begin
        case (ALUCtrl)
            `AND:    BusW = #20 BusA & BusB;
            `OR:     BusW = #20 BusA | BusB;
            `ADD:    BusW = #20 BusA + BusB;
            `PassA:  BusW = #20 BusA;
            `SUB:    BusW = #20 BusA - BusB;
            `PassB:  BusW = #20 BusB;

            // Multiply-accumulate: Rd = Ra * Rb + Rc
            `MADD:   BusW = #20 (BusA * BusB) + BusC;

            // 8x8-bit SIMD: lane-0 in bits [7:0]
            `VADD8:  BusW = #20 {
                         (BusA[63:56] + BusB[63:56]),
                         (BusA[55:48] + BusB[55:48]),
                         (BusA[47:40] + BusB[47:40]),
                         (BusA[39:32] + BusB[39:32]),
                         (BusA[31:24] + BusB[31:24]),
                         (BusA[23:16] + BusB[23:16]),
                         (BusA[15:8]  + BusB[15:8]),
                         (BusA[7:0]   + BusB[7:0])
                     };
            `VMUL8:  BusW = #20 {
                         v8p7[7:0], v8p6[7:0], v8p5[7:0], v8p4[7:0],
                         v8p3[7:0], v8p2[7:0], v8p1[7:0], v8p0[7:0]
                     };

            // Dot product: 8x8-bit -> 32-bit sum in [31:0], upper 32 bits zero
            `VDOT8:  BusW = #20 {32'b0, dot_sum};

            // 4x16-bit SIMD: lane-0 in bits [15:0]
            `VADD16: BusW = #20 {
                         (BusA[63:48] + BusB[63:48]),
                         (BusA[47:32] + BusB[47:32]),
                         (BusA[31:16] + BusB[31:16]),
                         (BusA[15:0]  + BusB[15:0])
                     };
            `VMUL16: BusW = #20 {
                         v16p3[15:0], v16p2[15:0],
                         v16p1[15:0], v16p0[15:0]
                     };

            // 2x32-bit SIMD: lane-0 in bits [31:0]
            `VADD32: BusW = #20 {
                         (BusA[63:32] + BusB[63:32]),
                         (BusA[31:0]  + BusB[31:0])
                     };

            default: BusW = 64'b0;
        endcase
    end

    assign #1 Zero = (BusW == 0);

endmodule
