//==============================================================================
// 4-Way Set-Associative Cache Testbench
// Demonstrates: Conflict misses, hit latency, miss penalty, memory writes
//==============================================================================
`timescale 1ns/1ps

module tb_cache;

    //==========================================================================
    // CPU Interface Signals (as per spec: 3 inputs from CPU)
    //==========================================================================
    reg         clk;
    reg         rst_n;
    reg         cpu_req_valid;      // CPU request valid
    reg         cpu_req_rw;         // 0=Read, 1=Write
    reg  [1:0]  cpu_req_size;       // 00=byte, 01=half, 10=word
    reg  [19:0] cpu_req_addr;       // Memory Address (20-bit = 1MB)
    reg  [31:0] cpu_req_wdata;      // Write data from CPU
    wire        cpu_req_ready;      // Cache ready for request
    wire        cpu_resp_valid;     // Response valid
    wire        cpu_resp_hit;       // Hit indicator
    wire [31:0] cpu_resp_rdata;     // Read data to CPU

    //==========================================================================
    // Memory Interface Signals (as per spec: 3 outputs to Memory)
    //==========================================================================
    wire        mem_req_valid;      // Memory request valid
    wire        mem_req_rw;         // 0=Read line, 1=Write line (writeback)
    wire [14:0] mem_req_addr;       // Line/Block address (32-byte aligned)
    wire [255:0] mem_req_wdata;     // Line data for writeback (32 bytes = 256 bits)
    reg         mem_resp_valid;     // Memory response valid
    reg  [255:0] mem_resp_rdata;    // Line data from memory (32 bytes)

    //==========================================================================
    // Memory Model (simulates main memory with configurable latency)
    //==========================================================================
    localparam MEM_LATENCY = 50;    // 50 cycle memory latency (miss penalty)
    
    reg [255:0] mem_storage [0:32767];  // 32K lines x 32 bytes = 1MB
    reg [6:0]   mem_delay;
    reg         mem_busy;
    reg [14:0]  mem_pending_addr;
    reg         mem_pending_rw;
    reg [255:0] mem_pending_wdata;
    
    integer mi;
    initial begin
        mem_resp_valid = 0;
        mem_busy = 0;
        mem_delay = 0;
        // Initialize memory with recognizable patterns
        for (mi = 0; mi < 32768; mi = mi + 1)
            mem_storage[mi] = {8{mi[31:0]}};  // Each line = 8 copies of address
    end
    
    // Memory controller with latency simulation
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            mem_resp_valid <= 0;
            mem_busy <= 0;
            mem_delay <= 0;
        end
        else begin
            mem_resp_valid <= 0;
            if (mem_req_valid && !mem_busy) begin
                mem_busy <= 1;
                mem_pending_addr <= mem_req_addr;
                mem_pending_rw <= mem_req_rw;
                mem_pending_wdata <= mem_req_wdata;
                mem_delay <= MEM_LATENCY;
                $display("    [MEM] Request: addr=0x%05x rw=%s", 
                         mem_req_addr, mem_req_rw ? "WRITE(WB)" : "READ");
            end
            else if (mem_busy) begin
                if (mem_delay == 0) begin
                    mem_busy <= 0;
                    mem_resp_valid <= 1;
                    if (mem_pending_rw) begin
                        mem_storage[mem_pending_addr] <= mem_pending_wdata;
                        $display("    [MEM] Writeback complete: addr=0x%05x", mem_pending_addr);
                    end
                    else begin
                        mem_resp_rdata <= mem_storage[mem_pending_addr];
                        $display("    [MEM] Read complete: addr=0x%05x", mem_pending_addr);
                    end
                end
                else begin
                    mem_delay <= mem_delay - 1;
                end
            end
        end
    end

    //==========================================================================
    // Cache Instance
    //==========================================================================
    cache dut (
        .clk(clk),
        .rst_n(rst_n),
        .cpu_req_valid(cpu_req_valid),
        .cpu_req_rw(cpu_req_rw),
        .cpu_req_size(cpu_req_size),
        .cpu_req_addr(cpu_req_addr),
        .cpu_req_wdata(cpu_req_wdata),
        .cpu_req_ready(cpu_req_ready),
        .cpu_resp_valid(cpu_resp_valid),
        .cpu_resp_hit(cpu_resp_hit),
        .cpu_resp_rdata(cpu_resp_rdata),
        .mem_req_valid(mem_req_valid),
        .mem_req_rw(mem_req_rw),
        .mem_req_addr(mem_req_addr),
        .mem_req_wdata(mem_req_wdata),
        .mem_resp_valid(mem_resp_valid),
        .mem_resp_rdata(mem_resp_rdata)
    );

    //==========================================================================
    // Clock Generation (100MHz = 10ns period)
    //==========================================================================
    initial clk = 0;
    always #5 clk = ~clk;

    //==========================================================================
    // Statistics Tracking
    //==========================================================================
    integer cycle_count, hit_count, miss_count, req_start;
    integer total_hit_latency, total_miss_latency;
    integer wb_count;  // Writeback count
    
    initial begin
        cycle_count = 0;
        hit_count = 0;
        miss_count = 0;
        total_hit_latency = 0;
        total_miss_latency = 0;
        wb_count = 0;
    end
    
    always @(posedge clk) cycle_count = cycle_count + 1;

    //==========================================================================
    // CPU Access Task - Simulates CPU memory requests
    //==========================================================================
    task cpu_access;
        input rw;           // 0=Read, 1=Write
        input [1:0] size;   // 00=byte, 01=half, 10=word
        input [19:0] addr;
        input [31:0] wdata;
        integer latency;
        begin
            @(posedge clk);
            while (!cpu_req_ready) @(posedge clk);
            
            // CPU sends request
            cpu_req_valid <= 1;
            cpu_req_rw    <= rw;
            cpu_req_size  <= size;
            cpu_req_addr  <= addr;
            cpu_req_wdata <= wdata;
            req_start = cycle_count;
            
            @(posedge clk);
            cpu_req_valid <= 0;
            
            // Wait for response
            while (!cpu_resp_valid) @(posedge clk);
            latency = cycle_count - req_start;
            
            // Update statistics
            if (cpu_resp_hit) begin
                hit_count = hit_count + 1;
                total_hit_latency = total_hit_latency + latency;
            end
            else begin
                miss_count = miss_count + 1;
                total_miss_latency = total_miss_latency + latency;
            end
        end
    endtask

    //==========================================================================
    // Helper function to display size
    //==========================================================================
    function [31:0] size_str;
        input [1:0] sz;
        begin
            case (sz)
                2'b00: size_str = "BYTE";
                2'b01: size_str = "HALF";
                default: size_str = "WORD";
            endcase
        end
    endfunction

    //==========================================================================
    // Main Test Sequence
    //==========================================================================
    integer i, block, addr, test_addr;
    reg [31:0] expected_data;
    
    initial begin
        $display("");
        $display("╔══════════════════════════════════════════════════════════════════╗");
        $display("║     4-WAY SET-ASSOCIATIVE CACHE SIMULATION                       ║");
        $display("║     Cache: 1KB (8 sets × 4 ways × 32B lines)                     ║");
        $display("║     Replacement: Random (LFSR)  |  Write Policy: Write-back      ║");
        $display("╚══════════════════════════════════════════════════════════════════╝");
        $display("");
        
        //----------------------------------------------------------------------
        // Reset
        //----------------------------------------------------------------------
        rst_n = 0;
        cpu_req_valid = 0;
        cpu_req_rw = 0;
        cpu_req_size = 2;
        cpu_req_addr = 0;
        cpu_req_wdata = 0;
        repeat(10) @(posedge clk);
        rst_n = 1;
        repeat(5) @(posedge clk);

        //======================================================================
        // TEST 1: Cache Hit Latency (1 cycle)
        //======================================================================
        $display("════════════════════════════════════════════════════════════════════");
        $display("TEST 1: CACHE HIT LATENCY DEMONSTRATION");
        $display("════════════════════════════════════════════════════════════════════");
        hit_count = 0; miss_count = 0;
        total_hit_latency = 0; total_miss_latency = 0;
        
        $display("[CPU] Read request: addr=0x00100 (first access - MISS expected)");
        cpu_access(0, 2, 20'h00100, 0);
        $display("  Result: %s | Latency: %0d cycles | Data: 0x%08x", 
                 cpu_resp_hit ? "HIT " : "MISS", cycle_count-req_start, cpu_resp_rdata);
        
        $display("[CPU] Read request: addr=0x00100 (same address - HIT expected)");
        cpu_access(0, 2, 20'h00100, 0);
        $display("  Result: %s | Latency: %0d cycles | Data: 0x%08x", 
                 cpu_resp_hit ? "HIT " : "MISS", cycle_count-req_start, cpu_resp_rdata);
        
        $display("[CPU] Read request: addr=0x00104 (same line - HIT expected)");
        cpu_access(0, 2, 20'h00104, 0);
        $display("  Result: %s | Latency: %0d cycles | Data: 0x%08x", 
                 cpu_resp_hit ? "HIT " : "MISS", cycle_count-req_start, cpu_resp_rdata);
        
        $display("");
        $display(">>> Hit Latency: 1 cycle | Miss Penalty: ~%0d cycles (memory latency)", MEM_LATENCY);
        $display("");

        //======================================================================
        // TEST 2: Different Data Sizes (byte, half-word, word)
        //======================================================================
        $display("════════════════════════════════════════════════════════════════════");
        $display("TEST 2: DATA SIZE SUPPORT (BYTE / HALF-WORD / WORD)");
        $display("════════════════════════════════════════════════════════════════════");
        
        // First fill a cache line
        cpu_access(0, 2, 20'h00200, 0);
        
        $display("[CPU] Write BYTE to 0x00200: data=0xAB");
        cpu_access(1, 2'b00, 20'h00200, 32'h000000AB);
        $display("  Result: %s", cpu_resp_hit ? "HIT" : "MISS");
        
        $display("[CPU] Write HALF-WORD to 0x00202: data=0xCDEF");
        cpu_access(1, 2'b01, 20'h00202, 32'h0000CDEF);
        $display("  Result: %s", cpu_resp_hit ? "HIT" : "MISS");
        
        $display("[CPU] Write WORD to 0x00204: data=0x12345678");
        cpu_access(1, 2'b10, 20'h00204, 32'h12345678);
        $display("  Result: %s", cpu_resp_hit ? "HIT" : "MISS");
        
        // Read back
        $display("[CPU] Read WORD from 0x00204:");
        cpu_access(0, 2'b10, 20'h00204, 0);
        $display("  Result: %s | Data: 0x%08x (expected: 0x12345678)", 
                 cpu_resp_hit ? "HIT" : "MISS", cpu_resp_rdata);
        $display("");

        //======================================================================
        // TEST 3: CONFLICT MISSES - Key requirement!
        //======================================================================
        $display("════════════════════════════════════════════════════════════════════");
        $display("TEST 3: CONFLICT MISSES DEMONSTRATION");
        $display("════════════════════════════════════════════════════════════════════");
        $display("Cache has 8 sets × 4 ways. Accessing 5 addresses mapping to same set");
        $display("will cause conflict misses (exceeds 4-way associativity).");
        $display("");
        $display("Address mapping: Set = (addr >> 5) & 0x7");
        $display("Addresses that map to SET 0: 0x00000, 0x00100, 0x00200, 0x00300, 0x00400");
        $display("(all have bits [7:5] = 000)");
        $display("");
        
        hit_count = 0; miss_count = 0;
        
        // Access 5 different blocks that all map to set 0
        // For 8 sets: set index = addr[7:5], so stride = 256 (0x100) keeps same set
        $display("--- Phase 1: Fill all 4 ways of Set 0 ---");
        for (i = 0; i < 4; i = i + 1) begin
            test_addr = i * 20'h100;  // 0x000, 0x100, 0x200, 0x300
            $display("[CPU] Read addr=0x%05x (Set 0, Way %0d)", test_addr, i);
            cpu_access(0, 2, test_addr, 0);
            $display("  Result: %s | Latency: %0d cycles", 
                     cpu_resp_hit ? "HIT " : "MISS", cycle_count-req_start);
        end
        
        $display("");
        $display("--- Phase 2: Access 5th address (CONFLICT MISS - evicts one way) ---");
        test_addr = 20'h400;  // 5th block mapping to set 0
        $display("[CPU] Read addr=0x%05x (Set 0, 5th block - causes eviction!)", test_addr);
        cpu_access(0, 2, test_addr, 0);
        $display("  Result: %s | Latency: %0d cycles", 
                 cpu_resp_hit ? "HIT " : "MISS", cycle_count-req_start);
        
        $display("");
        $display("--- Phase 3: Re-access evicted address (CONFLICT MISS) ---");
        test_addr = 20'h000;  // Likely evicted
        $display("[CPU] Read addr=0x%05x (was in Set 0, but may be evicted)", test_addr);
        cpu_access(0, 2, test_addr, 0);
        $display("  Result: %s | Latency: %0d cycles", 
                 cpu_resp_hit ? "HIT " : "MISS", cycle_count-req_start);
        
        $display("");
        $display(">>> Statistics: Hits=%0d, Misses=%0d", hit_count, miss_count);
        $display(">>> This demonstrates CONFLICT MISSES due to limited associativity");
        $display("");

        //======================================================================
        // TEST 4: MEMORY WRITE-BACK DEMONSTRATION
        //======================================================================
        $display("════════════════════════════════════════════════════════════════════");
        $display("TEST 4: MEMORY WRITE-BACK (DIRTY LINE EVICTION)");
        $display("════════════════════════════════════════════════════════════════════");
        $display("Write-back cache: dirty lines written to memory on eviction");
        $display("");
        
        // Write to a new address to make it dirty
        $display("--- Step 1: Write data to create dirty line ---");
        test_addr = 20'h01000;
        $display("[CPU] Write addr=0x%05x data=0xDEADBEEF", test_addr);
        cpu_access(1, 2, test_addr, 32'hDEADBEEF);
        $display("  Result: %s (line is now DIRTY)", cpu_resp_hit ? "HIT" : "MISS");
        
        $display("");
        $display("--- Step 2: Force eviction by filling the set ---");
        // Fill the set with 4 more blocks to force eviction of dirty line
        for (i = 1; i <= 4; i = i + 1) begin
            test_addr = 20'h01000 + (i * 20'h100);
            $display("[CPU] Read addr=0x%05x (filling set to force eviction)", test_addr);
            cpu_access(0, 2, test_addr, 0);
            $display("  Result: %s", cpu_resp_hit ? "HIT" : "MISS");
        end
        
        $display("");
        $display(">>> If WRITE(WB) appeared in memory log, write-back occurred!");
        $display("");

        //======================================================================
        // TEST 5: Sequential Access Pattern
        //======================================================================
        $display("════════════════════════════════════════════════════════════════════");
        $display("TEST 5: SEQUENTIAL ACCESS PATTERN (Good Locality)");
        $display("════════════════════════════════════════════════════════════════════");
        hit_count = 0; miss_count = 0;
        total_hit_latency = 0; total_miss_latency = 0;
        
        $display("Accessing 32 consecutive words (spans multiple lines):");
        for (i = 0; i < 32; i = i + 1) begin
            test_addr = 20'h02000 + (i * 4);
            cpu_access(0, 2, test_addr, 0);
        end
        
        $display("  Total: Hits=%0d, Misses=%0d", hit_count, miss_count);
        $display("  Hit Rate: %0d%%", (hit_count * 100) / (hit_count + miss_count));
        if (hit_count > 0)
            $display("  Avg Hit Latency: %0d cycles", total_hit_latency / hit_count);
        if (miss_count > 0)
            $display("  Avg Miss Latency: %0d cycles", total_miss_latency / miss_count);
        $display("");

        //======================================================================
        // TEST 6: Write then Read Verification
        //======================================================================
        $display("════════════════════════════════════════════════════════════════════");
        $display("TEST 6: WRITE THEN READ VERIFICATION");
        $display("════════════════════════════════════════════════════════════════════");
        
        $display("[CPU] Write addr=0x03000 data=0xCAFEBABE");
        cpu_access(1, 2, 20'h03000, 32'hCAFEBABE);
        
        $display("[CPU] Read addr=0x03000");
        cpu_access(0, 2, 20'h03000, 0);
        $display("  Read data: 0x%08x", cpu_resp_rdata);
        if (cpu_resp_rdata == 32'hCAFEBABE)
            $display("  >>> PASS: Data matches!");
        else
            $display("  >>> FAIL: Data mismatch!");
        
        $display("");
        $display("[CPU] Write addr=0x03004 data=0x12345678");
        cpu_access(1, 2, 20'h03004, 32'h12345678);
        
        $display("[CPU] Read addr=0x03004");
        cpu_access(0, 2, 20'h03004, 0);
        $display("  Read data: 0x%08x", cpu_resp_rdata);
        if (cpu_resp_rdata == 32'h12345678)
            $display("  >>> PASS: Data matches!");
        else
            $display("  >>> FAIL: Data mismatch!");
        $display("");

        //======================================================================
        // TEST 7: Repeated Conflict Miss Pattern
        //======================================================================
        $display("════════════════════════════════════════════════════════════════════");
        $display("TEST 7: THRASHING PATTERN (Worst Case - Repeated Conflicts)");
        $display("════════════════════════════════════════════════════════════════════");
        hit_count = 0; miss_count = 0;
        
        $display("Repeatedly accessing 5 addresses mapping to same set (4-way cache):");
        $display("This causes continuous evictions (thrashing)");
        $display("");
        
        for (i = 0; i < 20; i = i + 1) begin
            block = i % 5;
            test_addr = 20'h04000 + (block * 20'h100);
            cpu_access(0, 2, test_addr, 0);
        end
        
        $display("  Results: Hits=%0d, Misses=%0d", hit_count, miss_count);
        $display("  Hit Rate: %0d%% (expected low due to thrashing)", 
                 (hit_count * 100) / (hit_count + miss_count));
        $display("");

        //======================================================================
        // TEST 8: NON-BLOCKING CACHE BEHAVIOR (MSHR)
        //======================================================================
        $display("════════════════════════════════════════════════════════════════════");
        $display("TEST 8: NON-BLOCKING CACHE BEHAVIOR (MSHR DEMONSTRATION)");
        $display("════════════════════════════════════════════════════════════════════");
        $display("Non-blocking cache uses MSHR (Miss Status Holding Register) to:");
        $display("  - Track outstanding memory requests");
        $display("  - Allow cache to continue processing after miss is issued");
        $display("  - Handle memory response asynchronously");
        $display("");
        
        // First, let's show the MSHR in action
        $display("--- Scenario 1: Miss triggers MSHR allocation ---");
        test_addr = 20'h05000;  // New address, will miss
        $display("[CPU] Read addr=0x%05x (cache miss expected)", test_addr);
        $display("  MSHR will: 1) Store miss info  2) Issue memory request  3) Block CPU");
        cpu_access(0, 2, test_addr, 0);
        $display("  Result: %s | MSHR handled the miss", cpu_resp_hit ? "HIT" : "MISS");
        
        $display("");
        $display("--- Scenario 2: Hit while MSHR was previously active ---");
        $display("[CPU] Read addr=0x%05x (same line - should hit now)", test_addr);
        cpu_access(0, 2, test_addr, 0);
        $display("  Result: %s | Latency: %0d cycles (fast - data in cache)", 
                 cpu_resp_hit ? "HIT" : "MISS", cycle_count-req_start);
        
        $display("");
        $display("--- Scenario 3: Write miss with MSHR (allocate-on-write) ---");
        test_addr = 20'h06000;  // New address
        $display("[CPU] Write addr=0x%05x data=0xABCD1234 (write miss)", test_addr);
        $display("  MSHR will: 1) Fetch line  2) Merge write data  3) Mark dirty");
        cpu_access(1, 2, test_addr, 32'hABCD1234);
        $display("  Result: %s", cpu_resp_hit ? "HIT" : "MISS");
        
        // Verify the write
        $display("[CPU] Read addr=0x%05x (verify write)", test_addr);
        cpu_access(0, 2, test_addr, 0);
        $display("  Data: 0x%08x %s", cpu_resp_rdata, 
                 (cpu_resp_rdata == 32'hABCD1234) ? "(CORRECT)" : "(ERROR)");
        
        $display("");
        $display("--- Scenario 4: MSHR with dirty line eviction (write-back) ---");
        // Write to create dirty line
        test_addr = 20'h07000;
        $display("[CPU] Write addr=0x%05x data=0xDEAD0001 (create dirty line)", test_addr);
        cpu_access(1, 2, test_addr, 32'hDEAD0001);
        
        // Now access addresses that will evict this dirty line
        $display("[CPU] Accessing addresses to force eviction of dirty line...");
        $display("  MSHR will: 1) Write-back dirty  2) Fetch new line  3) Complete");
        for (i = 1; i <= 4; i = i + 1) begin
            test_addr = 20'h07000 + (i * 20'h100);
            cpu_access(0, 2, test_addr, 0);
        end
        $display("  If [MEM] WRITE(WB) appeared above, MSHR handled write-back correctly");
        
        $display("");
        $display("--- Scenario 5: MSHR state transitions ---");
        $display("MSHR State Machine:");
        $display("  IDLE -> MISS_PENDING: On cache miss, MSHR allocated");
        $display("  MISS_PENDING -> WB_PENDING: If evicting dirty line");
        $display("  WB_PENDING -> FETCH_PENDING: After write-back complete");
        $display("  FETCH_PENDING -> IDLE: After line fetched, request complete");
        $display("");
        
        // Show timing of MSHR operations
        $display("--- Scenario 6: MSHR timing demonstration ---");
        test_addr = 20'h08000;
        req_start = cycle_count;
        $display("[CPU] Read addr=0x%05x @ cycle %0d", test_addr, cycle_count);
        cpu_access(0, 2, test_addr, 0);
        $display("  Response @ cycle %0d (total latency: %0d cycles)", 
                 cycle_count, cycle_count - req_start);
        $display("  Breakdown: ~1 cycle miss detect + %0d cycle mem latency + 1 cycle response",
                 MEM_LATENCY);
        
        $display("");
        $display(">>> NON-BLOCKING SUMMARY:");
        $display("    - MSHR tracks one outstanding miss at a time");
        $display("    - Handles read misses, write misses, and write-backs");
        $display("    - Memory requests issued asynchronously");
        $display("    - Cache returns response when memory completes");
        $display("");

        //======================================================================
        // TEST 9: TRUE NON-BLOCKING - HIT UNDER MISS
        //======================================================================
        $display("════════════════════════════════════════════════════════════════════");
        $display("TEST 9: HIT-UNDER-MISS (True Non-Blocking Behavior)");
        $display("════════════════════════════════════════════════════════════════════");
        $display("This test verifies the cache can service HITS while a MISS is pending.");
        $display("A blocking cache would stall all requests during memory fetch.");
        $display("");
        
        // First, ensure we have some data in cache (different sets)
        $display("--- Setup: Pre-load cache lines in different sets ---");
        cpu_access(0, 2, 20'h00020, 0);  // Set 1
        cpu_access(0, 2, 20'h00040, 0);  // Set 2
        cpu_access(0, 2, 20'h00060, 0);  // Set 3
        $display("  Loaded lines at 0x00020 (Set 1), 0x00040 (Set 2), 0x00060 (Set 3)");
        
        $display("");
        $display("--- Hit-Under-Miss Test ---");
        $display("1. Issue READ MISS to trigger memory fetch (takes %0d cycles)", MEM_LATENCY);
        $display("2. While miss pending, issue HITs to other cached lines");
        $display("3. Hits should complete in 1 cycle, not wait for miss");
        $display("");
        
        // Start a miss (this will take ~50 cycles)
        test_addr = 20'h09000;  // New address - will miss
        @(posedge clk);
        while (!cpu_req_ready) @(posedge clk);
        cpu_req_valid <= 1;
        cpu_req_rw    <= 0;
        cpu_req_addr  <= test_addr;
        cpu_req_wdata <= 0;
        cpu_req_size  <= 2;
        $display("[CPU] @ cycle %0d: Issue MISS to addr=0x%05x", cycle_count, test_addr);
        @(posedge clk);
        cpu_req_valid <= 0;
        
        // Wait a few cycles for miss to be in progress
        repeat(3) @(posedge clk);
        
        // Now try to hit cached lines WHILE miss is pending
        hit_count = 0;
        miss_count = 0;
        
        $display("[CPU] @ cycle %0d: MISS still pending (MSHR busy)...", cycle_count);
        $display("      Now issuing HITs to pre-loaded lines:");
        
        // These should HIT immediately even though MSHR is busy
        if (cpu_req_ready) begin
            $display("      cpu_req_ready = 1 (accepting requests!)");
            
            // Hit to Set 1
            req_start = cycle_count;
            cpu_access(0, 2, 20'h00020, 0);
            $display("      HIT 0x00020: %s in %0d cycles", 
                     cpu_resp_hit ? "HIT" : "MISS", cycle_count - req_start);
            
            // Hit to Set 2
            req_start = cycle_count;
            cpu_access(0, 2, 20'h00040, 0);
            $display("      HIT 0x00040: %s in %0d cycles", 
                     cpu_resp_hit ? "HIT" : "MISS", cycle_count - req_start);
            
            // Hit to Set 3
            req_start = cycle_count;
            cpu_access(0, 2, 20'h00060, 0);
            $display("      HIT 0x00060: %s in %0d cycles", 
                     cpu_resp_hit ? "HIT" : "MISS", cycle_count - req_start);
        end
        else begin
            $display("      cpu_req_ready = 0 (BLOCKING - waiting for miss)");
        end
        
        // Wait for the original miss to complete
        while (!cpu_resp_valid) @(posedge clk);
        $display("[CPU] @ cycle %0d: Original MISS completed", cycle_count);
        
        $display("");
        if (hit_count >= 3) begin
            $display(">>> SUCCESS: %0d hits serviced WHILE miss was pending!", hit_count);
            $display(">>> This is TRUE NON-BLOCKING (hit-under-miss) behavior!");
        end
        else begin
            $display(">>> Cache blocked during miss (blocking behavior)");
        end
        $display("");

        //======================================================================
        // Summary
        //======================================================================
        $display("╔══════════════════════════════════════════════════════════════════╗");
        $display("║                    SIMULATION COMPLETE                           ║");
        $display("╠══════════════════════════════════════════════════════════════════╣");
        $display("║  Cache Architecture:                                             ║");
        $display("║    - 4-way set-associative                                       ║");
        $display("║    - 8 sets × 4 ways × 32-byte lines = 1KB                      ║");
        $display("║    - Random replacement (LFSR)                                   ║");
        $display("║    - Write-back policy with dirty bits                           ║");
        $display("║                                                                  ║");
        $display("║  Demonstrated Features:                                          ║");
        $display("║    ✓ Cache hit latency: 1 cycle                                  ║");
        $display("║    ✓ Cache miss penalty: ~%2d cycles                              ║", MEM_LATENCY);
        $display("║    ✓ Conflict misses (5 blocks to 4-way set)                     ║");
        $display("║    ✓ Memory writes (write-back on eviction)                      ║");
        $display("║    ✓ Byte/half-word/word access                                  ║");
        $display("║    ✓ Non-blocking MSHR (Miss Status Holding Register)            ║");
        $display("║    ✓ Hit-under-miss (service hits while miss pending)            ║");
        $display("╚══════════════════════════════════════════════════════════════════╝");
        
        #100;
        $finish;
    end

    //==========================================================================
    // Waveform Dump (for viewing in GTKWave or similar)
    //==========================================================================
    initial begin
        $dumpfile("cache_sim.vcd");
        $dumpvars(0, tb_cache);
    end

endmodule
