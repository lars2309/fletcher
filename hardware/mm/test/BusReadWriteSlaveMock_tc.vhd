-- Copyright 2018 Delft University of Technology
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
use work.MM_tc_params.all;


entity BusReadWriteSlaveMock_tc is
end BusReadWriteSlaveMock_tc;

architecture tb of BusReadWriteSlaveMock_tc is
  signal bus_clk                : std_logic                                               := '0';
  signal bus_reset              : std_logic                                               := '0';
  signal acc_clk                : std_logic                                               := '0';
  signal acc_reset              : std_logic                                               := '0';
  signal bus_rreq_valid         : std_logic                                               := '0';
  signal bus_rreq_ready         : std_logic                                               := '0';
  signal bus_rreq_addr          : std_logic_vector(BUS_ADDR_WIDTH-1 downto 0)             := (others => '0');
  signal bus_rreq_len           : std_logic_vector(BUS_LEN_WIDTH-1 downto 0)              := (others => '0');
  signal bus_rdat_valid         : std_logic                                               := '0';
  signal bus_rdat_ready         : std_logic                                               := '0';
  signal bus_rdat_data          : std_logic_vector(BUS_DATA_WIDTH-1 downto 0)             := (others => '0');
  signal bus_rdat_last          : std_logic                                               := '0';
  signal bus_wreq_valid         : std_logic;
  signal bus_wreq_ready         : std_logic;
  signal bus_wreq_addr          : std_logic_vector(BUS_ADDR_WIDTH-1 downto 0);
  signal bus_wreq_len           : std_logic_vector(BUS_LEN_WIDTH-1 downto 0);
  signal bus_wdat_valid         : std_logic;
  signal bus_wdat_ready         : std_logic;
  signal bus_wdat_data          : std_logic_vector(BUS_DATA_WIDTH-1 downto 0);
  signal bus_wdat_strobe        : std_logic_vector(BUS_STROBE_WIDTH-1 downto 0);
  signal bus_wdat_last          : std_logic;

  signal TbClock                : std_logic                                               := '0';
  signal TbReset                : std_logic                                               := '0';
  signal TbSimEnded             : std_logic                                               := '0';

  procedure handshake (signal clk : in std_logic; signal rdy : in std_logic) is
  begin
    loop
      wait until rising_edge(clk);
      exit when rdy = '1';
    end loop;
    wait for 0 ns;
  end handshake;

begin

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

    bus_rreq_addr               <= std_logic_vector(to_unsigned(0, BUS_ADDR_WIDTH));
    bus_rreq_len                <= std_logic_vector(to_unsigned(1, BUS_LEN_WIDTH));
    bus_rreq_valid              <= '1';
    handshake(TbClock, bus_rreq_ready);
    bus_rreq_addr               <= (others => 'U');
    bus_rreq_len                <= (others => 'U');
    bus_rreq_valid              <= '0';

    bus_rdat_ready              <= '1';
    handshake(TbClock, bus_rdat_valid);
    bus_rdat_ready              <= '0';

    bus_wreq_addr               <= std_logic_vector(to_unsigned(0, BUS_ADDR_WIDTH));
    bus_wreq_len                <= std_logic_vector(to_unsigned(1, BUS_LEN_WIDTH));
    bus_wreq_valid              <= '1';
    handshake(TbClock, bus_wreq_ready);
    bus_wreq_addr               <= (others => 'U');
    bus_wreq_len                <= (others => 'U');
    bus_wreq_valid              <= '0';

    bus_wdat_strobe             <= (others => '1');
    bus_wdat_last               <= '1';
    bus_wdat_data               <= X"DEADBEEF_12345678_BADCAFFE_13378888_11111111_22222222_33333333_44444444_11111111_22222222_33333333_44444444_11111111_22222222_33333333_44444444";
    bus_wdat_valid              <= '1';
    handshake(TbClock, bus_wdat_ready);
    bus_wdat_strobe             <= (others => 'U');
    bus_wdat_last               <= 'U';
    bus_wdat_data               <= (others => 'U');
    bus_wdat_valid              <= '0';

    bus_rreq_addr               <= std_logic_vector(to_unsigned(0, BUS_ADDR_WIDTH));
    bus_rreq_len                <= std_logic_vector(to_unsigned(1, BUS_LEN_WIDTH));
    bus_rreq_valid              <= '1';
    handshake(TbClock, bus_rreq_ready);
    bus_rreq_addr               <= (others => 'U');
    bus_rreq_len                <= (others => 'U');
    bus_rreq_valid              <= '0';

    bus_rdat_ready              <= '1';
    handshake(TbClock, bus_rdat_valid);
    bus_rdat_ready              <= '0';

    TbSimEnded                  <= '1';

    report "END OF TEST"  severity note;

    wait;

  end process;

end architecture;
