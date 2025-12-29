# ISSP Debug Setup Guide for Cache on DE0-Nano

## Overview

This guide explains how to set up In-System Sources and Probes (ISSP) to debug the 4-way set-associative cache on the DE0-Nano FPGA.

## Step 1: Create ISSP IP in Quartus

1. Open your project in Quartus Prime
2. Go to **Tools → IP Catalog**
3. Search for **"In-System Sources and Probes"**
4. Double-click to create a new instance

### ISSP Configuration:
- **Instance ID**: `ISSP` (or `CACHE_DEBUG`)
- **Source Width**: `32` bits (input to FPGA)
- **Probe Width**: `64` bits (output from FPGA)
- **Source Initial Value**: `0x00000000`
- **Output File**: `issp_debug.v`

5. Click **Generate HDL** and **Finish**

## Step 2: Add Files to Project

Add these files to your Quartus project:
```
verilog/cache.v          # Main cache module
verilog/top_synth.v      # Top module with ISSP
ip/issp_debug.v          # Generated ISSP IP (module name: issp_debug)
```

**Important**: The generated module must be named `issp_debug` to match the instantiation in `top_synth.v`.

## Step 3: Compile and Program

1. **Analysis & Synthesis**: Processing → Start Analysis & Synthesis
2. **Fitter**: Processing → Start Fitter
3. **Assembler**: Processing → Start Assembler
4. **Program**: Tools → Programmer → Start

## Step 4: Open ISSP Tool

1. Go to **Tools → In-System Sources and Probes Editor**
2. The ISSP window will show your instance
3. Click **Connect** to establish JTAG connection

## ISSP Control Bits (Source - 32 bits)

| Bit(s) | Name | Description |
|--------|------|-------------|
| 0 | debug_mode | 0=Auto mode, 1=Manual mode |
| 1 | debug_req_valid | Trigger manual request |
| 2 | debug_req_rw | 0=Read, 1=Write |
| 4:3 | debug_req_size | 00=Byte, 01=Half, 10=Word |
| 24:5 | debug_req_addr | 20-bit address for manual request |
| 25 | debug_reset_cnt | Pulse to reset hit/miss counters |
| 26 | debug_single_step | Enable single-step mode |
| 31:27 | debug_probe_sel | Select probe data (0-5) |

## ISSP Probe Data (Probe - 64 bits)

### Probe Select 0 (Default): Status Overview
| Bits | Data |
|------|------|
| 63:48 | Hit count (16 bits) |
| 47:32 | Miss count (16 bits) |
| 31:0 | Last response data |

### Probe Select 1: CPU Request
| Bits | Data |
|------|------|
| 59:40 | Request address |
| 31:0 | Write data |

### Probe Select 2: CPU Response
| Bits | Data |
|------|------|
| 47:32 | Total requests |
| 31:0 | Response data |

### Probe Select 3: Memory Interface
| Bits | Data |
|------|------|
| 62 | Memory R/W |
| 61 | Memory request valid |
| 60 | Memory busy |
| 59:54 | Memory delay counter |
| 47:33 | Memory address |
| 31:0 | Response data |

### Probe Select 4: Cache Status
| Bits | Data |
|------|------|
| 55 | cpu_req_ready |
| 54 | cpu_resp_valid |
| 53 | cpu_resp_hit |
| 52 | mem_req_valid |
| 51 | mem_req_rw |
| 50 | mem_busy |
| 47:32 | Hit count |
| 31:0 | Miss count |

### Probe Select 5: Hit Rate Helper
| Bits | Data |
|------|------|
| 63:48 | Total requests |
| 47:32 | Hit count |
| 31:16 | Miss count |

## Debug Procedures

### Test 1: Manual Cache Access

1. Set source to `0x00000001` (debug_mode = 1)
2. Set address: bits [24:5] = target address (e.g., 0x100 → source = 0x00002001)
3. Pulse request: set bit 1 high, then low
4. Observe probe for hit/miss and data

**Example - Read address 0x00100:**
```
Source = 0x00002001  (debug_mode=1, addr=0x100>>5=0x8, shifted to bits[24:5])
Wait...
Source = 0x00002003  (set req_valid=1)
Source = 0x00002001  (clear req_valid)
Read Probe[63:48] for hit count, Probe[31:0] for data
```

### Test 2: Check Hit Rate

1. Set probe_sel = 5 (source bits [31:27] = 00101)
2. Source = `0x28000000` (probe_sel=5, auto mode)
3. Let cache run for a while
4. Read: Probe[63:48]/Probe[47:32] = hit rate

### Test 3: Reset Counters

1. Pulse bit 25: `source = 0x02000000`
2. Then clear: `source = 0x00000000`

### Test 4: Single Step Mode

1. Set source = `0x04000000` (single_step=1, auto mode)
2. Each pulse of bit 1 triggers one request
3. Observe cache behavior step by step

## LED Indicators

| LED | Function |
|-----|----------|
| LED0 | Cache hit (pulse) |
| LED1 | Response valid (pulse) |
| LED2 | Cache ready |
| LED3 | Memory activity |
| LED4 | Debug mode active |
| LED7:5 | Hit/miss count (SW3 selects) |

## Switch Functions

| Switch | Function |
|--------|----------|
| SW0 | Read (0) / Write (1) in auto mode |
| SW2:1 | Address pattern (00=seq, 01=line, 10=set, 11=conflict) |
| SW3 | LED display (0=hits, 1=misses) |

## Troubleshooting

### ISSP Not Connecting
- Check JTAG cable connection
- Verify correct .sof is programmed
- Try Tools → Programmer → Auto Detect

### No Response from Cache
- Check rst_n signal (active low)
- Verify clock is running (LED2 should be on)
- Try debug_reset_cnt pulse

### Unexpected Miss Rate
- Check address pattern with probe_sel=1
- Verify set mapping (bits [7:5] = set index)
- Watch for conflict misses with probe_sel=3
