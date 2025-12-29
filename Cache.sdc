#==============================================================================
# SDC Constraints File for 4-Way Set-Associative Cache
# Target: DE0-Nano (Cyclone IV EP4CE22F17C6)
# Clock: 50 MHz (20 ns period)
#==============================================================================

#------------------------------------------------------------------------------
# Clock Definition
#------------------------------------------------------------------------------
# DE0-Nano has a 50 MHz oscillator connected to PIN_R8
create_clock -name clk_50 -period 20.000 [get_ports clk_50]

# Derive PLL clocks if any PLLs are used (for future expansion)
derive_pll_clocks

#------------------------------------------------------------------------------
# Clock Uncertainty
#------------------------------------------------------------------------------
# Account for jitter and other clock uncertainties
# Typical value for Cyclone IV is ~0.1-0.2 ns
derive_clock_uncertainty

#------------------------------------------------------------------------------
# Input Constraints
#------------------------------------------------------------------------------
# Reset button - asynchronous, but constrain for analysis
# DE0-Nano KEY[0] directly drives rst_n (directly from external source)
set_input_delay -clock clk_50 -max 5.0 [get_ports rst_n]
set_input_delay -clock clk_50 -min 0.0 [get_ports rst_n]

# DIP switches - directly from external source (active high on DE0-Nano)
# sw[3:0] directly from external source
set_input_delay -clock clk_50 -max 5.0 [get_ports sw[*]]
set_input_delay -clock clk_50 -min 0.0 [get_ports sw[*]]

#------------------------------------------------------------------------------
# Output Constraints
#------------------------------------------------------------------------------
# LEDs - directly driving external LEDs
# Assuming 10ns max output delay for LED drivers
set_output_delay -clock clk_50 -max 10.0 [get_ports led[*]]
set_output_delay -clock clk_50 -min 0.0  [get_ports led[*]]

#------------------------------------------------------------------------------
# False Paths
#------------------------------------------------------------------------------
# Reset is asynchronous - cut timing paths from rst_n
set_false_path -from [get_ports rst_n]

# DIP switches are asynchronous inputs (manual, not synchronized to clock)
set_false_path -from [get_ports sw[*]]

# LEDs are outputs that don't need strict timing (visual indicators)
set_false_path -to [get_ports led[*]]

#------------------------------------------------------------------------------
# Multicycle Paths (if any)
#------------------------------------------------------------------------------
# Memory response takes multiple cycles (6 cycles delay simulated)
# If the design has registered memory interface, these may be needed:
# set_multicycle_path -setup 2 -from [get_registers *mem_resp*] -to [get_registers *]
# set_multicycle_path -hold 1 -from [get_registers *mem_resp*] -to [get_registers *]

#------------------------------------------------------------------------------
# ISSP (In-System Sources and Probes) Constraints
#------------------------------------------------------------------------------
# ISSP uses JTAG clock domain - these are automatically handled by Quartus
# But we can explicitly set false paths to/from ISSP signals if needed

# ISSP source signals come from JTAG domain (async to main clock)
# set_false_path -from [get_keepers *issp*source*]

# ISSP probe signals are sampled by JTAG domain (async from main clock)
# set_false_path -to [get_keepers *issp*probe*]

#------------------------------------------------------------------------------
# I/O Standards (informational - actual settings in QSF file)
#------------------------------------------------------------------------------
# All I/Os use 3.3V LVTTL standard per DE0-Nano requirements
# - clk_50: 3.3-V LVTTL input
# - rst_n: 3.3-V LVTTL input (directly from KEY[0] active-low)
# - sw[3:0]: 3.3-V LVTTL input (directly from DIP switches active-high)
# - led[7:0]: 3.3-V LVTTL output (directly to LEDs active-high)

#------------------------------------------------------------------------------
# Timing Exceptions for Cache Logic
#------------------------------------------------------------------------------
# The cache uses block RAM which may have specific timing requirements
# Quartus typically handles these automatically, but explicit constraints
# can help meet timing closure

# Cache data memory (block RAM) - inferred from cache module
# These are typically handled by Quartus automatically

#------------------------------------------------------------------------------
# Maximum Frequency Target
#------------------------------------------------------------------------------
# Target: 50 MHz operation with positive slack
# If timing fails, consider:
# 1. Pipelining critical paths
# 2. Reducing cache size
# 3. Using Quartus timing optimization settings

#------------------------------------------------------------------------------
# Design-Specific Timing Notes
#------------------------------------------------------------------------------
# Critical paths in this design:
# 1. Tag comparison logic (4-way parallel compare)
# 2. LFSR random replacement selection
# 3. MSHR lookup for non-blocking operation
# 4. Data multiplexer (4-way to 1)
#
# The 50 MHz clock (20 ns period) should be adequate for this design
# on Cyclone IV. If timing fails:
# - Check fitter report for critical paths
# - Consider registering the tag comparison output
# - Consider pipelining the MSHR lookup

#==============================================================================
# End of SDC File
#==============================================================================
