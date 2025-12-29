#==============================================================================
# Tcl Script to Create ISSP (In-System Sources and Probes) IP for Cache Debug
# Run in Quartus: Tools -> Tcl Scripts -> Run this script
# Or from command line: quartus_sh -t create_issp.tcl
#==============================================================================

# Set project path (adjust if needed)
set project_path [pwd]
set ip_name "issp_debug"

puts "Creating ISSP IP: $ip_name"
puts "Project path: $project_path"

# Create the IP variation file
set qsys_content {
<?xml version="1.0" encoding="UTF-8"?>
<ip>
 <presetLibrary/>
 <rootComponent name="issp_debug" displayName="issp_debug" version="1.0" description="" tags="" categories=""/>
 <tag2 key="COMPONENT_EDITABLE" value="true"/>
 <tag2 key="COMPONENT_TYPE" value="altera_in_system_sources_probes"/>
 <parameter name="gui_use_auto_index" value="true"/>
 <parameter name="sld_instance_index" value="0"/>
 <parameter name="instance_id" value="ISSP"/>
 <parameter name="SLD_NODE_INFO" value=""/>
 <parameter name="sld_ir_width" value=""/>
 <parameter name="component_type_probe" value="Output"/>
 <parameter name="component_type_source" value="Input"/>
 <parameter name="probe_width" value="64"/>
 <parameter name="source_width" value="32"/>
 <parameter name="source_initial_value" value="0"/>
 <parameter name="create_source_clock" value="false"/>
 <parameter name="create_source_clock_enable" value="false"/>
</ip>
}

# Write IP file
set ip_file [open "$project_path/ip/$ip_name.ip" w]
puts $ip_file $qsys_content
close $ip_file

puts "ISSP IP file created: ip/$ip_name.ip"
puts ""
puts "Next steps:"
puts "1. In Quartus: Tools -> IP Catalog"
puts "2. Search for 'In-System Sources and Probes'"
puts "3. Double-click to configure or use the generated IP"
puts "4. Add issp_debug.v to your project"
