#!/bin/bash
#==============================================================================
# Program DE0-Nano FPGA from VS Code
#==============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
SOF_FILE="$PROJECT_DIR/output_files/Cache.sof"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}============================================${NC}"
echo -e "${BLUE}  Program DE0-Nano FPGA${NC}"
echo -e "${BLUE}============================================${NC}"
echo ""

# Check for SOF file
if [ ! -f "$SOF_FILE" ]; then
    echo -e "${RED}ERROR: $SOF_FILE not found!${NC}"
    echo "Please compile the project in Quartus first."
    exit 1
fi

echo -e "${YELLOW}SOF file: $SOF_FILE${NC}"
echo ""

# Check for programmer
if ! command -v quartus_pgm &> /dev/null; then
    echo -e "${RED}ERROR: quartus_pgm not found!${NC}"
    echo "Add Quartus to PATH: export PATH=\$PATH:/path/to/quartus/bin"
    exit 1
fi

# Check JTAG connection
echo -e "${YELLOW}Checking JTAG connection...${NC}"
jtagconfig 2>&1

echo ""
echo -e "${YELLOW}Programming FPGA...${NC}"

quartus_pgm -c 1 -m jtag -o "p;$SOF_FILE"

if [ $? -eq 0 ]; then
    echo ""
    echo -e "${GREEN}✓ FPGA programmed successfully!${NC}"
    echo ""
    echo "Next steps:"
    echo "  1. Press KEY0 on DE0-Nano to reset"
    echo "  2. Run: ./scripts/issp_vscode.sh"
else
    echo ""
    echo -e "${RED}✗ Programming failed!${NC}"
    echo ""
    echo "Troubleshooting:"
    echo "  1. Check USB-Blaster connection"
    echo "  2. Run: jtagconfig"
    echo "  3. Try: sudo killall jtagd && jtagd"
fi
