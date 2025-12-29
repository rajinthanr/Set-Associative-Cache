#!/bin/bash
#==============================================================================
# Cache Simulation Test Script
# Run from VS Code terminal: ./scripts/run_test.sh
#==============================================================================

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

cd "$PROJECT_DIR"

echo -e "${BLUE}============================================${NC}"
echo -e "${BLUE}  4-Way Set-Associative Cache Test Suite${NC}"
echo -e "${BLUE}============================================${NC}"
echo ""

#------------------------------------------------------------------------------
# Check for iverilog
#------------------------------------------------------------------------------
if ! command -v iverilog &> /dev/null; then
    echo -e "${RED}ERROR: iverilog not found!${NC}"
    echo "Install with: sudo apt install iverilog"
    exit 1
fi

if ! command -v vvp &> /dev/null; then
    echo -e "${RED}ERROR: vvp not found!${NC}"
    echo "Install with: sudo apt install iverilog"
    exit 1
fi

#------------------------------------------------------------------------------
# Compile
#------------------------------------------------------------------------------
echo -e "${YELLOW}[1/3] Compiling Verilog...${NC}"

iverilog -Wall -g2005-sv \
    -o simulation/cache_test \
    -I verilog \
    verilog/cache.v \
    verilog/tb_cache.v \
    2>&1 | tee simulation/compile.log

if [ ${PIPESTATUS[0]} -ne 0 ]; then
    echo -e "${RED}Compilation FAILED!${NC}"
    cat simulation/compile.log
    exit 1
fi

echo -e "${GREEN}Compilation successful!${NC}"
echo ""

#------------------------------------------------------------------------------
# Run Simulation
#------------------------------------------------------------------------------
echo -e "${YELLOW}[2/3] Running Simulation...${NC}"
echo ""

cd simulation
vvp cache_test 2>&1 | tee test_output.log
SIM_RESULT=${PIPESTATUS[0]}
cd "$PROJECT_DIR"

echo ""

#------------------------------------------------------------------------------
# Parse Results
#------------------------------------------------------------------------------
echo -e "${YELLOW}[3/3] Parsing Results...${NC}"
echo ""

# Count passed/failed tests
PASSED=$(grep -c "PASS" simulation/test_output.log 2>/dev/null || true)
FAILED=$(grep -c "FAIL" simulation/test_output.log 2>/dev/null || true)
TESTS=$(grep -c "^TEST [0-9]" simulation/test_output.log 2>/dev/null || true)

# Handle empty results
PASSED=${PASSED:-0}
FAILED=${FAILED:-0}
TESTS=${TESTS:-0}

echo -e "${BLUE}============================================${NC}"
echo -e "${BLUE}  Test Results Summary${NC}"
echo -e "${BLUE}============================================${NC}"
echo ""

# Show each test
echo -e "${GREEN}Tests Executed: $TESTS${NC}"
echo ""

# Check simulation completed
if grep -q "SIMULATION COMPLETE" simulation/test_output.log 2>/dev/null; then
    echo -e "${GREEN}✓ Simulation completed successfully${NC}"
    SIM_OK=1
else
    echo -e "${RED}✗ Simulation did not complete${NC}"
    SIM_OK=0
fi

# Check for key features
echo ""
echo -e "${BLUE}Feature Verification:${NC}"

FEATURES_OK=0

if grep -q "Hit Latency: 1 cycle" simulation/test_output.log 2>/dev/null; then
    echo -e "${GREEN}  ✓ Hit latency (1 cycle)${NC}"
    ((FEATURES_OK++))
else
    echo -e "${RED}  ✗ Hit latency (1 cycle)${NC}"
fi

if grep -q "MISS.*Latency.*5" simulation/test_output.log 2>/dev/null; then
    echo -e "${GREEN}  ✓ Miss latency (~50 cycles)${NC}"
    ((FEATURES_OK++))
else
    echo -e "${RED}  ✗ Miss latency (~50 cycles)${NC}"
fi

if grep -q "CONFLICT MISSES" simulation/test_output.log 2>/dev/null; then
    echo -e "${GREEN}  ✓ Conflict miss detection${NC}"
    ((FEATURES_OK++))
else
    echo -e "${RED}  ✗ Conflict miss detection${NC}"
fi

if grep -q "WRITE(WB)" simulation/test_output.log 2>/dev/null; then
    echo -e "${GREEN}  ✓ Write-back on eviction${NC}"
    ((FEATURES_OK++))
else
    echo -e "${RED}  ✗ Write-back on eviction${NC}"
fi

if grep -q "NON-BLOCKING" simulation/test_output.log 2>/dev/null; then
    echo -e "${GREEN}  ✓ Hit-under-miss${NC}"
    ((FEATURES_OK++))
else
    echo -e "${RED}  ✗ Hit-under-miss${NC}"
fi

if grep -q "MULTI-MSHR" simulation/test_output.log 2>/dev/null; then
    echo -e "${GREEN}  ✓ Miss-under-miss (4 MSHRs)${NC}"
    ((FEATURES_OK++))
else
    echo -e "${RED}  ✗ Miss-under-miss (4 MSHRs)${NC}"
fi

echo ""
echo -e "${BLUE}--------------------------------------------${NC}"
echo -e "Features verified: ${GREEN}$FEATURES_OK/6${NC}"
echo -e "${BLUE}--------------------------------------------${NC}"

if [ "$SIM_OK" -eq 1 ] && [ "$FEATURES_OK" -ge 5 ]; then
    echo ""
    echo -e "${GREEN}★★★ ALL TESTS PASSED! ★★★${NC}"
    echo ""
    exit 0
else
    echo ""
    echo -e "${YELLOW}Check simulation/test_output.log for details${NC}"
    echo ""
    exit 1
fi
