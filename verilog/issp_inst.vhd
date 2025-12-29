	component issp is
		port (
			source     : out std_logic_vector(31 downto 0);                    -- source
			probe      : in  std_logic_vector(63 downto 0) := (others => 'X'); -- probe
			source_clk : in  std_logic                     := 'X'              -- clk
		);
	end component issp;

	u0 : component issp
		port map (
			source     => CONNECTED_TO_source,     --    sources.source
			probe      => CONNECTED_TO_probe,      --     probes.probe
			source_clk => CONNECTED_TO_source_clk  -- source_clk.clk
		);

