// Synthesis top for 1KB cache with minimal I/O
module top_synth (
    input  wire        clk_50,
    input  wire        rst_n,
    input  wire [3:0]  sw,
    output wire [7:0]  led
);
    // CPU interface signals
    reg        cpu_req_valid;
    reg        cpu_req_rw;
    reg [1:0]  cpu_req_size;
    reg [19:0] cpu_req_addr;
    reg [31:0] cpu_req_wdata;
    wire       cpu_req_ready;
    wire       cpu_resp_valid;
    wire       cpu_resp_hit;
    wire [31:0] cpu_resp_rdata;

    // Memory interface (internal)
    wire        mem_req_valid;
    wire        mem_req_rw;
    wire [14:0] mem_req_addr;
    wire [255:0] mem_req_wdata;
    reg         mem_resp_valid;
    reg [255:0] mem_resp_rdata;

    // Internal state
    reg [5:0] mem_delay;
    reg mem_busy;
    reg [19:0] cnt;
    reg [7:0] hit_cnt;
    reg [7:0] miss_cnt;

    // Simple address generator
    always @(posedge clk_50 or negedge rst_n) begin
        if (!rst_n) begin
            cnt           <= 0;
            cpu_req_valid <= 0;
            cpu_req_rw    <= 0;
            cpu_req_size  <= 2;
            cpu_req_addr  <= 0;
            cpu_req_wdata <= 0;
            hit_cnt       <= 0;
            miss_cnt      <= 0;
        end
        else begin
            cnt <= cnt + 1;
            cpu_req_valid <= 0;
            // Generate request every 256 cycles
            if (cnt[7:0] == 0 && cpu_req_ready) begin
                cpu_req_valid <= 1;
                cpu_req_rw    <= sw[0];
                // Address pattern based on switches
                case (sw[2:1])
                    2'b00: cpu_req_addr <= {12'd0, cnt[12:5]}; // Sequential
                    2'b01: cpu_req_addr <= {12'd0, cnt[7:5], cnt[12:8]}; // Strided
                    2'b10: cpu_req_addr <= {12'd0, cnt[12:5]} ^ 20'h55; // XOR pattern
                    2'b11: cpu_req_addr <= cpu_req_addr + 256; // Big stride (conflicts)
                endcase
                cpu_req_wdata <= {cpu_req_addr[11:0], cnt[19:0]};
            end
            // Track hits/misses
            if (cpu_resp_valid) begin
                if (cpu_resp_hit)
                    hit_cnt <= hit_cnt + 1;
                else
                    miss_cnt <= miss_cnt + 1;
            end
        end
    end

    // Simple memory stub with latency
    always @(posedge clk_50 or negedge rst_n) begin
        if (!rst_n) begin
            mem_resp_valid <= 0;
            mem_resp_rdata <= 0;
            mem_delay <= 0;
            mem_busy <= 0;
        end
        else begin
            mem_resp_valid <= 0;
            if (mem_req_valid && !mem_busy) begin
                mem_busy <= 1;
                mem_delay <= 20; // 20 cycle latency
            end
            else if (mem_busy) begin
                if (mem_delay == 0) begin
                    mem_busy <= 0;
                    mem_resp_valid <= 1;
                    // Return address-based pattern
                    mem_resp_rdata <= {8{mem_req_addr, 17'd0}};
                end
                else begin
                    mem_delay <= mem_delay - 1;
                end
            end
        end
    end

    // Cache instance
    cache cache_inst (
        .clk(clk_50),
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

    // LED outputs - show cache status
    assign led[0] = cpu_resp_hit;       // Hit indicator
    assign led[1] = cpu_resp_valid;     // Response valid
    assign led[2] = cpu_req_ready;      // Ready for request
    assign led[3] = mem_req_valid;      // Memory request active
    assign led[7:4] = sw[3] ? miss_cnt[3:0] : hit_cnt[3:0]; // Hit or miss count
endmodule
