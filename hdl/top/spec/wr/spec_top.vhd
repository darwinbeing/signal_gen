-------------------------------------------------------------------------------
-- Title      : Fine Delay FMC SPEC (Simple PCI-Express FMC Carrier) top level
-- Project    : Fine Delay FMC (fmc-delay-1ns-4cha)
-------------------------------------------------------------------------------
-- File       : spec_top.vhd
-- Author     : Tomasz Wlostowski
-- Company    : CERN
-- Created    : 2011-08-24
-- Last update: 2014-01-15
-- Platform   : FPGA-generic
-- Standard   : VHDL'93
-------------------------------------------------------------------------------
-- Description: Top level for the SPEC 1.1 (and later releases) cards with
-- one Fine Delay FMC.
-- Supports:
-- - SDB enumeration (SDB descriptor at 0x00000)
-- - White Rabbit and Etherbone
-- - Interrupts (via WR VIC)
-------------------------------------------------------------------------------
--
-- Copyright (c) 2011 - 2012 CERN / BE-CO-HT
--
-- This source file is free software; you can redistribute it   
-- and/or modify it under the terms of the GNU Lesser General   
-- Public License as published by the Free Software Foundation; 
-- either version 2.1 of the License, or (at your option) any   
-- later version.                                               
--
-- This source is distributed in the hope that it will be       
-- useful, but WITHOUT ANY WARRANTY; without even the implied   
-- warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR      
-- PURPOSE.  See the GNU Lesser General Public License for more 
-- details.                                                     
--
-- You should have received a copy of the GNU Lesser General    
-- Public License along with this source; if not, download it   
-- from http://www.gnu.org/licenses/lgpl-2.1.html
--
-------------------------------------------------------------------------------
library IEEE;
use IEEE.STD_LOGIC_1164.all;
use IEEE.NUMERIC_STD.all;

use work.gn4124_core_pkg.all;
use work.gencores_pkg.all;
use work.wrcore_pkg.all;
use work.wr_fabric_pkg.all;
use work.wishbone_pkg.all;
use work.fine_delay_pkg.all;
use work.etherbone_pkg.all;
use work.wr_xilinx_pkg.all;
use work.genram_pkg.all;

use work.synthesis_descriptor.all;

library UNISIM;
use UNISIM.vcomponents.all;

entity spec_top is
  generic
    (
      g_simulation : integer := 0
      );
  port
    (
      -------------------------------------------------------------------------
      -- Standard SPEC ports (Gennum bridge, LEDS, Etc. Do not modify
      -------------------------------------------------------------------------

      clk_20m_vcxo_i : in std_logic;    -- 20MHz VCXO clock

      clk_125m_pllref_p_i : in std_logic;  -- 125 MHz PLL reference
      clk_125m_pllref_n_i : in std_logic;

      clk_125m_gtp_n_i : in std_logic;  -- 125 MHz GTP reference
      clk_125m_gtp_p_i : in std_logic;

      l_rst_n : in std_logic;           -- reset from gn4124 (rstout18_n)

      -- general purpose interface
      gpio       : inout std_logic_vector(1 downto 0);  -- gpio[0] -> gn4124 gpio8
                                        -- gpio[1] -> gn4124 gpio9
      -- pcie to local [inbound data] - rx
      p2l_rdy    : out   std_logic;     -- rx buffer full flag
      p2l_clkn   : in    std_logic;     -- receiver source synchronous clock-
      p2l_clkp   : in    std_logic;     -- receiver source synchronous clock+
      p2l_data   : in    std_logic_vector(15 downto 0);  -- parallel receive data
      p2l_dframe : in    std_logic;     -- receive frame
      p2l_valid  : in    std_logic;     -- receive data valid

      -- inbound buffer request/status
      p_wr_req : in  std_logic_vector(1 downto 0);  -- pcie write request
      p_wr_rdy : out std_logic_vector(1 downto 0);  -- pcie write ready
      rx_error : out std_logic;                     -- receive error

      -- local to parallel [outbound data] - tx
      l2p_data   : out std_logic_vector(15 downto 0);  -- parallel transmit data
      l2p_dframe : out std_logic;       -- transmit data frame
      l2p_valid  : out std_logic;       -- transmit data valid
      l2p_clkn   : out std_logic;  -- transmitter source synchronous clock-
      l2p_clkp   : out std_logic;  -- transmitter source synchronous clock+
      l2p_edb    : out std_logic;       -- packet termination and discard

      -- outbound buffer status
      l2p_rdy    : in std_logic;        -- tx buffer full flag
      l_wr_rdy   : in std_logic_vector(1 downto 0);  -- local-to-pcie write
      p_rd_d_rdy : in std_logic_vector(1 downto 0);  -- pcie-to-local read response data ready
      tx_error   : in std_logic;        -- transmit error
      vc_rdy     : in std_logic_vector(1 downto 0);  -- channel ready

      -- font panel leds
      led_red   : out std_logic;
      led_green : out std_logic;

      -------------------------------------------------------------------------
      -- PLL VCXO DAC Drive
      -------------------------------------------------------------------------

      dac_sclk_o  : out std_logic;
      dac_din_o   : out std_logic;
      --dac_clr_n_o : out std_logic;
      dac_cs1_n_o : out std_logic;
      dac_cs2_n_o : out std_logic;

      button1_i : in std_logic := '1';
      button2_i : in std_logic := '1';

      fmc_scl_b : inout std_logic := '1';
      fmc_sda_b : inout std_logic := '1';

      carrier_onewire_b : inout std_logic := '1';
      fmc_prsnt_m2c_l_i : in    std_logic;

      -------------------------------------------------------------------------
      -- SFP pins
      -------------------------------------------------------------------------

      sfp_txp_o : out std_logic;
      sfp_txn_o : out std_logic;

      sfp_rxp_i : in std_logic := '0';
      sfp_rxn_i : in std_logic := '1';

      sfp_mod_def0_b    : in    std_logic;  -- detect pin
      sfp_mod_def1_b    : inout std_logic;  -- scl
      sfp_mod_def2_b    : inout std_logic;  -- sda
      sfp_rate_select_b : inout std_logic := '0';
      sfp_tx_fault_i    : in    std_logic := '0';
      sfp_tx_disable_o  : out   std_logic;
      sfp_los_i         : in    std_logic := '0';

      -------------------------------------------------------------------------
      -- Fine Delay Pins
      -------------------------------------------------------------------------

      fd_tdc_start_p_i : in std_logic;
      fd_tdc_start_n_i : in std_logic;

      fd_clk_ref_p_i : in std_logic;
      fd_clk_ref_n_i : in std_logic;

      fd_trig_a_i         : in    std_logic;
      fd_tdc_cal_pulse_o  : out   std_logic;
      fd_tdc_d_b          : inout std_logic_vector(27 downto 0);
      fd_tdc_emptyf_i     : in    std_logic;
      fd_tdc_alutrigger_o : out   std_logic;
      fd_tdc_wr_n_o       : out   std_logic;
      fd_tdc_rd_n_o       : out   std_logic;
      fd_tdc_oe_n_o       : out   std_logic;
      fd_led_trig_o       : out   std_logic;
      fd_tdc_start_dis_o  : out   std_logic;
      fd_tdc_stop_dis_o   : out   std_logic;
      fd_spi_cs_dac_n_o   : out   std_logic;
      fd_spi_cs_pll_n_o   : out   std_logic;
      fd_spi_cs_gpio_n_o  : out   std_logic;
      fd_spi_sclk_o       : out   std_logic;
      fd_spi_mosi_o       : out   std_logic;
      fd_spi_miso_i       : in    std_logic;
      fd_delay_len_o      : out   std_logic_vector(3 downto 0);
      fd_delay_val_o      : out   std_logic_vector(9 downto 0);
      fd_delay_pulse_o    : out   std_logic_vector(3 downto 0);

      fd_dmtd_clk_o    : out std_logic;
      fd_dmtd_fb_in_i  : in  std_logic;
      fd_dmtd_fb_out_i : in  std_logic;

      fd_pll_status_i : in  std_logic;
      fd_ext_rst_n_o  : out std_logic;

      fd_onewire_b : inout std_logic;

      -----------------------------------------
      -- UART
      -----------------------------------------

      uart_rxd_i : in  std_logic;
      uart_txd_o : out std_logic
      );

end spec_top;

architecture rtl of spec_top is

--component chipscope_ila
--    port (
--      CONTROL : inout std_logic_vector(35 downto 0);
--      CLK     : in    std_logic;
--      TRIG0   : in    std_logic_vector(31 downto 0);
--      TRIG1   : in    std_logic_vector(31 downto 0);
--      TRIG2   : in    std_logic_vector(31 downto 0);
--      TRIG3   : in    std_logic_vector(31 downto 0));
--  end component;
--
--  component chipscope_icon
--    port (
--      CONTROL0 : inout std_logic_vector (35 downto 0));
--  end component;

--  signal CONTROL : std_logic_vector(35 downto 0);
--  signal CLK     : std_logic;
--  signal TRIG0   : std_logic_vector(31 downto 0);
--  signal TRIG1   : std_logic_vector(31 downto 0);
--  signal TRIG2   : std_logic_vector(31 downto 0);
--  signal TRIG3   : std_logic_vector(31 downto 0);


  component spec_serial_dac_arb
    generic(
      g_invert_sclk    : boolean;
      g_num_extra_bits : integer);
    port (
      clk_i       : in  std_logic;
      rst_n_i     : in  std_logic;
      val1_i      : in  std_logic_vector(15 downto 0);
      load1_i     : in  std_logic;
      val2_i      : in  std_logic_vector(15 downto 0);
      load2_i     : in  std_logic;
      dac_cs_n_o  : out std_logic_vector(1 downto 0);
      dac_clr_n_o : out std_logic;
      dac_sclk_o  : out std_logic;
      dac_din_o   : out std_logic);
  end component;

  component fd_ddr_pll
    port (
      RST       : in  std_logic;
      LOCKED    : out std_logic;
      CLK_IN1_P : in  std_logic;
      CLK_IN1_N : in  std_logic;
      CLK_OUT1  : out std_logic;
      CLK_OUT2  : out std_logic);
  end component;

  component spec_reset_gen
    port (
      clk_sys_i        : in  std_logic;
      rst_pcie_n_a_i   : in  std_logic;
      rst_button_n_a_i : in  std_logic;
      rst_n_o          : out std_logic);
  end component;

  function f_resize_slv (x : std_logic_vector; len : integer) return std_logic_vector is
    variable tmp : std_logic_vector(len-1 downto 0);
  begin
    if(len > x'length) then
      tmp(x'length-1 downto 0)   := x;
      tmp(len-1 downto x'length) := (others => '0');
    elsif(len < x'length) then
      tmp := x(len-1 downto 0);
    else
      tmp := x;
    end if;
    return tmp;
  end f_resize_slv;

  function f_int2bool (x : integer) return boolean is
  begin
    if(x = 0) then
      return false;
    else
      return true;
    end if;
  end f_int2bool;

  constant c_NUM_WB_MASTERS : integer := 5;
  constant c_NUM_WB_SLAVES  : integer := 4;

  constant c_MASTER_GENNUM    : integer := 0;
  constant c_MASTER_ETHERBONE : integer := 1;
  constant c_MASTER_LM32      : integer := 2; ---has two

  constant c_SLAVE_FD       : integer := 0;
  constant c_SLAVE_WRCORE   : integer := 1;
  constant c_SLAVE_VIC      : integer := 2;
  constant c_SLAVE_DPRAM	 : integer := 3;
  constant c_SLAVE_UART		 : integer := 4;
  constant c_DESC_SYNTHESIS : integer := 5;
  constant c_DESC_REPO_URL  : integer := 6;

  constant c_WRCORE_BRIDGE_SDB : t_sdb_bridge := f_xwb_bridge_manual_sdb(x"0003ffff", x"00030000");
	 
  constant init_lm32_addr : t_wishbone_address := x"00040000";

  constant g_dpram_size				: integer	:= 114688/4;  --in 32-bit words
  constant c_mnic_memsize_log2 	: integer	:= f_log2_size(g_dpram_size);
  
  constant c_wrc_periph_uart_sdb : t_sdb_device := (
    abi_class     => x"0000",              -- undocumented device
    abi_ver_major => x"01",
    abi_ver_minor => x"01",
    wbd_endian    => c_sdb_endian_big,
    wbd_width     => x"7",                 -- 8/16/32-bit port granularity
    sdb_component => (
      addr_first  => x"0000000000000000",
      addr_last   => x"00000000000000ff",
      product     => (
        vendor_id => x"000000000000CE42",  -- CERN
        device_id => x"dead0fee",
        version   => x"00000001",
        date      => x"20120305",
        name      => "UART               "))); 

  constant c_INTERCONNECT_LAYOUT : t_sdb_record_array(c_NUM_WB_MASTERS+1 downto 0) :=
    (c_SLAVE_WRCORE   => f_sdb_embed_bridge(c_WRCORE_BRIDGE_SDB, x"000c0000"),
     c_SLAVE_FD       => f_sdb_embed_device(c_FD_SDB_DEVICE, x"00080000"),
     c_SLAVE_VIC      => f_sdb_embed_device(c_xwb_vic_sdb, x"00090000"),
	  c_SLAVE_DPRAM	 => f_sdb_embed_device(f_xwb_dpram(g_dpram_size), init_lm32_addr),
	  c_SLAVE_UART	    => f_sdb_embed_device(c_wrc_periph_uart_sdb, x"00060000"), -- UART
     c_DESC_SYNTHESIS => f_sdb_embed_synthesis(c_sdb_synthesis_info),
     c_DESC_REPO_URL  => f_sdb_embed_repo_url(c_sdb_repo_url));  

  constant c_SDB_ADDRESS : t_wishbone_address := x"00000000";

  constant c_VIC_VECTOR_TABLE : t_wishbone_address_array(0 to 0) :=
    (0 => x"00080000");
  
  signal uart_dummy_i 	: std_logic;
  signal uart_dummy_o 	: std_logic;
  signal dbg_uart_rxd_i	: std_logic;
  signal dbg_uart_txd_o	: std_logic;
  signal wrpc_uart_rxd_i: std_logic;
  signal wrpc_uart_txd_o: std_logic;
  signal sg_uart_rxd_i	: std_logic;
  signal sg_uart_txd_o	: std_logic;

  signal pllout_clk_sys       : std_logic;
  signal pllout_clk_dmtd      : std_logic;
  signal pllout_clk_fb_pllref : std_logic;
  signal pllout_clk_fb_dmtd   : std_logic;

  signal clk_20m_vcxo_buf : std_logic;
  signal clk_125m_pllref  : std_logic;
  signal clk_125m_gtp     : std_logic;
  signal clk_sys          : std_logic;
  signal clk_dmtd         : std_logic;

  signal dac_hpll_load_p1 : std_logic;
  signal dac_dpll_load_p1 : std_logic;
  signal dac_hpll_data    : std_logic_vector(15 downto 0);
  signal dac_dpll_data    : std_logic_vector(15 downto 0);

  signal phy_tx_data      : std_logic_vector(7 downto 0);
  signal phy_tx_k         : std_logic;
  signal phy_tx_disparity : std_logic;
  signal phy_tx_enc_err   : std_logic;
  signal phy_rx_data      : std_logic_vector(7 downto 0);
  signal phy_rx_rbclk     : std_logic;
  signal phy_rx_k         : std_logic;
  signal phy_rx_enc_err   : std_logic;
  signal phy_rx_bitslide  : std_logic_vector(3 downto 0);
  signal phy_rst          : std_logic;
  signal phy_loopen       : std_logic;

  signal local_reset_n : std_logic;

  signal cnx_master_out : t_wishbone_master_out_array(c_NUM_WB_MASTERS-1 downto 0);
  signal cnx_master_in  : t_wishbone_master_in_array(c_NUM_WB_MASTERS-1 downto 0);

  signal cnx_slave_out : t_wishbone_slave_out_array(c_NUM_WB_SLAVES-1 downto 0);
  signal cnx_slave_in  : t_wishbone_slave_in_array(c_NUM_WB_SLAVES-1 downto 0);

  signal dcm_clk_ref_0, dcm_clk_ref_180 : std_logic;

  signal fd_tdc_start              : std_logic;
  signal tdc_data_out, tdc_data_in : std_logic_vector(27 downto 0);
  signal tdc_data_oe               : std_logic;

  signal tm_link_up         : std_logic;
  signal tm_utc             : std_logic_vector(39 downto 0);
  signal tm_cycles          : std_logic_vector(27 downto 0);
  signal tm_time_valid      : std_logic;
  signal tm_clk_aux_lock_en : std_logic;
  signal tm_clk_aux_locked  : std_logic;
  signal tm_dac_value       : std_logic_vector(23 downto 0);
  signal tm_dac_wr          : std_logic;

  signal ddr_pll_reset                 : std_logic;
  signal ddr_pll_locked, fd_pll_status : std_logic;

  signal wrc_scl_out, wrc_scl_in, wrc_sda_out, wrc_sda_in : std_logic;
  signal fd_scl_out, fd_scl_in, fd_sda_out, fd_sda_in     : std_logic;
  signal sfp_scl_out, sfp_scl_in, sfp_sda_out, sfp_sda_in : std_logic;
  signal wrc_owr_en, wrc_owr_in                           : std_logic_vector(1 downto 0);
  signal fd_owr_en, fd_owr_in                             : std_logic;

  signal fd_irq    : std_logic;
  signal gn_wb_adr : std_logic_vector(31 downto 0);

  signal pps : std_logic;

  signal etherbone_rst_n   : std_logic;
  signal etherbone_src_out : t_wrf_source_out;
  signal etherbone_src_in  : t_wrf_source_in;
  signal etherbone_snk_out : t_wrf_sink_out;
  signal etherbone_snk_in  : t_wrf_sink_in;
  signal etherbone_cfg_in  : t_wishbone_slave_in;
  signal etherbone_cfg_out : t_wishbone_slave_out;

  signal vic_irqs : std_logic_vector(31 downto 0);
  
   
  signal dpram_wbb_i : t_wishbone_slave_in;
  signal dpram_wbb_o : t_wishbone_slave_out;
  
  signal periph_slave_i : t_wishbone_slave_in_array(0 to 2);
  signal periph_slave_o : t_wishbone_slave_out_array(0 to 2);
  signal periph_dummy	: std_logic_vector (9 downto 0);
  signal wrpc_dummy		: std_logic_vector (2 downto 0);
  signal forced_lm32_reset_n : std_logic := '0';
  signal state_control : unsigned (11 downto 0) := x"fff";

  attribute buffer_type                    : string;  --" {bufgdll | ibufg | bufgp | ibuf | bufr | none}";
  attribute buffer_type of clk_125m_pllref : signal is "BUFG";

begin

LED_RED <= forced_lm32_reset_n;

sg_uart_rxd_i <= uart_rxd_i;
uart_txd_o <= sg_uart_txd_o;

managed_reset : process (clk_sys)
	variable use_dbg_uart: std_logic := '1';
	begin 
		if (rising_edge(clk_sys)) then
			if (BUTTON2_I = '0') then
				state_control <= state_control + 1;
			else
				if ((state_control /= x"000") and (state_control <= x"005")) then
					state_control <= x"000";
					forced_lm32_reset_n <= not forced_lm32_reset_n;
				elsif (state_control >= x"005") then
					state_control <= x"000";
					case use_dbg_uart is
						when use_dbg_uart => uart_txd_o <= dbg_uart_txd_o; dbg_uart_rxd_i <= uart_rxd_i;
						when others => uart_txd_o <= wrpc_uart_txd_o; wrpc_uart_rxd_i <= uart_rxd_i;
						end case; 
					use_dbg_uart := '0';
				end if;
			end if;
		end if;
	end process;
	
--trig0(0)				<= clk_sys;
--trig0(1) 			<= BUTTON2_I;
--trig0(4 downto 2) <= state_control; 
--trig0(5)				<= forced_lm32_reset_n;
-- -----------------------------------------------------------------------------
--  -- WB Peripherials
-- -----------------------------------------------------------------------------
  PERIPH : wrc_periph
    generic map(
      g_phys_uart    => true,
      g_virtual_uart => false,
      g_mem_words    => 0)
    port map(
      clk_sys_i   => clk_sys,
      rst_n_i     => local_reset_n,
      rst_net_n_o => open,
      rst_wrc_n_o => open,

      led_red_o   => open,              --led_red_o,
      led_green_o => open,              --led_green_o,
      scl_o       => open,
      scl_i       => periph_dummy(0),
      sda_o       => open,
      sda_i       => periph_dummy(1),
      sfp_scl_o   => open,
      sfp_scl_i   => periph_dummy(2),
      sfp_sda_o   => periph_dummy(3),
      sfp_sda_i   => periph_dummy(4),
      sfp_det_i   => periph_dummy(5),
      memsize_i   => "0000",
      btn1_i      => periph_dummy(6),
      btn2_i      => periph_dummy(7),

      slave_i => periph_slave_i,
      slave_o => periph_slave_o,

      uart_rxd_i => dbg_uart_rxd_i,
      uart_txd_o => dbg_uart_txd_o,

      owr_pwren_o => open,
      owr_en_o    => open,
      owr_i       => periph_dummy(9 downto 8)
      );
--  
  periph_slave_i(1) <= cnx_master_out(c_SLAVE_UART);
  cnx_master_in(c_SLAVE_UART) <= periph_slave_o(1);
--  trig2 <= cnx_master_out(c_SLAVE_UART).adr;
--  trig3 <=  cnx_master_in(c_SLAVE_UART).dat;

  --------------------------------------
  -- UART
  --------------------------------------
--  UART : xwb_simple_uart
--    generic map(
--      g_with_virtual_uart   => true,
--      g_with_physical_uart  => false,
--      g_interface_mode      => PIPELINED,
--      g_address_granularity => BYTE
--      )
--    port map(
--      clk_sys_i => clk_sys,
--      rst_n_i   => local_reset_n,
--
--      -- Wishbone
--      slave_i => cnx_master_out(c_SLAVE_UART),
--      slave_o => cnx_master_in(c_SLAVE_UART),
--      desc_o  => open,
--
--      uart_rxd_i => uart_rxd_i,
--      uart_txd_o => uart_txd_o
--      );

 U_Reset_Generator : spec_reset_gen
    port map (
      clk_sys_i        => clk_sys,
      rst_pcie_n_a_i   => l_rst_n,
      rst_button_n_a_i => button1_i,
      rst_n_o          => local_reset_n);

  U_Buf_CLK_PLL : IBUFGDS
    generic map (
      DIFF_TERM    => true,
      IBUF_LOW_PWR => true  -- Low power (TRUE) vs. performance (FALSE) setting for referenced
      )
    port map (
      O  => clk_125m_pllref,            -- Buffer output
      I  => clk_125m_pllref_p_i,  -- Diff_p buffer input (connect directly to top-level port)
      IB => clk_125m_pllref_n_i  -- Diff_n buffer input (connect directly to top-level port)
      );

  U_Buf_CLK_GTP : IBUFDS
    generic map (
      DIFF_TERM    => true,
      IBUF_LOW_PWR => false  -- Low power (TRUE) vs. performance (FALSE) setting for referenced
      )
    port map (
      O  => clk_125m_gtp,
      I  => clk_125m_gtp_p_i,
      IB => clk_125m_gtp_n_i
      );


  cmp_sys_clk_pll : PLL_BASE
    generic map (
      BANDWIDTH          => "OPTIMIZED",
      CLK_FEEDBACK       => "CLKFBOUT",
      COMPENSATION       => "INTERNAL",
      DIVCLK_DIVIDE      => 1,
      CLKFBOUT_MULT      => 8,
      CLKFBOUT_PHASE     => 0.000,
      CLKOUT0_DIVIDE     => 16,         -- 62.5 MHz
      CLKOUT0_PHASE      => 0.000,
      CLKOUT0_DUTY_CYCLE => 0.500,
      CLKOUT1_DIVIDE     => 16,         -- 125 MHz
      CLKOUT1_PHASE      => 0.000,
      CLKOUT1_DUTY_CYCLE => 0.500,
      CLKOUT2_DIVIDE     => 16,
      CLKOUT2_PHASE      => 0.000,
      CLKOUT2_DUTY_CYCLE => 0.500,
      CLKIN_PERIOD       => 8.0,
      REF_JITTER         => 0.016)
    port map (
      CLKFBOUT => pllout_clk_fb_pllref,
      CLKOUT0  => pllout_clk_sys,
      CLKOUT1  => open,
      CLKOUT2  => open,
      CLKOUT3  => open,
      CLKOUT4  => open,
      CLKOUT5  => open,
      LOCKED   => open,
      RST      => '0',
      CLKFBIN  => pllout_clk_fb_pllref,
      CLKIN    => clk_125m_pllref);

  cmp_dmtd_clk_pll : PLL_BASE
    generic map (
      BANDWIDTH          => "OPTIMIZED",
      CLK_FEEDBACK       => "CLKFBOUT",
      COMPENSATION       => "INTERNAL",
      DIVCLK_DIVIDE      => 1,
      CLKFBOUT_MULT      => 50,
      CLKFBOUT_PHASE     => 0.000,
      CLKOUT0_DIVIDE     => 16,         -- 62.5 MHz
      CLKOUT0_PHASE      => 0.000,
      CLKOUT0_DUTY_CYCLE => 0.500,
      CLKOUT1_DIVIDE     => 16,         -- 62.5 MHz
      CLKOUT1_PHASE      => 0.000,
      CLKOUT1_DUTY_CYCLE => 0.500,
      CLKOUT2_DIVIDE     => 8,
      CLKOUT2_PHASE      => 0.000,
      CLKOUT2_DUTY_CYCLE => 0.500,
      CLKIN_PERIOD       => 50.0,
      REF_JITTER         => 0.016)
    port map (
      CLKFBOUT => pllout_clk_fb_dmtd,
      CLKOUT0  => pllout_clk_dmtd,
      CLKOUT1  => open,                 --pllout_clk_sys,
      CLKOUT2  => open,
      CLKOUT3  => open,
      CLKOUT4  => open,
      CLKOUT5  => open,
      LOCKED   => open,
      RST      => '0',
      CLKFBIN  => pllout_clk_fb_dmtd,
      CLKIN    => clk_20m_vcxo_buf);



  cmp_clk_sys_buf : BUFG
    port map (
      O => clk_sys,
      I => pllout_clk_sys);

  cmp_clk_dmtd_buf : BUFG
    port map (
      O => clk_dmtd,
      I => pllout_clk_dmtd);

  cmp_clk_vcxo : BUFG
    port map (
      O => clk_20m_vcxo_buf,
      I => clk_20m_vcxo_i);
-----------------------------------------------------------------------------
-- LM32
-----------------------------------------------------------------------------  
  LM32_CORE : xwb_lm32
    generic map(
		g_profile => "medium_icache_debug",
		g_reset_vector=> init_lm32_addr)
    port map(
      clk_sys_i => clk_sys,
      rst_n_i   => forced_lm32_reset_n,
      irq_i     => (others=> '0'),

      dwb_o => cnx_slave_in(c_MASTER_LM32),
      dwb_i => cnx_slave_out(c_MASTER_LM32),
      iwb_o => cnx_slave_in(c_MASTER_LM32+1),
      iwb_i => cnx_slave_out(c_MASTER_LM32+1)
      );
		--trig0 <= cnx_slave_in(c_MASTER_LM32+1).adr;
		--trig2 <= cnx_master_out(c_SLAVE_FD).adr;
--		trig1(0) <= cnx_master_in(c_SLAVE_DPRAM).ack;
--		trig1(1) <= cnx_master_out(c_SLAVE_DPRAM).we; 
--		trig1 <= cnx_slave_in(c_MASTER_LM32).dat;
		--trig3 <= cnx_master_out(c_SLAVE_FD).dat;
--		trig3 <= cnx_slave_out(c_MASTER_LM32).dat;
---------------------------------------------------------------------------
-- Dual-port RAM
-----------------------------------------------------------------------------  
  DPRAM : xwb_dpram
    generic map(
      g_size                  => g_dpram_size,  --in 32-bit words
      g_init_file             => "uart.ram",
      g_must_have_init_file   => true,  --> OJO <--
      g_slave1_interface_mode => PIPELINED,
      g_slave2_interface_mode => PIPELINED,
      g_slave1_granularity    => BYTE,
      g_slave2_granularity    => WORD)  
    port map(
      clk_sys_i => clk_sys,
      rst_n_i   => local_reset_n,

      slave1_i => cnx_master_out(c_SLAVE_DPRAM),
      slave1_o => cnx_master_in(c_SLAVE_DPRAM),
      slave2_i => dpram_wbb_i,
      slave2_o => dpram_wbb_o
      );
-------------------------------------------------------------------------------
-- Gennum core
-------------------------------------------------------------------------------

  cmp_gn4124_core : gn4124_core
    port map
    (
      ---------------------------------------------------------
      -- Control and status
      rst_n_a_i => L_RST_N,
      status_o  => open,

      ---------------------------------------------------------
      -- P2L Direction
      --
      -- Source Sync DDR related signals
      p2l_clk_p_i  => P2L_CLKp,
      p2l_clk_n_i  => P2L_CLKn,
      p2l_data_i   => P2L_DATA,
      p2l_dframe_i => P2L_DFRAME,
      p2l_valid_i  => P2L_VALID,
      -- P2L Control
      p2l_rdy_o    => P2L_RDY,
      p_wr_req_i   => P_WR_REQ,
      p_wr_rdy_o   => P_WR_RDY,
      rx_error_o   => RX_ERROR,
      vc_rdy_i     => VC_RDY,

      ---------------------------------------------------------
      -- L2P Direction
      --
      -- Source Sync DDR related signals
      l2p_clk_p_o  => L2P_CLKp,
      l2p_clk_n_o  => L2P_CLKn,
      l2p_data_o   => L2P_DATA,
      l2p_dframe_o => L2P_DFRAME,
      l2p_valid_o  => L2P_VALID,
      -- L2P Control
      l2p_edb_o    => L2P_EDB,
      l2p_rdy_i    => L2P_RDY,
      l_wr_rdy_i   => L_WR_RDY,
      p_rd_d_rdy_i => P_RD_D_RDY,
      tx_error_i   => TX_ERROR,

      ---------------------------------------------------------
      -- Interrupt interface
      dma_irq_o => open,
      irq_p_i   => '0',
      irq_p_o   => open,

      dma_reg_clk_i => clk_sys,

      ---------------------------------------------------------
      -- CSR wishbone interface (master pipelined)
      csr_clk_i   => clk_sys,
      csr_adr_o   => gn_wb_adr,
      csr_dat_o   => cnx_slave_in(c_MASTER_GENNUM).dat,
      csr_sel_o   => cnx_slave_in(c_MASTER_GENNUM).sel,
      csr_stb_o   => cnx_slave_in(c_MASTER_GENNUM).stb,
      csr_we_o    => cnx_slave_in(c_MASTER_GENNUM).we,
      csr_cyc_o   => cnx_slave_in(c_MASTER_GENNUM).cyc,
      csr_dat_i   => cnx_slave_out(c_MASTER_GENNUM).dat,
      csr_ack_i   => cnx_slave_out(c_MASTER_GENNUM).ack,
      csr_stall_i => cnx_slave_out(c_MASTER_GENNUM).stall,

      dma_clk_i   => clk_sys,
      dma_ack_i   => '1',
      dma_stall_i => '0',
      dma_dat_i   => (others => '0'),

      dma_reg_adr_i => (others => '0'),
      dma_reg_dat_i => (others => '0'),
      dma_reg_sel_i => (others => '0'),
      dma_reg_stb_i => '0',
      dma_reg_cyc_i => '0',
      dma_reg_we_i  => '0'
      );

  cnx_slave_in(c_MASTER_GENNUM).adr <= gn_wb_adr(29 downto 0) & "00";

-------------------------------------------------------------------------------
-- Top level interconnect and interrupt controller
-------------------------------------------------------------------------------

  U_Intercon : xwb_sdb_crossbar
    generic map (
      g_num_masters => c_NUM_WB_SLAVES,
      g_num_slaves  => c_NUM_WB_MASTERS,
      g_registered  => true,
      g_wraparound  => true,
      g_layout      => c_INTERCONNECT_LAYOUT,
      g_sdb_addr    => c_SDB_ADDRESS)
    port map (
      clk_sys_i => clk_sys,
      rst_n_i   => local_reset_n,
      slave_i   => cnx_slave_in,
      slave_o   => cnx_slave_out,
      master_i  => cnx_master_in,
      master_o  => cnx_master_out);

  U_VIC : xwb_vic
    generic map (
      g_interface_mode      => PIPELINED,
      g_address_granularity => BYTE,
      g_num_interrupts      => 1,
      g_init_vectors        => c_VIC_VECTOR_TABLE)
    port map (
      clk_sys_i    => clk_sys,
      rst_n_i      => local_reset_n,
      slave_i      => cnx_master_out(c_SLAVE_VIC),
      slave_o      => cnx_master_in(c_SLAVE_VIC),
      irqs_i(0)    => fd_irq,
      irq_master_o => GPIO(0));

-------------------------------------------------------------------------------
-- White Rabbit Core + PHY
-------------------------------------------------------------------------------

  -- Tristates for FMC EEPROM
  fmc_scl_b  <= '0' when (wrc_scl_out = '0' or fd_scl_out = '0') else 'Z';
  fmc_sda_b  <= '0' when (wrc_sda_out = '0' or fd_sda_out = '0') else 'Z';
  wrc_scl_in <= fmc_scl_b;
  wrc_sda_in <= fmc_sda_b;
  fd_scl_in  <= fmc_scl_b;
  fd_sda_in  <= fmc_sda_b;

  -- Tristates for SFP EEPROM
  sfp_mod_def1_b <= '0' when sfp_scl_out = '0' else 'Z';
  sfp_mod_def2_b <= '0' when sfp_sda_out = '0' else 'Z';
  sfp_scl_in     <= sfp_mod_def1_b;
  sfp_sda_in     <= sfp_mod_def2_b;

  carrier_onewire_b <= '0' when wrc_owr_en(0) = '1' else 'Z';
  wrc_owr_in(0)     <= carrier_onewire_b;
  
  
--  chipscope_ila_1 : chipscope_ila
--    port map (
--      CONTROL => CONTROL,
--      CLK     => clk_sys,
--      TRIG0   => TRIG0,
--      TRIG1   => TRIG1,
--      TRIG2   => TRIG2,
--      TRIG3   => TRIG3);
--
--  chipscope_icon_1 : chipscope_icon
--    port map (
--      CONTROL0 => CONTROL);

  U_WR_CORE : xwr_core
    generic map (
      g_simulation                => g_simulation,
      g_phys_uart                 => true,
      g_virtual_uart              => true,
      g_with_external_clock_input => false,
      g_aux_clks                  => 1,
      g_ep_rxbuf_size             => 1024,
      g_dpram_initf               => "wrc_eth.ram",
      g_dpram_size                => 90112/4,
      g_interface_mode            => PIPELINED,
      g_address_granularity       => BYTE,
      g_softpll_enable_debugger   => false,
		g_aux_sdb						 => c_etherbone_sdb)
    port map (
      clk_sys_i    => clk_sys,
      clk_dmtd_i   => clk_dmtd,
      clk_ref_i    => clk_125m_pllref,
      clk_aux_i(0) => dcm_clk_ref_0,
      rst_n_i      => local_reset_n,

      dac_hpll_load_p1_o => dac_hpll_load_p1,
      dac_hpll_data_o    => dac_hpll_data,
      dac_dpll_load_p1_o => dac_dpll_load_p1,
      dac_dpll_data_o    => dac_dpll_data,

      phy_ref_clk_i      => clk_125m_pllref,
      phy_tx_data_o      => phy_tx_data,
      phy_tx_k_o         => phy_tx_k,
      phy_tx_disparity_i => phy_tx_disparity,
      phy_tx_enc_err_i   => phy_tx_enc_err,
      phy_rx_data_i      => phy_rx_data,
      phy_rx_rbclk_i     => phy_rx_rbclk,
      phy_rx_k_i         => phy_rx_k,
      phy_rx_enc_err_i   => phy_rx_enc_err,
      phy_rx_bitslide_i  => phy_rx_bitslide,
      phy_rst_o          => phy_rst,
      phy_loopen_o       => phy_loopen,

      led_act_o  => open,
      led_link_o => LED_GREEN,

      scl_o     => wrc_scl_out,
      scl_i     => wrc_scl_in,
      sda_o     => wrc_sda_out,
      sda_i     => wrc_sda_in,
      sfp_scl_o => sfp_scl_out,
      sfp_scl_i => sfp_scl_in,
      sfp_sda_o => sfp_sda_out,
      sfp_sda_i => sfp_sda_in,
      sfp_det_i => sfp_mod_def0_b,

--      uart_rxd_i => uart_rxd_i,
--      uart_txd_o => uart_txd_o,
		
		uart_rxd_i => wrpc_uart_rxd_i,
      uart_txd_o => wrpc_uart_txd_o,

      owr_en_o => wrc_owr_en,
      owr_i    => wrc_owr_in,

      slave_i => cnx_master_out(c_SLAVE_WRCORE),
      slave_o => cnx_master_in(c_SLAVE_WRCORE),

      aux_master_o => etherbone_cfg_in,
      aux_master_i => etherbone_cfg_out,

      wrf_src_o => etherbone_snk_in,
      wrf_src_i => etherbone_snk_out,
      wrf_snk_o => etherbone_src_in,
      wrf_snk_i => etherbone_src_out,

      tm_link_up_o         => tm_link_up,
      tm_dac_value_o       => tm_dac_value,
      tm_dac_wr_o(0)          => tm_dac_wr,
      tm_clk_aux_lock_en_i(0) => tm_clk_aux_lock_en,
      tm_clk_aux_locked_o(0)  => tm_clk_aux_locked,
      tm_time_valid_o      => tm_time_valid,
      tm_tai_o             => tm_utc,
      tm_cycles_o          => tm_cycles,

      btn1_i => '1',
      btn2_i => '1',

      rst_aux_n_o => etherbone_rst_n,
      pps_p_o     => pps
      );


  U_GTP : wr_gtp_phy_spartan6
    generic map (
      g_simulation => g_simulation,
      g_enable_ch0 => 0,
      g_enable_ch1 => 1)
    port map (
      gtp_clk_i          => clk_125m_gtp,
      ch0_ref_clk_i      => clk_125m_pllref,
      ch0_tx_data_i      => x"00",
      ch0_tx_k_i         => '0',
      ch0_tx_disparity_o => open,
      ch0_tx_enc_err_o   => open,
      ch0_rx_rbclk_o     => open,
      ch0_rx_data_o      => open,
      ch0_rx_k_o         => open,
      ch0_rx_enc_err_o   => open,
      ch0_rx_bitslide_o  => open,
      ch0_rst_i          => '1',
      ch0_loopen_i       => '0',

      ch1_ref_clk_i      => clk_125m_pllref,
      ch1_tx_data_i      => phy_tx_data,
      ch1_tx_k_i         => phy_tx_k,
      ch1_tx_disparity_o => phy_tx_disparity,
      ch1_tx_enc_err_o   => phy_tx_enc_err,
      ch1_rx_data_o      => phy_rx_data,
      ch1_rx_rbclk_o     => phy_rx_rbclk,
      ch1_rx_k_o         => phy_rx_k,
      ch1_rx_enc_err_o   => phy_rx_enc_err,
      ch1_rx_bitslide_o  => phy_rx_bitslide,
      ch1_rst_i          => phy_rst,
      ch1_loopen_i       => '0',        --phy_loopen,
      pad_txn0_o         => open,
      pad_txp0_o         => open,
      pad_rxn0_i         => '0',
      pad_rxp0_i         => '0',
      pad_txn1_o         => sfp_txn_o,
      pad_txp1_o         => sfp_txp_o,
      pad_rxn1_i         => sfp_rxn_i,
      pad_rxp1_i         => sfp_rxp_i);

  U_Etherbone : eb_slave_core
    generic map (
      g_sdb_address => f_resize_slv(c_sdb_address, 64))
    port map (
      clk_i       => clk_sys,
      nRst_i      => etherbone_rst_n,
      src_o       => etherbone_src_out,
      src_i       => etherbone_src_in,
      snk_o       => etherbone_snk_out,
      snk_i       => etherbone_snk_in,
      cfg_slave_o => etherbone_cfg_out,
      cfg_slave_i => etherbone_cfg_in,
      master_o    => cnx_slave_in(c_MASTER_ETHERBONE),
      master_i    => cnx_slave_out(c_MASTER_ETHERBONE));


  U_DAC_ARB : spec_serial_dac_arb
    generic map (
      g_invert_sclk    => false,
      g_num_extra_bits => 8)

    port map (
      clk_i   => clk_sys,
      rst_n_i => local_reset_n,

      val1_i  => dac_dpll_data,
      load1_i => dac_dpll_load_p1,

      val2_i  => dac_hpll_data,
      load2_i => dac_hpll_load_p1,

      dac_cs_n_o(0) => dac_cs1_n_o,
      dac_cs_n_o(1) => dac_cs2_n_o,
--      dac_clr_n_o   => open,
      dac_sclk_o    => dac_sclk_o,
      dac_din_o     => dac_din_o);

--  dac_clr_n_o <= '1';

  sfp_tx_disable_o <= '0';

-------------------------------------------------------------------------------
-- FINE DELAY INSTANTIATION
-------------------------------------------------------------------------------

  cmp_fd_tdc_start : IBUFDS
    generic map (
      DIFF_TERM    => true,
      IBUF_LOW_PWR => false  -- Low power (TRUE) vs. performance (FALSE) setting for referenced
      )
    port map (
      O  => fd_tdc_start,               -- Buffer output
      I  => fd_tdc_start_p_i,  -- Diff_p buffer input (connect directly to top-level port)
      IB => fd_tdc_start_n_i  -- Diff_n buffer input (connect directly to top-level port)
      );

  U_DDR_PLL : fd_ddr_pll
    port map (
      RST       => ddr_pll_reset,
      LOCKED    => ddr_pll_locked,
      CLK_IN1_P => fd_clk_ref_p_i,
      CLK_IN1_N => fd_clk_ref_n_i,
      CLK_OUT1  => dcm_clk_ref_0,
      CLK_OUT2  => dcm_clk_ref_180);

  ddr_pll_reset <= not fd_pll_status_i;
  fd_pll_status <= fd_pll_status_i and ddr_pll_locked;

  U_FineDelay_Core : fine_delay_core
    generic map (
      g_with_wr_core        => true,
      g_simulation          => f_int2bool(g_simulation),
      g_interface_mode      => PIPELINED,
      g_address_granularity => BYTE)
    port map (
      clk_ref_0_i   => dcm_clk_ref_0,
      clk_ref_180_i => dcm_clk_ref_180,
      clk_sys_i     => clk_sys,
      clk_dmtd_i    => clk_dmtd,
      rst_n_i       => local_reset_n,
      dcm_reset_o   => open,
      dcm_locked_i  => ddr_pll_locked,

      trig_a_i          => fd_trig_a_i,
      tdc_cal_pulse_o   => fd_tdc_cal_pulse_o,
      tdc_start_i       => fd_tdc_start,
      dmtd_fb_in_i      => fd_dmtd_fb_in_i,
      dmtd_fb_out_i     => fd_dmtd_fb_out_i,
      dmtd_samp_o       => fd_dmtd_clk_o,
      led_trig_o        => fd_led_trig_o,
      ext_rst_n_o       => fd_ext_rst_n_o,
      pll_status_i      => fd_pll_status,
      acam_d_o          => tdc_data_out,
      acam_d_i          => tdc_data_in,
      acam_d_oen_o      => tdc_data_oe,
      acam_emptyf_i     => fd_tdc_emptyf_i,
      acam_alutrigger_o => fd_tdc_alutrigger_o,
      acam_wr_n_o       => fd_tdc_wr_n_o,
      acam_rd_n_o       => fd_tdc_rd_n_o,
      acam_start_dis_o  => fd_tdc_start_dis_o,
      acam_stop_dis_o   => fd_tdc_stop_dis_o,
      spi_cs_dac_n_o    => fd_spi_cs_dac_n_o,
      spi_cs_pll_n_o    => fd_spi_cs_pll_n_o,
      spi_cs_gpio_n_o   => fd_spi_cs_gpio_n_o,
      spi_sclk_o        => fd_spi_sclk_o,
      spi_mosi_o        => fd_spi_mosi_o,
      spi_miso_i        => fd_spi_miso_i,

      delay_len_o   => fd_delay_len_o,
      delay_val_o   => fd_delay_val_o,
      delay_pulse_o => fd_delay_pulse_o,

      tm_link_up_i         => tm_link_up,
      tm_time_valid_i      => tm_time_valid,
      tm_cycles_i          => tm_cycles,
      tm_utc_i             => tm_utc,
      tm_clk_aux_lock_en_o => tm_clk_aux_lock_en,
      tm_clk_aux_locked_i  => tm_clk_aux_locked,
      tm_clk_dmtd_locked_i => '1',  --    FIXME: fan out real signal from the
      --    WRCore
      tm_dac_value_i       => tm_dac_value,
      tm_dac_wr_i          => tm_dac_wr,

      owr_en_o        => fd_owr_en,
      owr_i           => fd_owr_in,
      i2c_scl_oen_o   => fd_scl_out,
      i2c_scl_i       => fd_scl_in,
      i2c_sda_oen_o   => fd_sda_out,
      i2c_sda_i       => fd_sda_in,
      fmc_present_n_i => fmc_prsnt_m2c_l_i,

      wb_adr_i   => cnx_master_out(c_SLAVE_FD).adr,
      wb_dat_i   => cnx_master_out(c_SLAVE_FD).dat,
      wb_dat_o   => cnx_master_in(c_SLAVE_FD).dat,
      wb_sel_i   => cnx_master_out(c_SLAVE_FD).sel,
      wb_cyc_i   => cnx_master_out(c_SLAVE_FD).cyc,
      wb_stb_i   => cnx_master_out(c_SLAVE_FD).stb,
      wb_we_i    => cnx_master_out(c_SLAVE_FD).we,
      wb_ack_o   => cnx_master_in(c_SLAVE_FD).ack,
      wb_stall_o => cnx_master_in(c_SLAVE_FD).stall,
      wb_irq_o   => fd_irq);
		
		--trig0 <= cnx_master_out(c_SLAVE_FD).adr;

-- tristate buffer for the TDC data bus:
  fd_tdc_d_b    <= tdc_data_out when tdc_data_oe = '1' else (others => 'Z');
  fd_tdc_oe_n_o <= '1';
  tdc_data_in   <= fd_tdc_d_b;

  fd_onewire_b <= '0' when fd_owr_en = '1' else 'Z';
  fd_owr_in    <= fd_onewire_b;


end rtl;


