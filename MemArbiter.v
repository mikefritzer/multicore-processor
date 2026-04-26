// Round-robin memory bus arbiter for N-core SoC.
//
// Core interfaces are packed into flat vectors:
//   core_addr    [N*64-1:0]  — core i occupies bits [i*64+63 : i*64]
//   core_wdata   [N*64-1:0]
//   core_read    [N-1:0]     — bit i = core i requests a read
//   core_write   [N-1:0]     — bit i = core i requests a write
//   core_cas_req [N-1:0]     — bit i = core i holds bus (atomic CAS)
//   core_rdata   [N*64-1:0]  — broadcast; each core sees all read data (filters by grant)
//   core_grant   [N-1:0]     — one-hot; indicates which core owns the bus this cycle
//
// A CAS request holds the grant for 2 consecutive cycles (read then write).
// The arbiter will not switch owners while cas_req is asserted.

`timescale 1ns/1ps

module MemArbiter #(parameter N = 4) (
    input  wire           CLK,
    input  wire           resetl,

    // Per-core packed interfaces
    input  wire [N*64-1:0] core_addr,
    input  wire [N*64-1:0] core_wdata,
    input  wire [N-1:0]    core_read,
    input  wire [N-1:0]    core_write,
    input  wire [N-1:0]    core_cas_req,
    output reg  [N*64-1:0] core_rdata,
    output reg  [N-1:0]    core_grant,

    // Single shared memory port
    output reg  [63:0]     mem_addr,
    output reg  [63:0]     mem_wdata,
    output reg             mem_read,
    output reg             mem_write,
    input  wire [63:0]     mem_rdata
);

    // Broadcast read data to all cores; each core uses its own grant bit to qualify.
    integer b;
    always @(*) begin
        for (b = 0; b < N; b = b + 1)
            core_rdata[b*64 +: 64] = mem_rdata;
    end

    // Current owner register (index, not one-hot)
    reg [$clog2(N)-1:0] owner;
    reg                  cas_locked;   // bus locked for CAS second phase

    // Combinational: find next requesting core starting from owner+1 (round-robin)
    reg [$clog2(N)-1:0] next_owner;
    integer j;
    always @(*) begin
        next_owner = owner;
        for (j = 1; j <= N; j = j + 1) begin
            if (core_read[(owner + j) % N] || core_write[(owner + j) % N])
                // Use the last hit in the loop = lowest-priority search; first hit wins
                // (the loop runs lowest to highest offset; we want first, so break on first)
                next_owner = next_owner; // overridden below
        end
        // Proper first-hit round-robin
        next_owner = owner; // default: keep owner if no one else requests
        for (j = N-1; j >= 1; j = j - 1) begin
            if (core_read[(owner + j) % N] || core_write[(owner + j) % N])
                next_owner = (owner + j) % N;
        end
        // If current owner still requests, keep it (CAS or back-to-back ops)
        if (core_read[owner] || core_write[owner] || core_cas_req[owner])
            next_owner = owner;
    end

    // Sequential state
    always @(posedge CLK) begin
        if (!resetl) begin
            owner      <= {$clog2(N){1'b0}};
            cas_locked <= 1'b0;
            core_grant <= {N{1'b0}};
            mem_read   <= 1'b0;
            mem_write  <= 1'b0;
            mem_addr   <= 64'b0;
            mem_wdata  <= 64'b0;
        end else begin
            if (!cas_locked) begin
                owner <= next_owner;
            end

            // Lock bus for second CAS phase
            if (core_cas_req[owner] && !cas_locked)
                cas_locked <= 1'b1;
            else if (cas_locked)
                cas_locked <= 1'b0;

            // Drive memory port from winning core
            core_grant           <= {N{1'b0}};
            core_grant[owner]    <= (core_read[owner] || core_write[owner] || core_cas_req[owner]);
            mem_addr             <= core_addr [owner*64 +: 64];
            mem_wdata            <= core_wdata[owner*64 +: 64];
            mem_read             <= core_read [owner];
            mem_write            <= core_write[owner];
        end
    end

endmodule
