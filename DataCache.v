// Direct-mapped write-through L1 data cache.
// LOG2_LINES=6 -> 64 lines, index=6 bits, tag=55 bits, block=8 bytes (one doubleword).
module DataCache #(
    parameter LOG2_LINES = 6   // 2^6 = 64 cache lines
)(
    input  [63:0] Address,
    input  [63:0] WriteData,
    input         MemoryRead,
    input         MemoryWrite,
    input         Clock,
    output reg [63:0] ReadData,

    // Main memory interface
    output [63:0] MemAddress,
    output [63:0] MemWriteData,
    output        MemRead,
    output        MemWrite,
    input  [63:0] MemReadData,

    // Performance monitoring
    output reg CacheHit,
    output reg CacheMiss
);

    localparam LINES    = 1 << LOG2_LINES;       // number of cache lines
    localparam IDX_LO   = 3;                     // byte offset bits = 3 (8-byte block)
    localparam IDX_HI   = IDX_LO + LOG2_LINES - 1;
    localparam TAG_LO   = IDX_HI + 1;
    localparam TAG_BITS = 64 - TAG_LO;

    reg [63:0]          cache_data  [LINES-1:0];
    reg [TAG_BITS-1:0]  cache_tag   [LINES-1:0];
    reg [LINES-1:0]     cache_valid;

    integer k;
    initial begin
        cache_valid = {LINES{1'b0}};
        for (k = 0; k < LINES; k = k + 1)
            cache_tag[k] = {TAG_BITS{1'b0}};
    end

    wire [LOG2_LINES-1:0] index = Address[IDX_HI:IDX_LO];
    wire [TAG_BITS-1:0]   tag   = Address[63:TAG_LO];
    wire hit = cache_valid[index] && (cache_tag[index] == tag);

    // Read logic
    always @(*) begin
        CacheHit  = 1'b0;
        CacheMiss = 1'b0;
        if (MemoryRead) begin
            if (hit) begin
                ReadData  = #5 cache_data[index];
                CacheHit  = 1'b1;
            end else begin
                ReadData  = #50 MemReadData;
                CacheMiss = 1'b1;
            end
        end else begin
            ReadData = 64'bx;
        end
    end

    // Write and refill logic
    always @(posedge Clock) begin
        if (MemoryWrite) begin
            cache_valid[index] <= 1'b1;
            cache_tag[index]   <= tag;
            cache_data[index]  <= WriteData;
        end else if (MemoryRead && !hit) begin
            cache_valid[index] <= 1'b1;
            cache_tag[index]   <= tag;
            cache_data[index]  <= MemReadData;
        end
    end

    // Only fetch from main memory on a miss — hits are served from cache
    assign MemAddress   = Address;
    assign MemWriteData = WriteData;
    assign MemRead      = MemoryRead && !hit;
    assign MemWrite     = MemoryWrite;

endmodule
