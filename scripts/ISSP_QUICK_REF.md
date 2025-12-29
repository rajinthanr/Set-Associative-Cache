# ISSP Quick Reference for Cache Debugging
# DE0-Nano - 4-Way Set-Associative Cache

## Quick Start

1. Program FPGA with Cache.sof
2. Open: Tools → System Debugging Tools → System Console
3. Run: `source scripts/issp_test.tcl`
4. Run: `issp_init` then `issp_open`
5. Run: `test_all` or individual commands

## Source Bits (32-bit Control → FPGA)

| Bits | Name | Description |
|------|------|-------------|
| 0 | debug_mode | 0=auto, 1=manual |
| 1 | req_valid | Request valid |
| 2 | req_rw | 0=read, 1=write |
| 4:3 | req_size | 00=byte, 01=half, 10=word |
| 24:5 | req_addr | 20-bit address |
| 25 | reset_cnt | Reset counters |
| 26 | single_step | Single step mode |
| 31:27 | probe_sel | Probe selection (0-5) |

## Probe Views (64-bit Monitoring ← FPGA)

| Sel | View | Contents |
|-----|------|----------|
| 0 | Status | hit_cnt, miss_cnt, total_req, state, flags |
| 1 | Request | addr, wdata, size, rw, valid, ready, hit |
| 2 | Response | rdata, tag, way info |
| 3 | Memory | mem interface signals |
| 4 | MSHR | mshr_valid, mshr_addr, states |
| 5 | Debug | debug counters |

## Common Commands

```tcl
# Setup
issp_init                    # Find ISSP service
issp_open                    # Open connection
issp_close                   # Close connection

# Mode Control
cache_auto_mode              # Auto test pattern
cache_manual_mode            # Manual control
cache_reset_counters         # Reset stats

# Operations
cache_read 0x00000           # Read address
cache_write 0x00000 0x1234   # Write data
cache_status                 # Show statistics
cache_mshr_status            # Show MSHR state
cache_select_probe 0         # Select probe view

# Tests
test_basic                   # Basic operations
test_hit_miss                # Hit/miss test
test_conflict                # 4-way conflict
test_mshr                    # Non-blocking test
test_all                     # Run all tests
```

## Manual Source Values

```tcl
# Auto mode, probe 0
issp_write 0x00000000

# Manual mode, probe 0
issp_write 0x00000001

# Manual read from 0x00100, word size
# addr=0x00100 → bits 24:5 = 0x00100 << 5 = 0x00002000
# size=word(10) → bits 4:3 = 0x10 = 0x10
# valid=1, rw=0, mode=1
issp_write 0x00002013

# Reset counters (pulse bit 25)
issp_write 0x02000001
issp_write 0x00000001

# Select probe 4 (MSHR)
# probe_sel=4 → bits 31:27 = 4 << 27 = 0x20000000
issp_write 0x20000001
```

## Address Mapping (1KB Cache)

- Cache Size: 1KB (8 sets × 4 ways × 32B lines)
- Block Size: 32 bytes (256 bits)
- Address bits: [19:10]=tag, [9:5]=set, [4:0]=offset

| Address | Set | Tag |
|---------|-----|-----|
| 0x00000 | 0 | 0x000 |
| 0x00020 | 1 | 0x000 |
| 0x00100 | 0 | 0x000 |
| 0x00200 | 0 | 0x001 |
| 0x00400 | 0 | 0x002 |

## LED Indicators

| LED | Meaning |
|-----|---------|
| 0 | Cache Hit |
| 1 | Cache Miss |
| 2 | Request Valid |
| 3 | Response Valid |
| 4 | Memory Busy |
| 5 | Debug Mode |
| 6 | MSHR Active |
| 7 | Heartbeat |

## Troubleshooting

**No ISSP service found:**
- Ensure FPGA is programmed
- Check issp_debug.v is in project
- Recompile with ISSP enabled

**No response from cache:**
- Check rst_n button not pressed
- Switch to manual mode first
- Verify clock is running (LED7 heartbeat)

**Always missing:**
- Normal for cold cache
- Access same block again for hit
- Check address mapping

**Hit rate low:**
- Check test addresses
- Verify set mapping
- May need more locality in access pattern
