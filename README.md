# Set-Associative Cache (Verilog + Python simulator)

This repository contains:

- A Python cycle-ish simulator (`cache.py`, `mem.py`, `workload.py`) used for quick experiments (already added).
- Verilog RTL for a parameterized 4-way set-associative cache with random replacement and a simple MSHR-like non-blocking mechanism under `verilog/`:
  - `verilog/cache.v` - cache RTL (Verilog)
  - `verilog/memory_model.v` - BRAM-based 1MB memory model for simulation
  - `verilog/tb_cache.v` - simple testbench (runs random accesses and prints hit/miss)
  - `verilog/top.v` - basic synthesis top for DE0-Nano (demo harness)

Goals and assumptions:
- Main memory: 1 MB (ADDR_WIDTH=20)
- Cache: 64 KB total, 32 B lines, 4-way set associative
- Replacement: random (LFSR-based)
- Non-blocking: simple MSHR entries (configurable depth)

Simulation:
- Use any Verilog simulator (Icarus Verilog, ModelSim/Questa, or Verilator).
- Example with Icarus Verilog (install `iverilog` and `vvp`):

```bash
iverilog -g2005 -o tb sim -s tb_cache verilog/tb_cache.v verilog/cache.v verilog/memory_model.v
vvp a.out
```

Replace the command above for your simulator (ModelSim/Questa: compile and run `tb_cache`).

FPGA / DE0-Nano:
- `verilog/top.v` is a tiny demo top that streams addresses to the cache and drives LEDs with a status bit.
- The DE0-Nano has external SDRAM — for real hardware you should connect the cache request interface to a proper SDRAM controller rather than the behavioral `memory_model.v` used for simulation. Mapping a 1MB memory into on-chip BRAMs may not fit depending on the device resources.
- I can update the Quartus project (`Cache.qsf`) to add these files and create proper pin assignments if you want. Tell me which device/part string is in your Quartus project if you want me to wire pin assignments or integrate into the project.

Next steps I can do for you:
- Improve the Verilog cache (support writes, multiple waiters per MSHR, better replacement policy like pseudo-LRU).
- Create a ModelSim/Questa script and waveform configuration for debug.
- Integrate the RTL into your Quartus project and generate a .qsf update.
- Create a UART-based statistics reporter so you can read hit/miss counts over the DE0-Nano serial port.

Tell me which of the next steps you want me to do now.
# Set-Associative-Cache
Set Associative Cache with Random Replacement Policy with Non-Blocking
