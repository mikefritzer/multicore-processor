module RegisterFile(BusA, BusB, BusC, BusW, RA, RB, RC, RW, RegWr, Clk);
    output [63:0] BusA, BusB, BusC;
    input  [63:0] BusW;
    input  [4:0]  RA, RB, RC, RW;
    input         RegWr;
    input         Clk;

    reg [63:0] registers [31:0];

    integer i;
    initial begin
        for (i = 0; i < 32; i = i + 1)
            registers[i] = 64'b0;
    end

    assign #2 BusA = registers[RA];
    assign #2 BusB = registers[RB];
    assign #2 BusC = registers[RC];

    always @(posedge Clk) begin
        if (RegWr && RW != 5'd31)
            registers[RW] <= #3 BusW;
    end
endmodule
