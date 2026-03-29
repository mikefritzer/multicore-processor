# AMD/Xilinx Vivado Non-Project Mode Script
set part_number [lindex $argv 0]
set num_cores   [lindex $argv 1]

# Add original modules
read_verilog [glob rtl/core/*.v]
read_verilog [glob rtl/generated/*.sv]
read_xdc xdc/constraints.xdc

# Synthesize the design with the specified top module and part number
synth_design -top soc_top -part $part_number -generic CORES=$num_cores

# Implementation steps
opt_design
place_design
route_design

# Generate reports to be parsed for PPA metrics
report_utilization -file reports/utilization.txt
report_timing_summary -file reports/timing.txt
report_power -file reports/power.txt
write_bitstream -force build/output.bit

# Ensure signals crossing clock domains are properly synced
report_cdc -file reports/cdc_report.txt
report_power -file reports/power.txt -name {power_1}

# Area & Timing Reports with more details for PPA analysis
report_utilization -file reports/utilization.txt
report_timing_summary -delay_type min_max -report_unconstrained -check_timing_verbose -max_paths 10 -input_pins -file reports/timing.txt