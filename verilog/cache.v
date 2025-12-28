//==============================================================================
// Non-blocking 4-way set-associative cache with MULTI-LEVEL MSHR
// Supports: hit-under-miss AND miss-under-miss (configurable MSHR depth)
// Scalable: change NUM_SETS for cache size, NUM_MSHR for miss parallelism
//==============================================================================
module cache (
    input  wire        clk,
    input  wire        rst_n,
    // CPU Interface
    input  wire        cpu_req_valid,
    input  wire        cpu_req_rw,       // 0=read, 1=write
    input  wire [1:0]  cpu_req_size,     // 0=byte, 1=half, 2=word
    input  wire [19:0] cpu_req_addr,
    input  wire [31:0] cpu_req_wdata,
    output reg         cpu_req_ready,
    output reg         cpu_resp_valid,
    output reg         cpu_resp_hit,
    output reg  [31:0] cpu_resp_rdata,
    // Memory Interface
    output reg         mem_req_valid,
    output reg         mem_req_rw,
    output reg  [14:0] mem_req_addr,
    output reg [255:0] mem_req_wdata,
    input  wire        mem_resp_valid,
    input  wire [255:0] mem_resp_rdata
);

    //==========================================================================
    // CONFIGURABLE PARAMETERS
    //==========================================================================
    // Cache geometry
    localparam NUM_SETS   = 8;       // Number of sets (8, 16, 32, 64, 512)
    localparam SET_BITS   = 3;       // log2(NUM_SETS)
    localparam TAG_BITS   = 12;      // 20 - SET_BITS - 5
    localparam ASSOC      = 4;       // Ways per set
    localparam NUM_LINES  = 32;      // NUM_SETS * ASSOC
    localparam LINE_BITS  = 256;     // 32 bytes * 8 bits

    // MSHR configuration - CHANGE THIS TO ADJUST MISS PARALLELISM
    localparam NUM_MSHR   = 4;       // Number of MSHR entries (1, 2, 4, 8)
    localparam MSHR_BITS  = 2;       // log2(NUM_MSHR)

    //==========================================================================
    // STORAGE ARRAYS
    //==========================================================================
    reg [TAG_BITS-1:0]  tag_array   [0:NUM_LINES-1];
    reg                 valid_array [0:NUM_LINES-1];
    reg                 dirty_array [0:NUM_LINES-1];
    reg [LINE_BITS-1:0] data_array  [0:NUM_LINES-1];

    // LFSR for random replacement
    reg [15:0] lfsr;

    //==========================================================================
    // MULTI-LEVEL MSHR (Miss Status Holding Registers)
    //==========================================================================
    // Each MSHR entry tracks one outstanding miss
    reg                    mshr_valid      [0:NUM_MSHR-1];  // Entry in use
    reg                    mshr_issued     [0:NUM_MSHR-1];  // Memory request issued
    reg                    mshr_wb_pending [0:NUM_MSHR-1];  // Writeback pending
    reg [14:0]             mshr_block      [0:NUM_MSHR-1];  // Block address
    reg [SET_BITS-1:0]     mshr_set        [0:NUM_MSHR-1];  // Set index
    reg [2:0]              mshr_word       [0:NUM_MSHR-1];  // Word offset
    reg                    mshr_rw         [0:NUM_MSHR-1];  // Read/Write
    reg [1:0]              mshr_size       [0:NUM_MSHR-1];  // Access size
    reg [31:0]             mshr_wdata      [0:NUM_MSHR-1];  // Write data
    reg [5:0]              mshr_victim     [0:NUM_MSHR-1];  // Victim line index
    reg [LINE_BITS-1:0]    mshr_wb_data    [0:NUM_MSHR-1];  // Writeback data
    reg [14:0]             mshr_wb_addr    [0:NUM_MSHR-1];  // Writeback address

    // MSHR status signals
    reg [MSHR_BITS-1:0] mshr_free_idx;     // Index of free MSHR entry
    reg                 mshr_has_free;      // At least one MSHR is free
    reg [MSHR_BITS-1:0] mshr_active_idx;   // Currently active MSHR (for mem req)
    reg                 mshr_conflict;      // Request conflicts with pending MSHR

    //==========================================================================
    // ADDRESS DECODING
    //==========================================================================
    wire [SET_BITS-1:0] addr_set   = cpu_req_addr[SET_BITS+4:5];
    wire [TAG_BITS-1:0] addr_tag   = cpu_req_addr[19:20-TAG_BITS];
    wire [14:0]         addr_block = cpu_req_addr[19:5];
    wire [2:0]          addr_word  = cpu_req_addr[4:2];

    //==========================================================================
    // WORKING VARIABLES
    //==========================================================================
    integer i, j, base, way, idx, hit_idx, bpos;
    reg hit;
    reg [LINE_BITS-1:0] line_rd, line_wr;
    reg [TAG_BITS-1:0] evict_tag;
    reg [14:0] evict_block;
    reg found_free;
    reg found_conflict;
    reg [MSHR_BITS-1:0] resp_mshr_idx;

    //==========================================================================
    // INITIALIZATION
    //==========================================================================
    initial begin
        lfsr = 16'hACE1;
        for (i = 0; i < NUM_LINES; i = i + 1) begin
            valid_array[i] = 0;
            dirty_array[i] = 0;
        end
        for (i = 0; i < NUM_MSHR; i = i + 1) begin
            mshr_valid[i] = 0;
            mshr_issued[i] = 0;
            mshr_wb_pending[i] = 0;
        end
    end

    //==========================================================================
    // MSHR STATUS COMPUTATION (combinational)
    //==========================================================================
    always @(*) begin
        // Find free MSHR entry
        found_free = 0;
        mshr_free_idx = 0;
        for (i = 0; i < NUM_MSHR; i = i + 1) begin
            if (!mshr_valid[i] && !found_free) begin
                found_free = 1;
                mshr_free_idx = i[MSHR_BITS-1:0];
            end
        end
        mshr_has_free = found_free;

        // Check for conflict (request to block already being fetched)
        found_conflict = 0;
        for (i = 0; i < NUM_MSHR; i = i + 1) begin
            if (mshr_valid[i] && mshr_block[i] == addr_block) begin
                found_conflict = 1;
            end
        end
        mshr_conflict = found_conflict;
    end

    //==========================================================================
    // MAIN CACHE CONTROLLER
    //==========================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            cpu_req_ready   <= 1;
            cpu_resp_valid  <= 0;
            cpu_resp_hit    <= 0;
            cpu_resp_rdata  <= 0;
            mem_req_valid   <= 0;
            mem_req_rw      <= 0;
            mem_req_addr    <= 0;
            mem_req_wdata   <= 0;
            lfsr            <= 16'hACE1;
            for (i = 0; i < NUM_LINES; i = i + 1) begin
                valid_array[i] <= 0;
                dirty_array[i] <= 0;
            end
            for (i = 0; i < NUM_MSHR; i = i + 1) begin
                mshr_valid[i]      <= 0;
                mshr_issued[i]     <= 0;
                mshr_wb_pending[i] <= 0;
            end
        end
        else begin
            // LFSR update for random replacement
            lfsr <= {lfsr[14:0], lfsr[15] ^ lfsr[13] ^ lfsr[12] ^ lfsr[10]};
            
            // Default: clear response and mem request
            cpu_resp_valid <= 0;
            mem_req_valid  <= 0;

            //==================================================================
            // MSHR STATE MACHINE - Process outstanding misses
            //==================================================================
            for (i = 0; i < NUM_MSHR; i = i + 1) begin
                if (mshr_valid[i]) begin
                    // State: Need to issue writeback
                    if (mshr_wb_pending[i] && !mshr_issued[i] && !mem_req_valid) begin
                        mem_req_valid    <= 1;
                        mem_req_rw       <= 1;  // Write
                        mem_req_addr     <= mshr_wb_addr[i];
                        mem_req_wdata    <= mshr_wb_data[i];
                        mshr_issued[i]   <= 1;
                        mshr_active_idx  <= i[MSHR_BITS-1:0];
                    end
                    // State: Need to issue fetch (after writeback or clean miss)
                    else if (!mshr_wb_pending[i] && !mshr_issued[i] && !mem_req_valid) begin
                        mem_req_valid    <= 1;
                        mem_req_rw       <= 0;  // Read
                        mem_req_addr     <= mshr_block[i];
                        mshr_issued[i]   <= 1;
                        mshr_active_idx  <= i[MSHR_BITS-1:0];
                    end
                end
            end

            //==================================================================
            // MEMORY RESPONSE HANDLING
            //==================================================================
            if (mem_resp_valid) begin
                // Find which MSHR this response is for
                for (i = 0; i < NUM_MSHR; i = i + 1) begin
                    if (mshr_valid[i] && mshr_issued[i]) begin
                        if (mshr_wb_pending[i]) begin
                            // Writeback complete - now issue fetch
                            mshr_wb_pending[i] <= 0;
                            mshr_issued[i]     <= 0;  // Ready to issue fetch
                        end
                        else begin
                            // Fetch complete - install line and respond
                            idx = mshr_victim[i];
                            tag_array[idx]   <= mshr_block[i][14:15-TAG_BITS];
                            valid_array[idx] <= 1;
                            
                            if (mshr_rw[i]) begin
                                // Write miss - merge write data
                                line_wr = mem_resp_rdata;
                                bpos = mshr_word[i] * 4;
                                case (mshr_size[i])
                                    2'b00: line_wr[bpos*8 +: 8]  = mshr_wdata[i][7:0];
                                    2'b01: line_wr[bpos*8 +: 16] = mshr_wdata[i][15:0];
                                    default: line_wr[bpos*8 +: 32] = mshr_wdata[i];
                                endcase
                                data_array[idx]  <= line_wr;
                                dirty_array[idx] <= 1;
                                cpu_resp_rdata   <= mshr_wdata[i];
                            end
                            else begin
                                // Read miss
                                data_array[idx]  <= mem_resp_rdata;
                                dirty_array[idx] <= 0;
                                cpu_resp_rdata   <= mem_resp_rdata[mshr_word[i]*32 +: 32];
                            end
                            
                            cpu_resp_valid <= 1;
                            cpu_resp_hit   <= 0;  // Was a miss
                            
                            // Free this MSHR
                            mshr_valid[i]  <= 0;
                            mshr_issued[i] <= 0;
                        end
                    end
                end
            end

            //==================================================================
            // CPU REQUEST HANDLING
            //==================================================================
            if (cpu_req_valid && cpu_req_ready) begin
                // Check for cache hit
                hit = 0;
                hit_idx = 0;
                base = addr_set * ASSOC;
                for (way = 0; way < ASSOC; way = way + 1) begin
                    idx = base + way;
                    if (valid_array[idx] && tag_array[idx] == addr_tag) begin
                        hit = 1;
                        hit_idx = idx;
                    end
                end

                if (hit) begin
                    //==========================================================
                    // CACHE HIT - Service immediately
                    //==========================================================
                    cpu_resp_valid <= 1;
                    cpu_resp_hit   <= 1;
                    
                    if (cpu_req_rw) begin
                        // Write hit
                        line_rd = data_array[hit_idx];
                        bpos = addr_word * 4;
                        case (cpu_req_size)
                            2'b00: line_rd[bpos*8 +: 8]  = cpu_req_wdata[7:0];
                            2'b01: line_rd[bpos*8 +: 16] = cpu_req_wdata[15:0];
                            default: line_rd[bpos*8 +: 32] = cpu_req_wdata;
                        endcase
                        data_array[hit_idx]  <= line_rd;
                        dirty_array[hit_idx] <= 1;
                        cpu_resp_rdata <= cpu_req_wdata;
                    end
                    else begin
                        // Read hit
                        cpu_resp_rdata <= data_array[hit_idx][addr_word*32 +: 32];
                    end
                    
                    cpu_req_ready <= 1;  // Ready for next request
                end
                else if (mshr_conflict) begin
                    //==========================================================
                    // CONFLICT - Same block already being fetched
                    //==========================================================
                    // Block until that MSHR completes
                    cpu_req_ready <= 0;
                end
                else if (mshr_has_free) begin
                    //==========================================================
                    // CACHE MISS - Allocate MSHR entry
                    //==========================================================
                    i = mshr_free_idx;
                    mshr_valid[i]  <= 1;
                    mshr_issued[i] <= 0;
                    mshr_block[i]  <= addr_block;
                    mshr_set[i]    <= addr_set;
                    mshr_word[i]   <= addr_word;
                    mshr_rw[i]     <= cpu_req_rw;
                    mshr_size[i]   <= cpu_req_size;
                    mshr_wdata[i]  <= cpu_req_wdata;
                    mshr_victim[i] <= base + lfsr[1:0];
                    
                    idx = base + lfsr[1:0];
                    
                    if (valid_array[idx] && dirty_array[idx]) begin
                        // Dirty eviction - need writeback first
                        evict_tag = tag_array[idx];
                        evict_block = {evict_tag, addr_set, 2'b00};
                        mshr_wb_pending[i] <= 1;
                        mshr_wb_addr[i]    <= evict_block;
                        mshr_wb_data[i]    <= data_array[idx];
                        dirty_array[idx]   <= 0;
                    end
                    else begin
                        // Clean - fetch directly
                        mshr_wb_pending[i] <= 0;
                    end
                    
                    // IMPORTANT: Stay ready for more requests!
                    // Multi-MSHR allows multiple outstanding misses
                    cpu_req_ready <= 1;
                end
                else begin
                    //==========================================================
                    // ALL MSHR FULL - Must block
                    //==========================================================
                    cpu_req_ready <= 0;
                end
            end

            //==================================================================
            // RE-ENABLE READY when blocked and MSHR frees up
            //==================================================================
            if (!cpu_req_ready && mshr_has_free && !mshr_conflict) begin
                cpu_req_ready <= 1;
            end
        end
    end

endmodule
