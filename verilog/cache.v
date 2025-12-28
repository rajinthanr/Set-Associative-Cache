// Non-blocking 4-way set-associative cache with hit-under-miss
// Supports processing hits while a miss is being serviced
// Scalable: change NUM_SETS to increase size (8->16->32->64->512)
module cache (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        cpu_req_valid,
    input  wire        cpu_req_rw,
    input  wire [1:0]  cpu_req_size,
    input  wire [19:0] cpu_req_addr,
    input  wire [31:0] cpu_req_wdata,
    output reg         cpu_req_ready,
    output reg         cpu_resp_valid,
    output reg         cpu_resp_hit,
    output reg  [31:0] cpu_resp_rdata,
    output reg         mem_req_valid,
    output reg         mem_req_rw,
    output reg  [14:0] mem_req_addr,
    output reg [255:0] mem_req_wdata,
    input  wire        mem_resp_valid,
    input  wire [255:0] mem_resp_rdata
);
    // === SCALABLE PARAMETERS ===
    localparam NUM_SETS  = 8;
    localparam SET_BITS  = 3;
    localparam TAG_BITS  = 12;
    localparam ASSOC     = 4;
    localparam NUM_LINES = 32;
    localparam LINE_BITS = 256;

    // Storage arrays
    reg [TAG_BITS-1:0]  tag_array   [0:NUM_LINES-1];
    reg                 valid_array [0:NUM_LINES-1];
    reg                 dirty_array [0:NUM_LINES-1];
    reg [LINE_BITS-1:0] data_array  [0:NUM_LINES-1];

    // LFSR for random replacement
    reg [15:0] lfsr;

    // MSHR for non-blocking miss handling
    reg        mshr_valid;
    reg [14:0] mshr_block;
    reg [SET_BITS-1:0] mshr_set;
    reg [2:0]  mshr_word;
    reg        mshr_rw;
    reg [1:0]  mshr_size;
    reg [31:0] mshr_wdata;
    reg [5:0]  mshr_victim;
    reg        mshr_wb_pending;
    reg [TAG_BITS-1:0] mshr_tag;  // Tag of pending block

    // Address decoding
    wire [SET_BITS-1:0] addr_set   = cpu_req_addr[SET_BITS+4:5];
    wire [TAG_BITS-1:0] addr_tag   = cpu_req_addr[19:20-TAG_BITS];
    wire [14:0]         addr_block = cpu_req_addr[19:5];
    wire [2:0]          addr_word  = cpu_req_addr[4:2];

    // Check if current request conflicts with MSHR (same block being fetched)
    wire mshr_conflict = mshr_valid && (addr_block == mshr_block);

    // Working variables
    integer i, base, way, idx, hit_idx, bpos;
    reg hit;
    reg [LINE_BITS-1:0] line_rd, line_wr;
    reg [TAG_BITS-1:0] evict_tag;
    reg [14:0] evict_block;
    
    // For tracking hits during miss
    reg process_hit;
    reg [5:0] process_hit_idx;
    reg process_hit_rw;
    reg [1:0] process_hit_size;
    reg [2:0] process_hit_word;
    reg [31:0] process_hit_wdata;

    // Initialization
    initial begin
        lfsr = 16'hACE1;
        mshr_valid = 0;
        mshr_wb_pending = 0;
        for (i = 0; i < NUM_LINES; i = i + 1) begin
            valid_array[i] = 0;
            dirty_array[i] = 0;
        end
    end

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
            mshr_valid      <= 0;
            mshr_wb_pending <= 0;
            process_hit     <= 0;
            for (i = 0; i < NUM_LINES; i = i + 1) begin
                valid_array[i] <= 0;
                dirty_array[i] <= 0;
            end
        end
        else begin
            // LFSR update
            lfsr <= {lfsr[14:0], lfsr[15] ^ lfsr[13] ^ lfsr[12] ^ lfsr[10]};
            cpu_resp_valid <= 0;
            mem_req_valid  <= 0;
            process_hit    <= 0;

            // === MSHR State Machine (handles miss in background) ===
            
            // State: writeback complete, now fetch line
            if (mshr_valid && mshr_wb_pending) begin
                mshr_wb_pending <= 0;
                mem_req_valid   <= 1;
                mem_req_rw      <= 0;
                mem_req_addr    <= mshr_block;
            end
            // State: memory response for miss - install line and respond
            else if (mem_resp_valid && mshr_valid && !mshr_wb_pending) begin
                idx = mshr_victim;
                tag_array[idx]   <= mshr_block[14:15-TAG_BITS];
                valid_array[idx] <= 1;
                if (mshr_rw) begin
                    line_wr = mem_resp_rdata;
                    bpos = mshr_word * 4;
                    case (mshr_size)
                        2'b00: line_wr[bpos*8 +: 8]  = mshr_wdata[7:0];
                        2'b01: line_wr[bpos*8 +: 16] = mshr_wdata[15:0];
                        default: line_wr[bpos*8 +: 32] = mshr_wdata;
                    endcase
                    data_array[idx]  <= line_wr;
                    dirty_array[idx] <= 1;
                    cpu_resp_rdata   <= mshr_wdata;
                end
                else begin
                    data_array[idx]  <= mem_resp_rdata;
                    dirty_array[idx] <= 0;
                    cpu_resp_rdata   <= mem_resp_rdata[mshr_word*32 +: 32];
                end
                cpu_resp_valid <= 1;
                cpu_resp_hit   <= 0;  // This was a miss
                mshr_valid     <= 0;  // Free MSHR
            end

            // === CPU Request Handling (can process hits while miss pending) ===
            
            // Always ready unless: new miss AND mshr busy
            // We CAN accept requests if they hit, even with mshr_valid
            
            if (cpu_req_valid && cpu_req_ready) begin
                // Check for hit
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
                    // === HIT: Service immediately (even if MSHR busy) ===
                    cpu_resp_valid <= 1;
                    cpu_resp_hit   <= 1;
                    if (cpu_req_rw) begin
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
                        cpu_resp_rdata <= data_array[hit_idx][addr_word*32 +: 32];
                    end
                    // Stay ready for more requests
                    cpu_req_ready <= 1;
                end
                else if (mshr_conflict) begin
                    // === CONFLICT: Request to same block being fetched ===
                    // Must wait - don't accept this request yet
                    cpu_req_ready <= 0;
                end
                else if (!mshr_valid) begin
                    // === MISS: MSHR free, allocate it ===
                    mshr_valid  <= 1;
                    mshr_block  <= addr_block;
                    mshr_set    <= addr_set;
                    mshr_word   <= addr_word;
                    mshr_rw     <= cpu_req_rw;
                    mshr_size   <= cpu_req_size;
                    mshr_wdata  <= cpu_req_wdata;
                    mshr_tag    <= addr_tag;
                    mshr_victim <= base + lfsr[1:0];
                    idx = base + lfsr[1:0];
                    
                    if (valid_array[idx] && dirty_array[idx]) begin
                        // Dirty eviction - writeback first
                        evict_tag = tag_array[idx];
                        evict_block = {evict_tag, addr_set, 2'b00};
                        mem_req_valid    <= 1;
                        mem_req_rw       <= 1;
                        mem_req_addr     <= evict_block;
                        mem_req_wdata    <= data_array[idx];
                        dirty_array[idx] <= 0;
                        mshr_wb_pending  <= 1;
                    end
                    else begin
                        // Clean eviction - fetch directly
                        mem_req_valid   <= 1;
                        mem_req_rw      <= 0;
                        mem_req_addr    <= addr_block;
                        mshr_wb_pending <= 0;
                    end
                    
                    // IMPORTANT: Stay ready for hits while miss processes!
                    cpu_req_ready <= 1;
                end
                else begin
                    // === MISS but MSHR busy: Block until MSHR free ===
                    cpu_req_ready <= 0;
                end
            end
            
            // Re-enable ready when MSHR frees up (for blocked requests)
            if (!cpu_req_ready && !mshr_valid) begin
                cpu_req_ready <= 1;
            end
        end
    end
endmodule
