#==============================================================================
# ISSP Test Commands for Cache Debugging
# Target: DE0-Nano (Cyclone IV EP4CE22F17C6)
# 
# Usage: Run in Quartus System Console after programming the FPGA
#        Tools -> System Debugging Tools -> System Console
#        Then: source scripts/issp_test.tcl
#==============================================================================

#------------------------------------------------------------------------------
# ISSP Source Bit Mapping (32 bits - Control from Quartus to FPGA)
#------------------------------------------------------------------------------
# Bit 0:       debug_mode      (0=auto pattern, 1=manual ISSP control)
# Bit 1:       req_valid       (manual request valid)
# Bit 2:       req_rw          (0=read, 1=write)
# Bits 4:3:    req_size        (00=byte, 01=half, 10=word, 11=reserved)
# Bits 24:5:   req_addr        (20-bit address)
# Bit 25:      reset_cnt       (reset hit/miss counters)
# Bit 26:      single_step     (single step mode)
# Bits 31:27:  probe_sel       (probe multiplexer selection 0-5)

#------------------------------------------------------------------------------
# ISSP Probe Bit Mapping (64 bits - Monitoring from FPGA to Quartus)
#------------------------------------------------------------------------------
# Based on probe_sel:
# 0: Basic status    - {hit_cnt[15:0], miss_cnt[15:0], total_req[15:0], state[7:0], flags[7:0]}
# 1: Cache request   - {addr[19:0], wdata[31:0], size[1:0], rw, valid, ready, resp_valid, hit}
# 2: Cache response  - {rdata[31:0], tag bits, way info}
# 3: Memory interface- {mem signals}
# 4: MSHR status     - {mshr_valid, mshr_addr, mshr states}
# 5: Debug counters  - {various debug counters}

#------------------------------------------------------------------------------
# Helper Functions
#------------------------------------------------------------------------------

# Build source value from individual fields
proc build_source {debug_mode req_valid req_rw req_size req_addr reset_cnt single_step probe_sel} {
    set source 0
    set source [expr {$source | (($debug_mode & 0x1) << 0)}]
    set source [expr {$source | (($req_valid & 0x1) << 1)}]
    set source [expr {$source | (($req_rw & 0x1) << 2)}]
    set source [expr {$source | (($req_size & 0x3) << 3)}]
    set source [expr {$source | (($req_addr & 0xFFFFF) << 5)}]
    set source [expr {$source | (($reset_cnt & 0x1) << 25)}]
    set source [expr {$source | (($single_step & 0x1) << 26)}]
    set source [expr {$source | (($probe_sel & 0x1F) << 27)}]
    return $source
}

# Parse probe value for probe_sel=0 (basic status)
proc parse_probe_status {probe} {
    set flags     [expr {$probe & 0xFF}]
    set state     [expr {($probe >> 8) & 0xFF}]
    set total_req [expr {($probe >> 16) & 0xFFFF}]
    set miss_cnt  [expr {($probe >> 32) & 0xFFFF}]
    set hit_cnt   [expr {($probe >> 48) & 0xFFFF}]
    
    puts "===== Cache Status ====="
    puts "Hit Count:    $hit_cnt"
    puts "Miss Count:   $miss_cnt"
    puts "Total Reqs:   $total_req"
    puts "State:        [format 0x%02X $state]"
    puts "Flags:        [format 0x%02X $flags]"
    if {$total_req > 0} {
        set hit_rate [expr {100.0 * $hit_cnt / $total_req}]
        puts "Hit Rate:     [format %.2f $hit_rate]%"
    }
    puts "========================"
}

# Parse probe value for probe_sel=1 (cache request)
proc parse_probe_request {probe} {
    set hit        [expr {$probe & 0x1}]
    set resp_valid [expr {($probe >> 1) & 0x1}]
    set ready      [expr {($probe >> 2) & 0x1}]
    set valid      [expr {($probe >> 3) & 0x1}]
    set rw         [expr {($probe >> 4) & 0x1}]
    set size       [expr {($probe >> 5) & 0x3}]
    set wdata      [expr {($probe >> 7) & 0xFFFFFFFF}]
    set addr       [expr {($probe >> 39) & 0xFFFFF}]
    
    puts "===== Cache Request ====="
    puts "Address:      [format 0x%05X $addr]"
    puts "Write Data:   [format 0x%08X $wdata]"
    puts "Size:         $size ([lindex {byte half word reserved} $size])"
    puts "R/W:          [expr {$rw ? \"WRITE\" : \"READ\"}]"
    puts "Valid:        $valid"
    puts "Ready:        $ready"
    puts "Resp Valid:   $resp_valid"
    puts "Hit:          $hit"
    puts "========================="
}

#------------------------------------------------------------------------------
# ISSP Access Functions (Adjust service path based on your design)
#------------------------------------------------------------------------------

# Initialize ISSP connection
proc issp_init {} {
    global issp_path
    
    # Get available services
    set masters [get_service_paths master]
    puts "Available master services: $masters"
    
    # Find ISSP service (adjust name if needed)
    set issp_services [get_service_paths issp]
    puts "Available ISSP services: $issp_services"
    
    if {[llength $issp_services] > 0} {
        set issp_path [lindex $issp_services 0]
        puts "Using ISSP: $issp_path"
        return 1
    } else {
        puts "ERROR: No ISSP service found!"
        puts "Make sure the FPGA is programmed with ISSP enabled"
        return 0
    }
}

# Open ISSP service
proc issp_open {} {
    global issp_path issp_claim
    set issp_claim [claim_service issp $issp_path ""]
    puts "ISSP service opened"
}

# Close ISSP service
proc issp_close {} {
    global issp_claim
    close_service issp $issp_claim
    puts "ISSP service closed"
}

# Write to ISSP source
proc issp_write {value} {
    global issp_claim
    issp_write_source $issp_claim $value
    puts "ISSP Source <- [format 0x%08X $value]"
}

# Read from ISSP probe
proc issp_read {} {
    global issp_claim
    set probe [issp_read_probe $issp_claim]
    puts "ISSP Probe -> [format 0x%016X $probe]"
    return $probe
}

#------------------------------------------------------------------------------
# High-Level Test Commands
#------------------------------------------------------------------------------

# Switch to auto mode (let cache run automatic test pattern)
proc cache_auto_mode {} {
    set src [build_source 0 0 0 0 0 0 0 0]
    issp_write $src
    puts "Cache set to AUTO mode"
}

# Switch to manual mode (control via ISSP)
proc cache_manual_mode {} {
    set src [build_source 1 0 0 0 0 0 0 0]
    issp_write $src
    puts "Cache set to MANUAL mode"
}

# Reset hit/miss counters
proc cache_reset_counters {} {
    set src [build_source 1 0 0 0 0 1 0 0]
    issp_write $src
    after 10
    set src [build_source 1 0 0 0 0 0 0 0]
    issp_write $src
    puts "Counters reset"
}

# Read cache status
proc cache_status {} {
    # Select probe 0 (basic status)
    set src [build_source 1 0 0 0 0 0 0 0]
    issp_write $src
    after 10
    set probe [issp_read]
    parse_probe_status $probe
}

# Perform a cache read
proc cache_read {addr} {
    puts "Cache READ from address [format 0x%05X $addr]"
    
    # Set address and read request
    set src [build_source 1 1 0 2 $addr 0 0 0]
    issp_write $src
    
    after 10
    
    # Clear request
    set src [build_source 1 0 0 0 0 0 0 0]
    issp_write $src
    
    # Read response (switch to probe 1)
    set src [build_source 1 0 0 0 0 0 0 1]
    issp_write $src
    after 10
    set probe [issp_read]
    parse_probe_request $probe
    
    return $probe
}

# Perform a cache write
proc cache_write {addr data} {
    puts "Cache WRITE [format 0x%08X $data] to address [format 0x%05X $addr]"
    
    # Note: Write data must be set through a different mechanism
    # since ISSP source only has address control
    # This function sets up the address for write
    
    set src [build_source 1 1 1 2 $addr 0 0 0]
    issp_write $src
    
    after 10
    
    # Clear request
    set src [build_source 1 0 0 0 0 0 0 0]
    issp_write $src
    
    puts "Write request sent (note: data path limited by ISSP width)"
}

# Select probe view
proc cache_select_probe {sel} {
    set src [build_source 1 0 0 0 0 0 0 $sel]
    issp_write $src
    puts "Selected probe view: $sel"
    after 10
    set probe [issp_read]
    return $probe
}

# View MSHR status
proc cache_mshr_status {} {
    puts "===== MSHR Status ====="
    set src [build_source 1 0 0 0 0 0 0 4]
    issp_write $src
    after 10
    set probe [issp_read]
    puts "MSHR Probe: [format 0x%016X $probe]"
    puts "======================="
}

#------------------------------------------------------------------------------
# Test Sequences
#------------------------------------------------------------------------------

# Test 1: Basic functionality test
proc test_basic {} {
    puts "\n========== TEST: Basic Cache Operations =========="
    
    cache_manual_mode
    cache_reset_counters
    
    # Sequential reads to same set (should cause hits after first miss)
    puts "\n--- Sequential Reads (same block) ---"
    cache_read 0x00000
    after 100
    cache_read 0x00004
    after 100
    cache_read 0x00008
    after 100
    
    cache_status
    
    puts "========== END TEST =========="
}

# Test 2: Hit/miss pattern
proc test_hit_miss {} {
    puts "\n========== TEST: Hit/Miss Pattern =========="
    
    cache_manual_mode
    cache_reset_counters
    
    # First access - cold miss
    puts "\n--- First access (cold miss expected) ---"
    cache_read 0x00000
    after 100
    cache_status
    
    # Same block - should hit
    puts "\n--- Same block access (hit expected) ---"
    cache_read 0x00004
    after 100
    cache_status
    
    # Different set - cold miss
    puts "\n--- Different set (cold miss expected) ---"
    cache_read 0x00100
    after 100
    cache_status
    
    puts "========== END TEST =========="
}

# Test 3: Conflict test (4-way associative)
proc test_conflict {} {
    puts "\n========== TEST: 4-Way Conflict =========="
    
    cache_manual_mode
    cache_reset_counters
    
    # Access 5 addresses that map to same set (should cause 1 eviction)
    # Set index = addr[9:5] for 8 sets, so addresses differ by 0x200 map to same set
    
    puts "\n--- Filling all 4 ways ---"
    cache_read 0x00000  ;# Way 0
    after 100
    cache_read 0x00200  ;# Way 1
    after 100
    cache_read 0x00400  ;# Way 2
    after 100
    cache_read 0x00600  ;# Way 3
    after 100
    
    cache_status
    
    puts "\n--- 5th access (causes eviction) ---"
    cache_read 0x00800  ;# Should evict one way
    after 100
    
    cache_status
    
    puts "========== END TEST =========="
}

# Test 4: MSHR non-blocking test
proc test_mshr {} {
    puts "\n========== TEST: MSHR Non-Blocking =========="
    
    cache_manual_mode
    cache_reset_counters
    
    # Quick successive reads to different sets
    puts "\n--- Multiple outstanding misses ---"
    cache_read 0x00000
    cache_read 0x00100
    cache_read 0x00200
    cache_read 0x00300
    
    after 500
    
    cache_status
    cache_mshr_status
    
    puts "========== END TEST =========="
}

# Run all tests
proc test_all {} {
    puts "\n###################################################"
    puts "# ISSP Cache Test Suite"
    puts "###################################################\n"
    
    test_basic
    after 500
    
    test_hit_miss
    after 500
    
    test_conflict
    after 500
    
    test_mshr
    
    puts "\n###################################################"
    puts "# All tests complete"
    puts "###################################################\n"
}

#------------------------------------------------------------------------------
# Interactive Commands
#------------------------------------------------------------------------------

proc help {} {
    puts ""
    puts "=============================================="
    puts "ISSP Cache Debug Commands"
    puts "=============================================="
    puts ""
    puts "Setup:"
    puts "  issp_init          - Find ISSP service"
    puts "  issp_open          - Open ISSP connection"
    puts "  issp_close         - Close ISSP connection"
    puts ""
    puts "Mode Control:"
    puts "  cache_auto_mode    - Auto test pattern"
    puts "  cache_manual_mode  - Manual ISSP control"
    puts "  cache_reset_counters - Reset statistics"
    puts ""
    puts "Cache Operations:"
    puts "  cache_read <addr>  - Read from address"
    puts "  cache_write <addr> <data> - Write to address"
    puts "  cache_status       - Show hit/miss stats"
    puts "  cache_mshr_status  - Show MSHR state"
    puts "  cache_select_probe <0-5> - Select probe view"
    puts ""
    puts "Tests:"
    puts "  test_basic         - Basic operations"
    puts "  test_hit_miss      - Hit/miss patterns"
    puts "  test_conflict      - 4-way conflict test"
    puts "  test_mshr          - Non-blocking test"
    puts "  test_all           - Run all tests"
    puts ""
    puts "Low-Level:"
    puts "  issp_write <val>   - Write raw source"
    puts "  issp_read          - Read raw probe"
    puts "  build_source ...   - Build source value"
    puts ""
    puts "=============================================="
    puts ""
}

#------------------------------------------------------------------------------
# Auto-run help on load
#------------------------------------------------------------------------------
puts ""
puts "ISSP Test Script Loaded"
puts "Type 'help' for available commands"
puts ""
puts "Quick Start:"
puts "  1. issp_init"
puts "  2. issp_open"
puts "  3. test_all"
puts "  4. issp_close"
puts ""
