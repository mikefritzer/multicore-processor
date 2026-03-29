import re
import os
import matplotlib.pyplot as plt

def parse_vivado_reports(reports_dir):
    metrics = {
        "lut_usage": 0,
        "wns": 0.0,  # Worst Negative Slack
        "power_w": 0.0,
        "cdc_errors": 0
    }

    # 1. Parse Utilization (Area)
    util_path = os.path.join(reports_dir, "utilization.txt")
    if os.path.exists(util_path):
        with open(util_path, 'r') as f:
            content = f.read()
            # Look for "| Slice LUTs | <number> |"
            match = re.search(r"Slice LUTs\s*\|\s*(\d+)", content)
            if match:
                metrics["lut_usage"] = int(match.group(1))

    # 2. Parse Timing (Performance)
    timing_path = os.path.join(reports_dir, "timing.txt")
    if os.path.exists(timing_path):
        with open(timing_path, 'r') as f:
            content = f.read()
            # Look for "WNS(ns)"
            match = re.search(r"WNS\(ns\)\s*\|\s*([\-\d\.]+)", content)
            if match:
                metrics["wns"] = float(match.group(1))

    # 3. Parse Power (Low Power Verification)
    power_path = os.path.join(reports_dir, "power.txt")
    if os.path.exists(power_path):
        with open(power_path, 'r') as f:
            content = f.read()
            # Look for "Total On-Chip Power (W) | <number> |"
            match = re.search(r"Total On-Chip Power \(W\)\s*\|\s*([\d\.]+)", content)
            if match:
                metrics["power_w"] = float(match.group(1))

    return metrics

def generate_comparison_plot(data_log):
    # This function would take a history of runs (1, 2, 4 cores)
    # and generate a .png chart for your README.
    cores = [d['cores'] for d in data_log]
    power = [d['power_w'] for d in data_log]
    
    plt.figure(figsize=(10, 5))
    plt.plot(cores, power, marker='o', linestyle='-', color='b')
    plt.title('Power Consumption Scaling vs. Core Count')
    plt.xlabel('Number of Cores')
    plt.ylabel('Power (Watts)')
    plt.grid(True)
    plt.savefig('docs/power_scaling_chart.png')

# Example usage logic for the Makefile
if __name__ == "__main__":
    import sys
    # Simulating a multi-core data collection
    results = parse_vivado_reports("reports")
    print(f"--- PPA Results ---")
    print(f"Area (LUTs): {results['lut_usage']}")
    print(f"Timing (WNS): {results['wns']} ns")
    print(f"Power: {results['power_w']} W")