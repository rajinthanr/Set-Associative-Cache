//==============================================================================
// ISSP Debug IP - Placeholder/Template
// Generate the actual IP using Quartus IP Catalog:
//   Tools -> IP Catalog -> "In-System Sources and Probes"
//
// Configuration:
//   Instance ID: ISSP
//   Source Width: 32 bits
//   Probe Width: 64 bits
//==============================================================================

// This is a simulation stub - replace with generated IP for synthesis
module issp_debug (
    input  wire [63:0] probe,
    output wire [31:0] source
);

`ifdef SIMULATION
    // For simulation: allow external control
    reg [31:0] source_reg;
    assign source = source_reg;
    
    initial begin
        source_reg = 32'h00000000;
    end
    
    // Task to set source from testbench
    task set_source;
        input [31:0] value;
        begin
            source_reg = value;
        end
    endtask
    
    // Monitor probe values
    always @(probe) begin
        $display("[ISSP] Probe = 0x%016x", probe);
    end
`else
    // For synthesis: Quartus will replace this with actual IP
    // Generate using: Tools -> IP Catalog -> In-System Sources and Probes
    
    assign source = 32'h00000000;  // Default - will be overridden by IP
    
    // Synthesis directive to prevent optimization
    (* keep = 1 *) wire [63:0] probe_keep = probe;
`endif

endmodule
