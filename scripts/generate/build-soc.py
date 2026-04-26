"""
Generate a synthesizable multicore SoC top module.

Usage:
    python build-soc.py --cores N --out rtl/generated/soc_top.sv

Architecture:
  N `core` instances, each with a private L1 data cache whose miss path
  connects to MemArbiter.  MemArbiter owns a single shared DataMemory.
  A per-SoC barrier register handles the BARRIER instruction: each core
  asserts barrier_req; when all N cores have asserted it, barrier_ack is
  broadcast and all cores clear their req in the same cycle.
"""
import argparse
import os


def generate_soc(num_cores: int, output_path: str) -> None:
    n = num_cores

    # ---- per-core signal declarations ----
    per_core_wires = []
    for i in range(n):
        per_core_wires.append(f"""\
    wire [63:0] imem_addr_{i};
    wire [63:0] c{i}_mm_addr, c{i}_mm_wdata;
    wire        c{i}_mm_read, c{i}_mm_write, c{i}_mm_grant;
    wire [63:0] c{i}_mm_rdata;
    wire        c{i}_barrier_req, c{i}_cas_req;
    wire [63:0] c{i}_dmemout, c{i}_pc;""")

    # ---- arbiter packed-bus connections ----
    arb_addr  = ", ".join(reversed([f"c{i}_mm_addr"  for i in range(n)]))
    arb_wdata = ", ".join(reversed([f"c{i}_mm_wdata" for i in range(n)]))
    arb_read  = ", ".join(reversed([f"c{i}_mm_read"  for i in range(n)]))
    arb_write = ", ".join(reversed([f"c{i}_mm_write" for i in range(n)]))
    arb_cas   = ", ".join(reversed([f"c{i}_cas_req"  for i in range(n)]))
    arb_grant_slices = "\n".join(
        [f"    assign c{i}_mm_grant = arb_grant[{i}];" for i in range(n)])
    arb_rdata_slices = "\n".join(
        [f"    assign c{i}_mm_rdata = arb_rdata[{i}*64 +: 64];" for i in range(n)])

    # ---- core instantiations ----
    core_insts = []
    for i in range(n):
        core_insts.append(f"""\
    core #() core_{i} (
        .CLK               (CLK),
        .resetl            (resetl),
        .startpc           (startpc),
        .core_id           (32'd{i}),
        .main_mem_addr     (c{i}_mm_addr),
        .main_mem_writedata(c{i}_mm_wdata),
        .main_mem_read     (c{i}_mm_read),
        .main_mem_write    (c{i}_mm_write),
        .main_mem_readdata (c{i}_mm_rdata),
        .main_mem_grant    (c{i}_mm_grant),
        .barrier_req       (c{i}_barrier_req),
        .barrier_ack       (barrier_ack),
        .cas_bus_req       (c{i}_cas_req),
        .dmemout           (c{i}_dmemout),
        .currentpc         (c{i}_pc)
    );""")

    barrier_req_and = " & ".join([f"c{i}_barrier_req" for i in range(n)])

    sv_code = f"""\
// AUTO-GENERATED MULTICORE SOC TOP
// Cores: {n}  |  Generator: scripts/generate/build-soc.py
// Do not edit by hand.

`timescale 1ns/1ps

module soc_top (
    input  logic        CLK,
    input  logic        resetl,
    input  logic [63:0] startpc,
    output logic [63:0] global_error_count
);

    // ---- Per-core wires ----
{chr(10).join(per_core_wires)}

    // ---- Arbiter packed buses ----
    wire [{n}*64-1:0] arb_addr  = {{{arb_addr}}};
    wire [{n}*64-1:0] arb_wdata = {{{arb_wdata}}};
    wire [{n}-1:0]    arb_read  = {{{arb_read}}};
    wire [{n}-1:0]    arb_write = {{{arb_write}}};
    wire [{n}-1:0]    arb_cas   = {{{arb_cas}}};
    wire [{n}*64-1:0] arb_rdata;
    wire [{n}-1:0]    arb_grant;

    // Distribute arbiter outputs back to individual core wires
{arb_grant_slices}
{arb_rdata_slices}

    // ---- Shared memory arbiter ----
    wire [63:0] shared_addr, shared_wdata, shared_rdata;
    wire        shared_read, shared_write;

    MemArbiter #(.N({n})) arbiter (
        .CLK         (CLK),
        .resetl      (resetl),
        .core_addr   (arb_addr),
        .core_wdata  (arb_wdata),
        .core_read   (arb_read),
        .core_write  (arb_write),
        .core_cas_req(arb_cas),
        .core_rdata  (arb_rdata),
        .core_grant  (arb_grant),
        .mem_addr    (shared_addr),
        .mem_wdata   (shared_wdata),
        .mem_read    (shared_read),
        .mem_write   (shared_write),
        .mem_rdata   (shared_rdata)
    );

    // ---- Shared data memory ----
    DataMemory shared_ram (
        .ReadData   (shared_rdata),
        .Address    (shared_addr),
        .WriteData  (shared_wdata),
        .MemoryRead (shared_read),
        .MemoryWrite(shared_write),
        .Clock      (CLK)
    );

    // ---- Barrier register ----
    // barrier_ack goes high when ALL cores have asserted barrier_req.
    wire barrier_ack = {barrier_req_and};

    // ---- Core instantiations ----
{chr(10).join(core_insts)}

    // ---- Placeholder error counter (tie to 0 until fault injection added) ----
    assign global_error_count = 64'b0;

endmodule
"""

    os.makedirs(os.path.dirname(output_path), exist_ok=True)
    with open(output_path, "w") as f:
        f.write(sv_code)
    print(f"Generated {n}-core SoC -> {output_path}")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Multicore SoC generator")
    parser.add_argument("--cores", type=int, default=4,
                        help="Number of cores (default: 4)")
    parser.add_argument("--out",   type=str, default="rtl/generated/soc_top.sv",
                        help="Output SystemVerilog file")
    args = parser.parse_args()
    generate_soc(args.cores, args.out)
