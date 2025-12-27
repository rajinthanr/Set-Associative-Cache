// Small 1KB 4-way set-associative cache for fast synthesis
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
    // To scale: change NUM_SETS (8=1KB, 16=2KB, 32=4KB, 64=8KB, 512=64KB)
    // SET_BITS = log2(NUM_SETS), TAG_BITS = 20 - SET_BITS - 5
    localparam NUM_SETS  = 8;       // 8 sets (scale: 8,16,32,64,512)
    localparam SET_BITS  = 3;       // log2(8)=3 (scale: 3,4,5,6,9)
    localparam TAG_BITS  = 12;      // 20-3-5=12 (scale: 12,11,10,9,6)
    localparam ASSOC     = 4;       // 4 ways (fixed)
    localparam NUM_LINES = 32;      // NUM_SETS * ASSOC (scale: 32,64,128,256,2048)
    localparam LINE_BITS = 256;     // 32 bytes per line (fixed)

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
    reg [5:0]  mshr_victim;  // log2(NUM_LINES) bits needed
    reg        mshr_wb_pending;

    // Address decoding (adjust bit ranges for different cache sizes)
    wire [SET_BITS-1:0] addr_set   = cpu_req_addr[SET_BITS+4:5];
    wire [TAG_BITS-1:0] addr_tag   = cpu_req_addr[19:20-TAG_BITS];
    wire [14:0]         addr_block = cpu_req_addr[19:5];
    wire [2:0]          addr_word  = cpu_req_addr[4:2];

    // Working variables
    integer i, base, way, idx, hit_idx, bpos;
    reg hit;
    reg [LINE_BITS-1:0] line_rd, line_wr;
    reg [TAG_BITS-1:0] evict_tag;
    reg [14:0] evict_block;

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

            // State: writeback complete, now fetch line
            if (mshr_valid && mshr_wb_pending) begin
                mshr_wb_pending <= 0;
                mem_req_valid   <= 1;
                mem_req_rw      <= 0;
                mem_req_addr    <= mshr_block;
            end
            // State: memory response for miss
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
                cpu_resp_hit   <= 0;
                mshr_valid     <= 0;
                cpu_req_ready  <= 1;
            end
            // State: new CPU request
            else if (cpu_req_valid && cpu_req_ready && !mshr_valid) begin
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
                end
                else begin
                    // Cache miss
                    cpu_req_ready <= 0;
                    mshr_valid  <= 1;
                    mshr_block  <= addr_block;
                    mshr_set    <= addr_set;
                    mshr_word   <= addr_word;
                    mshr_rw     <= cpu_req_rw;
                    mshr_size   <= cpu_req_size;
                    mshr_wdata  <= cpu_req_wdata;
                    mshr_victim <= base + lfsr[1:0];
                    idx = base + lfsr[1:0];
                    if (valid_array[idx] && dirty_array[idx]) begin
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
                        mem_req_valid   <= 1;
                        mem_req_rw      <= 0;
                        mem_req_addr    <= addr_block;
                        mshr_wb_pending <= 0;
                    end
                end
            end
        end
    end
endmodule
