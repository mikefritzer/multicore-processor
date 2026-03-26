`timescale 1ns / 1ps
/*
 * Module: InstructionMemory
 *
 * Implements read-only instruction memory
 * 
 */
module InstructionMemory(Data, Address);
   parameter T_rd = 20;
   parameter MemSize = 40;
   
   output [31:0] Data;
   input [63:0]  Address;
   reg [31:0] 	 Data;
   
   always @ (Address) begin
      #4;
      case(Address)

	/* Test Program 1:
	 * Program loads constants from the data memory. Uses these constants to test
	 * the following instructions: LDUR, ORR, AND, CBZ, ADD, SUB, STUR and B.
	 * 
	 * Assembly code for test:
	 * 
	 * 0: LDUR X9, [XZR, 0x0]    //Load 1 into x9
	 * 4: LDUR x11, [XZR, 0x8]   //Load a into x11
	 * 8: LDUR X11, [XZR, 0x11]  //Load 5 into x11
	 * C: LDUR X12, [XZR, 0x18]  //Load big constant into x12
	 * 10: LDUR X13, [XZR, 0x20]  //load a 0 into X13
	 * 
	 * 14: ORR x10, x10, X11  //Create mask of 0xf
	 * 18: AND X12, X12, x11  //Mask off low order bits of big constant
	 *
	 * loop:
	 * 1C: CBZ X12, end  //while X12 is not 0
	 * 20: ADD X13, X13, X9  //Increment counter in X13
	 * 24: SUB X12, X12, X9  //Decrement remainder of big constant in X12
	 * 28: B loop  //Repeat till X12 is 0
	 * 2C: STUR X13, [XZR, 0x20]  //store back the counter value into the memory location 0x20
	 */
	

	63'h000: Data = 32'hF84003E9;
	63'h004: Data = 32'hF84083EA;
	63'h008: Data = 32'hF84103EB;
	63'h00c: Data = 32'hF84183EC;
	63'h010: Data = 32'hF84203ED;
	63'h014: Data = 32'hAA0B014A;
	63'h018: Data = 32'h8A0A018C;
	63'h01c: Data = 32'hB400008C;
	63'h020: Data = 32'h8B0901AD;
	63'h024: Data = 32'hCB09018C;
	63'h028: Data = 32'h17FFFFFD;
	63'h02c: Data = 32'hF80203ED;
	63'h030: Data = 32'hF84203ED;  //One last load to place stored value on memdbus for test checking.

	63'h034: Data = 32'b10010001000000000000001111101001; // 34: ADDI X9, XZR, 0x0  // load a 0 into X9

	63'h038: Data = 32'b11010010111000100100011010001011; // 38: MOVZ x11, 0x1234, LSL 48 // (x11 = 0x1234 * 2^48)
	63'h03c: Data = 32'b10001011000010010000000101101001; // 3c: ADD X9, x11, X9 // add result of MOVZ in x11 to x9

	63'h040: Data = 32'b11010010110010101100111100001011; // 40: MOVZ x11, 0x5678, LSL 32 // (x11 = 0x5678 * 2^32)
	63'h044: Data = 32'b10001011000010010000000101101001; // 44: ADD X9, x11, X9 // add result of MOVZ in x11 to x9

	63'h048: Data = 32'b11010010101100110101011110001011; // 48: MOVZ x11, 0x9abc, LSL 16 // (x11 = 0x9abc * 2^16)
	63'h04c: Data = 32'b10001011000010010000000101101001; // 4c: ADD X9, x11, X9 // add result of MOVZ in x11 to x9

	63'h050: Data = 32'b11010010100110111101111000001011; // 50: MOVZ x11, 0xdef0, LSL 0 // (x11 = 0xdef0 * 2^0)
	63'h054: Data = 32'b10001011000010010000000101101001; // 54: ADD X9, x11, X9 // add result of MOVZ in x11 to x9
			
	63'h058: Data = 32'b11111000000000011100001111101001; // 58: STUR X9, [XZR, 0x28] // store constant in memory
	63'h05c: Data = 32'b11111000010000011100001111101010; // 5c: LDUR X10, [XZR, 0x28] // Load constant into x10

	63'h068: Data = 32'b11010010100000001000000101001010; // 68: MOVZ x10, 0x0101, LSL 0 // (x10 = 0x0101 * 2^0)
	63'h06c: Data = 32'b11010010100000010000000101101011; // 6c: MOVZ x11, 0x0202, LSL 0 // (x11 = 0x0202 * 2^0)

	63'h070: Data = 32'b11010010100000000000000110001100; // 70: MOVZ x12, 0x000A, LSL 0 // (x12 = 0x000A * 2^0)
	63'h074: Data = 32'b01001110000010110000000101001001; // 74: VADD8 X9, X10, X11 // (x9 = x10 + x11, done byte-wise)

	63'h078: Data = 32'b10011011000010110011000101001101; // 78: MADD X13, X12, X10, X11 // (x13 = x12 * x10 + x11)
	63'h07c: Data = 32'b11101011000010010000000100111111; // 7c: SUBS XZR, X9, X9 // Force zero flag to be true

	63'h080: Data = 32'b10011010100010010000000110101110; // 80: CSEL X14, X13, X9, EQ // if zero flag is true, set x14 to x13, else set x14 to 0
	63'h084: Data = 32'b11111000000000000111000111001110; // 84: STUR X14, [XZR, 0x30] // store value of x14 in memory for test verification

	63'h088: Data = 32'b11111000010000000111000111001111; // LDUR X15, [XZR, 0x30] for verification
	63'h08c: Data = 32'b11010010100000001000000001101010; // 8c: MOVZ X10, 0x0403, LSL 0 // (x10 = 0x0403 * 2^0)

	63'h090: Data = 32'b11010010100000000100000010101011; // 90: MOVZ X11, 0x0205, LSL 0 // (x11 = 0x0205 * 2^0)
	63'h094: Data = 32'b01001110001010110000000101001100; // 94: VMUL8 X12, X10, X11 // (x12 = x10 * x11, done byte-wise)

	63'h098: Data = 32'b11111000000000111000001111101100; // 98: STUR X12, [XZR, 0x38] // store result of VMUL8 in memory for test verification
	63'h09c: Data = 32'b11111000010000111000001111101101; // 9c: LDUR X13, [XZR, 0x38] for verification
	
	63'h0a0: Data = 32'hF84083EA; // LDUR X10, [XZR, 0x8]
	63'h0a4: Data = 32'hF84103EB; // LDUR X11, [XZR, 0x10]
	
	63'h0a8: Data = 32'hF84083EC; // LDUR X12, [XZR, 0x8]
	63'h0ac: Data = 32'hF84103ED; // LDUR X13, [XZR, 0x10]

	default: Data = 32'hXXXXXXXX;
      endcase
   end
endmodule
