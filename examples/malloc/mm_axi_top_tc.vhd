-- Copyright 2019 Delft University of Technology
--
-- Licensed under the Apache License, Version 2.0 (the "License");
-- you may not use this file except in compliance with the License.
-- You may obtain a copy of the License at
--
--     http://www.apache.org/licenses/LICENSE-2.0
--
-- Unless required by applicable law or agreed to in writing, software
-- distributed under the License is distributed on an "AS IS" BASIS,
-- WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
-- See the License for the specific language governing permissions and
-- limitations under the License.

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.Utils.all;
use work.SimUtils.all;
use work.Interconnect.all;
use work.MM.all;
use work.MM_tc_params.all;
use work.AXI.all;

entity mm_axi_top_tc is
end mm_axi_top_tc;

architecture tb of mm_axi_top_tc is
  constant SLV_BUS_ADDR_WIDTH   : natural := 32;
  constant SLV_BUS_DATA_WIDTH   : natural := 32;
  constant SLV_BUS_STROBE_WIDTH : natural := SLV_BUS_DATA_WIDTH/8;

  signal bus_clk                : std_logic                                               := '0';
  signal acc_clk                : std_logic                                               := '0';
  signal bus_reset              : std_logic                                               := '0';
  signal bus_reset_n            : std_logic                                               := '0';
  signal acc_reset              : std_logic                                               := '0';

  signal cmd_region             : std_logic_vector(log2ceil(MEM_REGIONS)-1 downto 0);
  signal cmd_addr               : std_logic_vector(BUS_ADDR_WIDTH-1 downto 0);
  signal cmd_size               : std_logic_vector(BUS_ADDR_WIDTH-1 downto 0);
  signal cmd_free               : std_logic                                               := '0';
  signal cmd_alloc              : std_logic                                               := '0';
  signal cmd_realloc            : std_logic                                               := '0';
  signal cmd_valid              : std_logic                                               := '0';
  signal cmd_ready              : std_logic;
  signal resp_addr              : std_logic_vector(BUS_ADDR_WIDTH-1 downto 0);
  signal resp_success           : std_logic;
  signal resp_valid             : std_logic;
  signal resp_ready             : std_logic                                               := '0';

  signal bus_rreq_valid         : std_logic                                               := '0';
  signal bus_rreq_ready         : std_logic                                               := '0';
  signal bus_rreq_addr          : std_logic_vector(BUS_ADDR_WIDTH-1 downto 0)             := (others => '0');
  signal bus_rreq_len           : std_logic_vector(BUS_LEN_WIDTH-1 downto 0)              := (others => '0');
  signal bus_rreq_size          : std_logic_vector(2 downto 0)                            := (others => '0');
  signal bus_rdat_valid         : std_logic                                               := '0';
  signal bus_rdat_ready         : std_logic                                               := '0';
  signal bus_rdat_data          : std_logic_vector(BUS_DATA_WIDTH-1 downto 0)             := (others => '0');
  signal bus_rdat_resp          : std_logic_vector(1 downto 0)                            := (others => '0');
  signal bus_rdat_last          : std_logic                                               := '0';
  signal bus_wreq_valid         : std_logic                                               := '0';
  signal bus_wreq_ready         : std_logic;
  signal bus_wreq_addr          : std_logic_vector(BUS_ADDR_WIDTH-1 downto 0);
  signal bus_wreq_len           : std_logic_vector(BUS_LEN_WIDTH-1 downto 0);
  signal bus_wreq_size          : std_logic_vector(2 downto 0)                            := (others => '0');
  signal bus_wdat_valid         : std_logic;
  signal bus_wdat_ready         : std_logic;
  signal bus_wdat_data          : std_logic_vector(BUS_DATA_WIDTH-1 downto 0);
  signal bus_wdat_strobe        : std_logic_vector(BUS_STROBE_WIDTH-1 downto 0);
  signal bus_wdat_last          : std_logic;
  signal bus_resp_valid         : std_logic;
  signal bus_resp_ready         : std_logic;
  signal bus_resp_resp          : std_logic_vector(1 downto 0);

  signal slv_rreq_valid         : std_logic                                               := '0';
  signal slv_rreq_ready         : std_logic                                               := '0';
  signal slv_rreq_addr          : std_logic_vector(SLV_BUS_ADDR_WIDTH-1 downto 0)         := (others => '0');
  signal slv_rdat_valid         : std_logic                                               := '0';
  signal slv_rdat_ready         : std_logic                                               := '0';
  signal slv_rdat_data          : std_logic_vector(SLV_BUS_DATA_WIDTH-1 downto 0)         := (others => '0');
  signal slv_rdat_resp          : std_logic_vector(1 downto 0)                            := (others => '0');
  signal slv_wreq_valid         : std_logic                                               := '0';
  signal slv_wreq_ready         : std_logic;
  signal slv_wreq_addr          : std_logic_vector(SLV_BUS_ADDR_WIDTH-1 downto 0);
  signal slv_wdat_valid         : std_logic;
  signal slv_wdat_ready         : std_logic;
  signal slv_wdat_data          : std_logic_vector(SLV_BUS_DATA_WIDTH-1 downto 0);
  signal slv_wdat_strobe        : std_logic_vector(SLV_BUS_STROBE_WIDTH-1 downto 0)       := (others => '1');
  signal slv_resp_valid         : std_logic;
  signal slv_resp_ready         : std_logic;
  signal slv_resp_resp          : std_logic_vector(1 downto 0);

  signal TbClock                : std_logic                                               := '0';
  signal TbReset                : std_logic                                               := '0';
  signal TbSimEnded             : std_logic                                               := '0';

  procedure handshake_out (signal clk : in std_logic; signal rdy : in std_logic;
                           signal valid : out std_logic) is
  begin
    valid <= '1';
    loop
      wait until rising_edge(clk);
      exit when rdy = '1';
    end loop;
    wait for 0 ns;
    valid <= '0';
  end handshake_out;

  procedure handshake_in (signal clk : in std_logic; signal rdy : out std_logic;
                          signal valid : in std_logic) is
  begin
    rdy <= '1';
    loop
      wait until rising_edge(clk);
      exit when valid = '1';
    end loop;
    wait for 0 ns;
    rdy <= '0';
  end handshake_in;

begin

  -- Clock generation
  TbClock <= not TbClock after TbPeriod/2 when TbSimEnded /= '1' else '0';

  bus_clk <= TbClock;
  acc_clk <= TbClock;

  bus_reset <= TbReset;
  bus_reset_n <= not TbReset;
  acc_reset <= TbReset;

  stimuli : process
    variable addr     : std_logic_vector(BUS_ADDR_WIDTH-1 downto 0);
    variable mmio_dat : std_logic_vector(SLV_BUS_DATA_WIDTH-1 downto 0);
  begin
    ---------------------------------------------------------------------------
    TbReset                     <= '1';
    wait until rising_edge(TbClock);
    slv_resp_ready    <= '1';
    slv_wdat_strobe   <= (others => '1');
    slv_wdat_valid    <= '0';
    slv_wreq_valid    <= '0';
    slv_rreq_valid    <= '0';
    slv_resp_ready    <= '1';
    wait until rising_edge(TbClock);
    TbReset                     <= '0';
    wait until rising_edge(TbClock);

    -- Set region to 1
    slv_wreq_addr <= slv(to_unsigned(4*4, slv_wreq_addr'length));
    handshake_out(TbClock, slv_wreq_ready, slv_wreq_valid);

    slv_wdat_data <= slv(to_unsigned(1, slv_wdat_data'length));
    handshake_out(TbClock, slv_wdat_ready, slv_wdat_valid);

    -- Set size to 3 GB
    slv_wreq_addr <= slv(to_unsigned(2*4, slv_wreq_addr'length));
    handshake_out(TbClock, slv_wreq_ready, slv_wreq_valid);

    slv_wdat_data <= slv(shift_left(to_unsigned(3, BUS_ADDR_WIDTH), 20)(slv_wdat_data'length-1 downto 0));
    handshake_out(TbClock, slv_wdat_ready, slv_wdat_valid);

    slv_wreq_addr <= slv(to_unsigned(2*4+4, slv_wreq_addr'length));
    handshake_out(TbClock, slv_wreq_ready, slv_wreq_valid);

    slv_wdat_data <= slv(shift_left(to_unsigned(3, BUS_ADDR_WIDTH), 20)(slv_wdat_data'length*2-1 downto slv_wdat_data'length));
    handshake_out(TbClock, slv_wdat_ready, slv_wdat_valid);

    -- Allocate
    slv_wreq_addr <= slv(to_unsigned(5*4, slv_wreq_addr'length));
    handshake_out(TbClock, slv_wreq_ready, slv_wreq_valid);

    slv_wdat_data <= slv(resize(unsigned(slv("0011")), slv_wdat_data'length));
    handshake_out(TbClock, slv_wdat_ready, slv_wdat_valid);

    -- Wait for completion
    slv_rreq_addr <= slv(to_unsigned(8*4, slv_rreq_addr'length));
    slv_rdat_ready <= '0';
    loop
      handshake_out(TbClock, slv_rreq_ready, slv_rreq_valid);
      loop
        wait until rising_edge(TbClock);
        exit when slv_rdat_valid = '1';
      end loop;
      mmio_dat := slv_rdat_data;
      handshake_in(TbClock, slv_rdat_ready, slv_rdat_valid);
      exit when mmio_dat(0) = '1';
    end loop;

    -- Read address
    slv_rreq_addr <= slv(to_unsigned(6*4, slv_rreq_addr'length));
    handshake_out(TbClock, slv_rreq_ready, slv_rreq_valid);
    slv_rreq_addr <= slv(to_unsigned(6*4+4, slv_rreq_addr'length));
    handshake_out(TbClock, slv_rreq_ready, slv_rreq_valid);

    slv_rdat_ready <= '1';
    loop
      wait until rising_edge(TbClock);
      exit when slv_rdat_valid = '1';
    end loop;
    addr(31 downto 0) := slv_rdat_data;
    loop
      wait until rising_edge(TbClock);
      exit when slv_rdat_valid = '1';
    end loop;
    addr(63 downto 32) := slv_rdat_data;
    report "malloc of size 3GB at " & sim_hex_no0x(addr);
    wait for 0 ns;
    slv_rdat_ready <= '0';

    -- Reset response
    slv_wreq_addr <= slv(to_unsigned(8*4, slv_wreq_addr'length));
    handshake_out(TbClock, slv_wreq_ready, slv_wreq_valid);

    slv_wdat_data <= slv(to_unsigned(0, slv_wdat_data'length));
    handshake_out(TbClock, slv_wdat_ready, slv_wdat_valid);


    -- Set region to 1
    slv_wreq_addr <= slv(to_unsigned(4*4, slv_wreq_addr'length));
    handshake_out(TbClock, slv_wreq_ready, slv_wreq_valid);

    slv_wdat_data <= slv(to_unsigned(1, slv_wdat_data'length));
    handshake_out(TbClock, slv_wdat_ready, slv_wdat_valid);

    -- Set size to 34 GB
    slv_wreq_addr <= slv(to_unsigned(2*4, slv_wreq_addr'length));
    handshake_out(TbClock, slv_wreq_ready, slv_wreq_valid);

    slv_wdat_data <= slv(shift_left(to_unsigned(34, BUS_ADDR_WIDTH), 30)(slv_wdat_data'length-1 downto 0));
    handshake_out(TbClock, slv_wdat_ready, slv_wdat_valid);

    slv_wreq_addr <= slv(to_unsigned(2*4+4, slv_wreq_addr'length));
    handshake_out(TbClock, slv_wreq_ready, slv_wreq_valid);

    slv_wdat_data <= slv(shift_left(to_unsigned(34, BUS_ADDR_WIDTH), 30)(slv_wdat_data'length*2-1 downto slv_wdat_data'length));
    handshake_out(TbClock, slv_wdat_ready, slv_wdat_valid);

    -- Allocate
    slv_wreq_addr <= slv(to_unsigned(5*4, slv_wreq_addr'length));
    handshake_out(TbClock, slv_wreq_ready, slv_wreq_valid);

    slv_wdat_data <= slv(resize(unsigned(slv("0011")), slv_wdat_data'length));
    handshake_out(TbClock, slv_wdat_ready, slv_wdat_valid);

    -- Wait for completion
    slv_rreq_addr <= slv(to_unsigned(8*4, slv_rreq_addr'length));
    slv_rdat_ready <= '0';
    loop
      handshake_out(TbClock, slv_rreq_ready, slv_rreq_valid);
      loop
        wait until rising_edge(TbClock);
        exit when slv_rdat_valid = '1';
      end loop;
      mmio_dat := slv_rdat_data;
      handshake_in(TbClock, slv_rdat_ready, slv_rdat_valid);
      exit when mmio_dat(0) = '1';
    end loop;

    -- Read address
    slv_rreq_addr <= slv(to_unsigned(6*4, slv_rreq_addr'length));
    handshake_out(TbClock, slv_rreq_ready, slv_rreq_valid);
    slv_rreq_addr <= slv(to_unsigned(6*4+4, slv_rreq_addr'length));
    handshake_out(TbClock, slv_rreq_ready, slv_rreq_valid);

    slv_rdat_ready <= '1';
    loop
      wait until rising_edge(TbClock);
      exit when slv_rdat_valid = '1';
    end loop;
    addr(31 downto 0) := slv_rdat_data;
    loop
      wait until rising_edge(TbClock);
      exit when slv_rdat_valid = '1';
    end loop;
    addr(63 downto 32) := slv_rdat_data;
    report "malloc of size 34GB at " & sim_hex_no0x(addr);
    wait for 0 ns;
    slv_rdat_ready <= '0';

    -- Reset response
    slv_wreq_addr <= slv(to_unsigned(8*4, slv_wreq_addr'length));
    handshake_out(TbClock, slv_wreq_ready, slv_wreq_valid);

    slv_wdat_data <= slv(to_unsigned(0, slv_wdat_data'length));
    handshake_out(TbClock, slv_wdat_ready, slv_wdat_valid);


    TbSimEnded                  <= '0';

    report "END OF TEST"  severity note;

    wait;

  end process;

  top_inst : axi_top
    generic map (
      BUS_ADDR_WIDTH              => BUS_ADDR_WIDTH,
      BUS_DATA_WIDTH              => BUS_DATA_WIDTH,
      BUS_STROBE_WIDTH            => BUS_STROBE_WIDTH,
      BUS_LEN_WIDTH               => BUS_LEN_WIDTH,
      BUS_BURST_MAX_LEN           => BUS_BURST_MAX_LEN,
      BUS_BURST_STEP_LEN          => BUS_BURST_STEP_LEN,
      NUM_REGS                    => 9
    )
    port map (
      acc_clk                     => acc_clk,
      acc_reset                   => acc_reset,
      bus_clk                     => bus_clk,
      bus_reset_n                 => bus_reset_n,

      -- Read address channel
      m_axi_araddr                => bus_rreq_addr,
      m_axi_arlen                 => bus_rreq_len,
      m_axi_arvalid               => bus_rreq_valid,
      m_axi_arready               => bus_rreq_ready,
      m_axi_arsize                => bus_rreq_size,

      -- Read data channel
      m_axi_rdata                 => bus_rdat_data,
      m_axi_rresp                 => bus_rdat_resp,
      m_axi_rlast                 => bus_rdat_last,
      m_axi_rvalid                => bus_rdat_valid,
      m_axi_rready                => bus_rdat_ready,

      -- Write address channel
      m_axi_awvalid               => bus_wreq_valid,
      m_axi_awready               => bus_wreq_ready,
      m_axi_awaddr                => bus_wreq_addr,
      m_axi_awlen                 => bus_wreq_len,
      m_axi_awsize                => bus_wreq_size,

      -- Write data channel
      m_axi_wvalid                => bus_wdat_valid,
      m_axi_wready                => bus_wdat_ready,
      m_axi_wdata                 => bus_wdat_data,
      m_axi_wlast                 => bus_wdat_last,
      m_axi_wstrb                 => bus_wdat_strobe,

      -- Write response channel
      m_axi_bvalid                => bus_resp_valid,
      m_axi_bready                => bus_resp_ready,
      m_axi_bresp                 => bus_resp_resp,

      ---------------------------------------------------------------------------
      -- AXI4-lite Slave as MMIO interface
      ---------------------------------------------------------------------------
      -- Read address channel
      s_axi_araddr                => slv_rreq_addr,
      s_axi_arvalid               => slv_rreq_valid,
      s_axi_arready               => slv_rreq_ready,

      -- Read data channel
      s_axi_rdata                 => slv_rdat_data,
      s_axi_rresp                 => slv_rdat_resp,
      s_axi_rvalid                => slv_rdat_valid,
      s_axi_rready                => slv_rdat_ready,

      -- Write address channel
      s_axi_awvalid               => slv_wreq_valid,
      s_axi_awready               => slv_wreq_ready,
      s_axi_awaddr                => slv_wreq_addr,

      -- Write data channel
      s_axi_wvalid                => slv_wdat_valid,
      s_axi_wready                => slv_wdat_ready,
      s_axi_wdata                 => slv_wdat_data,
      s_axi_wstrb                 => slv_wdat_strobe,

      -- Write response channel
      s_axi_bvalid                => slv_resp_valid,
      s_axi_bready                => slv_resp_ready,
      s_axi_bresp                 => slv_resp_resp
    );

  dev_mem : AXIReadWriteSlaveMock
    generic map (
      BUS_ADDR_WIDTH            => BUS_ADDR_WIDTH,
      BUS_LEN_WIDTH             => BUS_LEN_WIDTH,
      BUS_DATA_WIDTH            => BUS_DATA_WIDTH,
      BUS_STROBE_WIDTH          => BUS_STROBE_WIDTH,
      SEED                      => 1337,
      RANDOM_REQUEST_TIMING     => BUS_SLAVE_RND_REQ,
      RANDOM_RESPONSE_TIMING    => BUS_SLAVE_RND_RESP,
      SREC_FILE                 => ""
    )
    port map (
      clk                       => bus_clk,
      reset                     => bus_reset,

      wreq_valid                => bus_wreq_valid,
      wreq_ready                => bus_wreq_ready,
      wreq_addr                 => bus_wreq_addr,
      wreq_len                  => bus_wreq_len,
      wdat_valid                => bus_wdat_valid,
      wdat_ready                => bus_wdat_ready,
      wdat_data                 => bus_wdat_data,
      wdat_strobe               => bus_wdat_strobe,
      wdat_last                 => bus_wdat_last,

      resp_valid                => bus_resp_valid,
      resp_ready                => bus_resp_ready,
      resp_resp                 => bus_resp_resp,

      rreq_valid                => bus_rreq_valid,
      rreq_ready                => bus_rreq_ready,
      rreq_addr                 => bus_rreq_addr,
      rreq_len                  => bus_rreq_len,
      rdat_valid                => bus_rdat_valid,
      rdat_ready                => bus_rdat_ready,
      rdat_data                 => bus_rdat_data,
      rdat_last                 => bus_rdat_last
    );

end architecture;
