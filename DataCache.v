module DataCache(
    input [63:0] Address,
    input [63:0] WriteData,
    input MemoryRead,
    input MemoryWrite,
    input Clock,
    output reg [63:0] ReadData,
    
    // Connections to Main Data Memory
    output [63:0] MemAddress,
    output [63:0] MemWriteData,
    output MemRead,
    output MemWrite,
    input [63:0] MemReadData,
    
    // Performance monitoring
    output reg CacheHit,
    output reg CacheMiss
);

    // Cache Storage: 8 lines of 64-bit data
    reg [63:0] cache_data [7:0];
    reg [57:0] cache_tag  [7:0];
    reg [7:0]  cache_valid;       // 1 valid bit per line

    initial cache_valid = 8'b0;   // All lines invalid at startup

    // Address Breakdown
    wire [2:0]  index = Address[5:3];
    wire [57:0] tag   = Address[63:6];

    // Hit Detection
    wire hit = cache_valid[index] && (cache_tag[index] == tag);

    // Read Logic
    always @(*) begin
        CacheHit = 0;
        CacheMiss = 0;
        
        if (MemoryRead) begin
            if (hit) begin
                ReadData = #5 cache_data[index]; // Fast Cache Read (simulated 5ns)
                CacheHit = 1;
            end else begin
                ReadData = #50 MemReadData;      // Slow RAM Fetch (simulated 50ns)
                CacheMiss = 1;
            end
        end else begin
            ReadData = 64'bx;
        end
    end

    // Write & Update Logic (Write-Through strategy)
    always @(posedge Clock) begin
        if (MemoryWrite) begin
            // Update cache on write
            cache_valid[index] <= 1'b1;
            cache_tag[index]   <= tag;
            cache_data[index]  <= WriteData;
        end 
        else if (MemoryRead && !hit) begin
            // On a read miss, save the fetched memory into the cache
            cache_valid[index] <= 1'b1;
            cache_tag[index]   <= tag;
            cache_data[index]  <= MemReadData;
        end
    end

    // Pass-through signals to Main Memory
    assign MemAddress = Address;
    assign MemWriteData = WriteData;
    assign MemRead = MemoryRead;       // Main memory reads on every request in this simple design
    assign MemWrite = MemoryWrite;

endmodule