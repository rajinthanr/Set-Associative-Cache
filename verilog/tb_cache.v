`timescale 1ns/1ps
module tb_cache;
    reg         clk;
    reg         rst_n;
    reg         cpu_req_valid;
    reg         cpu_req_rw;
    reg [1:0]   cpu_req_size;
    reg [19:0]  cpu_req_addr;
    reg [31:0]  cpu_req_wdata;
    wire        cpu_req_ready;
    wire        cpu_resp_valid;
    wire        cpu_resp_hit;
    wire [31:0] cpu_resp_rdata;
    wire        mem_req_valid;
    wire        mem_req_rw;
    wire [14:0] mem_req_addr;
    wire [255:0] mem_req_wdata;
    reg         mem_resp_valid;
    reg [255:0] mem_resp_rdata;
    localparam MEM_LATENCY = 50;
    reg [255:0] mem_storage [0:32767];
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
        for (mi = 0; mi < 32768; mi = mi + 1)
            mem_storage[mi] = {16{mi[15:0]}};
    end
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
            end
            else if (mem_busy) begin
                if (mem_delay == 0) begin
                    mem_busy <= 0;
                    mem_resp_valid <= 1;
                    if (mem_pending_rw)
                        mem_storage[mem_pending_addr] <= mem_pending_wdata;
                    else
                        mem_resp_rdata <= mem_storage[mem_pending_addr];
                end
                else begin
                    mem_delay <= mem_delay - 1;
                end
            end
        end
    end
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
    initial clk = 0;
    always #5 clk = ~clk;
    integer cycle_count, hit_count, miss_count, req_start;
    initial cycle_count = 0;
    always @(posedge clk) cycle_count = cycle_count + 1;
    task cpu_access;
        input rw;
        input [1:0] size;
        input [19:0] addr;
        input [31:0] wdata;
        begin
            @(posedge clk);
            while (!cpu_req_ready) @(posedge clk);
            cpu_req_valid <= 1;
            cpu_req_rw    <= rw;
            cpu_req_size  <= size;
            cpu_req_addr  <= addr;
            cpu_req_wdata <= wdata;
            req_start = cycle_count;
            @(posedge clk);
            cpu_req_valid <= 0;
            while (!cpu_resp_valid) @(posedge clk);
            if (cpu_resp_hit)
                hit_count = hit_count + 1;
            else
                miss_count = miss_count + 1;
        end
    endtask
    integer i, block, addr;
    initial begin
        $display("=== 4-WAY SET-ASSOCIATIVE CACHE TEST ===");
        rst_n = 0;
        cpu_req_valid = 0;
        cpu_req_rw = 0;
        cpu_req_size = 2;
        cpu_req_addr = 0;
        cpu_req_wdata = 0;
        hit_count = 0;
        miss_count = 0;
        repeat(10) @(posedge clk);
        rst_n = 1;
        repeat(5) @(posedge clk);
        $display("TEST 1: Read Miss then Hit");
        cpu_access(0, 2, 20'h00100, 0);
        $display("  Read 0x00100: hit=%b lat=%0d", cpu_resp_hit, cycle_count-req_start);
        cpu_access(0, 2, 20'h00100, 0);
        $display("  Read 0x00100: hit=%b lat=%0d", cpu_resp_hit, cycle_count-req_start);
        $display("TEST 2: Write Hit");
        cpu_access(1, 2, 20'h00104, 32'hDEADBEEF);
        $display("  Write hit=%b", cpu_resp_hit);
        cpu_access(0, 2, 20'h00104, 0);
        $display("  Read data=0x%08x (expect DEADBEEF)", cpu_resp_rdata);
        $display("TEST 3: Conflict Misses (5 blocks to same set)");
        hit_count = 0;
        miss_count = 0;
        for (i = 0; i < 100; i = i + 1) begin
            block = i % 5;
            addr = block * 20'h4000;
            cpu_access(0, 2, addr, 0);
        end
        $display("  hits=%0d misses=%0d", hit_count, miss_count);
        $display("TEST 4: Write Miss");
        cpu_access(1, 2, 20'h80000, 32'hCAFEBABE);
        $display("  Write hit=%b", cpu_resp_hit);
        cpu_access(0, 2, 20'h80000, 0);
        $display("  Read data=0x%08x (expect CAFEBABE)", cpu_resp_rdata);
        $display("=== TESTS COMPLETE ===");
        #100;
        $finish;
    end
endmodule
