#!/bin/bash
#==============================================================================
# ISSP Test Script for VS Code
# Connects to DE0-Nano FPGA and tests cache via ISSP
#==============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

echo -e "${BLUE}============================================${NC}"
echo -e "${BLUE}  ISSP Cache Debug - DE0-Nano${NC}"
echo -e "${BLUE}============================================${NC}"
echo ""

#------------------------------------------------------------------------------
# Check for Quartus tools
#------------------------------------------------------------------------------
if ! command -v quartus_stp &> /dev/null; then
    echo -e "${RED}ERROR: quartus_stp not found!${NC}"
    echo ""
    echo "Make sure Quartus is in your PATH. Try:"
    echo "  export PATH=\$PATH:/path/to/quartus/bin"
    echo ""
    echo "Or run this in Quartus System Console instead:"
    echo "  Tools -> System Debugging Tools -> System Console"
    echo "  source scripts/issp_test.tcl"
    exit 1
fi

#------------------------------------------------------------------------------
# Create Tcl script for ISSP interaction
#------------------------------------------------------------------------------
TCL_SCRIPT=$(mktemp /tmp/issp_test_XXXXXX.tcl)

cat > "$TCL_SCRIPT" << 'ENDTCL'
# ISSP Test Script for Cache Debugging
puts "\n===== ISSP Cache Test ====="

# Find ISSP services
set issp_list [get_service_paths issp]

if {[llength $issp_list] == 0} {
    puts "ERROR: No ISSP service found!"
    exit 1
}

puts "Found ISSP: [lindex $issp_list 0]"
set issp_path [lindex $issp_list 0]

# Open ISSP
set issp [claim_service issp $issp_path ""]
puts "ISSP connected: $issp"

# Get instance info
puts "\n--- ISSP Instance Info ---"
set info [issp_get_instance_info $issp]
puts "Info: $info"

puts "\n--- Initial Probe Reading ---"
set probe [issp_read_probe_data $issp]
puts "Probe (64-bit): $probe"

puts "\n--- Reset Counters ---"
# Reset counters (pulse bit 25): 0x02000001 then 0x00000001
issp_write_source_data $issp 0x02000001
after 50
issp_write_source_data $issp 0x00000001
after 50
puts "Counters reset"

puts "\n--- Auto Mode (bit 0 = 0) ---"
issp_write_source_data $issp 0x00000000
puts "Cache in AUTO mode - generating requests"
puts "Watch LEDs on DE0-Nano!"

# Sample probe for 5 seconds
puts "\n--- Sampling Cache Status ---"
for {set i 1} {$i <= 5} {incr i} {
    after 1000
    set probe [issp_read_probe_data $issp]
    puts "  Sample $i: $probe"
}

puts "\n--- Manual Mode Test ---"
# Switch to manual mode (bit 0 = 1)
issp_write_source_data $issp 0x00000001
puts "Switched to MANUAL mode"

# Reset counters
issp_write_source_data $issp 0x02000001
after 50
issp_write_source_data $issp 0x00000001
after 50

# Manual READ to address 0x00100
# Source bits: [0]=mode=1, [1]=valid=1, [2]=rw=0, [4:3]=size=10, [24:5]=addr
# addr = 0x100 -> shifted to bits[24:5] = 0x100 << 5 = 0x2000
# Combined: 0x00002000 | 0x10 (size) | 0x02 (valid) | 0x01 (mode) = 0x00002013
puts "\nManual READ @ 0x00100 (expect MISS - cold cache)..."
issp_write_source_data $issp 0x00002013
after 200
issp_write_source_data $issp 0x00002001
after 100

set probe [issp_read_probe_data $issp]
puts "After 1st READ: $probe"

# Same address again (should HIT)
puts "\nManual READ @ 0x00100 (expect HIT - cached)..."
issp_write_source_data $issp 0x00002013
after 200
issp_write_source_data $issp 0x00002001
after 100

set probe [issp_read_probe_data $issp]
puts "After 2nd READ: $probe"

# Back to auto mode
puts "\n--- Back to Auto Mode ---"
issp_write_source_data $issp 0x00000000
puts "Cache back in AUTO mode"

# Final sample
after 500
set probe [issp_read_probe_data $issp]
puts "Final probe: $probe"

# Close service
close_service issp $issp
puts "\n===== Test Complete ====="
ENDTCL

#------------------------------------------------------------------------------
# Run the Tcl script via system-console
#------------------------------------------------------------------------------
echo -e "${YELLOW}Connecting to FPGA...${NC}"
echo ""

# Find system-console
SYSCON=$(find /home/rajinthan/altera_lite -name "system-console" -type f 2>/dev/null | grep -v doc | head -1)

if [ -z "$SYSCON" ]; then
    echo -e "${RED}ERROR: system-console not found!${NC}"
    echo "Looking for alternative..."
    SYSCON="quartus_stp"
fi

echo "Using: $SYSCON"
"$SYSCON" --script="$TCL_SCRIPT" 2>&1

RESULT=$?

# Cleanup
rm -f "$TCL_SCRIPT"

echo ""
if [ $RESULT -eq 0 ]; then
    echo -e "${GREEN}✓ ISSP test completed successfully${NC}"
else
    echo -e "${RED}✗ ISSP test failed${NC}"
    echo ""
    echo -e "${YELLOW}Troubleshooting:${NC}"
    echo "1. Is the FPGA programmed? Run: quartus_pgm -c 1 -m jtag -o 'p;output_files/Cache.sof'"
    echo "2. Is USB-Blaster connected? Run: jtagconfig"
    echo "3. Is ISSP in the design? Recompile with issp.qsys"
fi

exit $RESULT
