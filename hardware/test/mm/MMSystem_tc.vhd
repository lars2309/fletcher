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
use work.Interconnect.all;
use work.MM.all;
use work.MM_tc_params.all;

entity MMSystem_tc is
end MMSystem_tc;

architecture tb of MMSystem_tc is
  signal bus_clk                : std_logic                                               := '0';
  signal acc_clk                : std_logic                                               := '0';
  signal bus_reset              : std_logic                                               := '0';
  signal acc_reset              : std_logic                                               := '0';
  signal bus_rreq_valid         : std_logic                                               := '0';
  signal bus_rreq_ready         : std_logic                                               := '0';
  signal bus_rreq_addr          : std_logic_vector(BUS_ADDR_WIDTH-1 downto 0)             := (others => '0');
  signal bus_rreq_len           : std_logic_vector(BUS_LEN_WIDTH-1 downto 0)              := (others => '0');
  signal bus_rdat_valid         : std_logic                                               := '0';
  signal bus_rdat_ready         : std_logic                                               := '0';
  signal bus_rdat_data          : std_logic_vector(BUS_DATA_WIDTH-1 downto 0)             := (others => '0');
  signal bus_rdat_last          : std_logic                                               := '0';
  signal bus_wreq_valid         : std_logic                                               := '0';
  signal bus_wreq_ready         : std_logic;
  signal bus_wreq_addr          : std_logic_vector(BUS_ADDR_WIDTH-1 downto 0);
  signal bus_wreq_len           : std_logic_vector(BUS_LEN_WIDTH-1 downto 0);
  signal bus_wdat_valid         : std_logic;
  signal bus_wdat_ready         : std_logic;
  signal bus_wdat_data          : std_logic_vector(BUS_DATA_WIDTH-1 downto 0);
  signal bus_wdat_strobe        : std_logic_vector(BUS_STROBE_WIDTH-1 downto 0);
  signal bus_wdat_last          : std_logic;
  signal frames_cmd_region      : std_logic_vector(log2ceil(MEM_REGIONS)-1 downto 0);
  signal frames_cmd_addr        : std_logic_vector(BUS_ADDR_WIDTH-1 downto 0);
  signal frames_cmd_free        : std_logic                                               := '0';
  signal frames_cmd_alloc       : std_logic                                               := '0';
  signal frames_cmd_find        : std_logic                                               := '0';
  signal frames_cmd_clear       : std_logic                                               := '0';
  signal frames_cmd_valid       : std_logic                                               := '0';
  signal frames_cmd_ready       : std_logic;

  signal frames_resp_addr       : std_logic_vector(BUS_ADDR_WIDTH-1 downto 0);
  signal frames_resp_success    : std_logic;
  signal frames_resp_valid      : std_logic;
  signal frames_resp_ready      : std_logic                                               := '0';

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
  acc_reset <= TbReset;

  stimuli : process
  begin
    ---------------------------------------------------------------------------
    wait until rising_edge(TbClock);
    TbReset                     <= '1';
    wait until rising_edge(TbClock);
    TbReset                     <= '0';
    bus_wreq_valid              <= '0';
    bus_wdat_valid              <= '0';
    bus_rreq_valid              <= '0';
    wait until rising_edge(TbClock);



    TbSimEnded                  <= '1';

    report "END OF TEST"  severity note;

    wait;

  end process;

  frames : MMFrames
    generic map (
      PAGE_SIZE_LOG2            => PAGE_SIZE_LOG2,
      MEM_REGIONS               => MEM_REGIONS,
      MEM_SIZES                 => MEM_SIZES,
      MEM_MAP_BASE              => MEM_MAP_BASE,
      MEM_MAP_SIZE_LOG2         => MEM_MAP_SIZE_LOG2,
      BUS_ADDR_WIDTH            => BUS_ADDR_WIDTH
    )
    port map (
      clk                       => bus_clk,
      reset                     => bus_reset,
      cmd_region                => frames_cmd_region,
      cmd_addr                  => frames_cmd_addr,
      cmd_free                  => frames_cmd_free,
      cmd_alloc                 => frames_cmd_alloc,
      cmd_find                  => frames_cmd_find,
      cmd_clear                 => frames_cmd_clear,
      cmd_valid                 => frames_cmd_valid,
      cmd_ready                 => frames_cmd_ready,

      resp_addr                 => frames_resp_addr,
      resp_success              => frames_resp_success,
      resp_valid                => frames_resp_valid,
      resp_ready                => frames_resp_ready
    );

  host_mem : BusReadWriteSlaveMock
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
