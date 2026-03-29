import argparse
import os

def generate_soc(num_cores, output_path):
    # Template for the Top-Level SoC with N cores
    sv_code = f"""
// AUTO-GENERATED MULTI-CORE TOP LEVEL
// Parameters: CORES={num_cores}
module soc_top (
    input  logic CLK,
    input  logic resetl,
    input  logic [63:0] startpc,
    output logic [63:0] global_error_count
);

    // Shared Memory Wires
    wire [63:0] shared_mem_addr;
    wire [63:0] shared_mem_wdata;
    wire [63:0] shared_mem_rdata;
    wire        shared_mem_read;
    wire        shared_mem_write;

    // Per-Core Instruction Interfaces
    {" ".join([f"wire [31:0] imem_data_{i}; wire [63:0] imem_addr_{i};" for i in range(num_cores)])}

    // --- Core Instantiations ---
"""
    # Dynamically instantiate N cores
    for i in range(num_cores):
        sv_code += f"""
    singlecycle_core core_{i} (
        .CLK(CLK),
        .resetl(resetl),
        .startpc(startpc),
        .core_id(32'd{i}),
        .imem_addr(imem_addr_{i}),
        .imem_data(imem_data_{i}),
        .main_mem_addr(shared_mem_addr), // Simplified: Direct tie (Requires Arbiter for real multi-master)
        .main_mem_writedata(shared_mem_wdata),
        .main_mem_readdata(shared_mem_rdata),
        .main_mem_read(shared_mem_read),
        .main_mem_write(shared_mem_write)
    );
"""
    
    sv_code += "\n    // --- Shared Infrastructure ---\n"
    # Shared Data Memory
    sv_code += """
    DataMemory shared_ram (
        .ReadData(shared_mem_rdata),
        .Address(shared_mem_addr),
        .WriteData(shared_mem_wdata),
        .MemoryRead(shared_mem_read),
        .MemoryWrite(shared_mem_write),
        .Clock(CLK)
    );
endmodule
"""
    with open(output_path, 'w') as f:
        f.write(sv_code)
    print(f"Successfully generated {num_cores}-core SoC at {output_path}")

if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--cores", type=int, default=1)
    parser.add_argument("--out", type=str, default="rtl/generated/soc_top.sv")
    args = parser.parse_args()
    generate_soc(args.cores, args.out)