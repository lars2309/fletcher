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
use work.MM.all;
use work.MM_tc_params.all;

entity MMBarrier_tc is
end MMBarrier_tc;

architecture tb of MMBarrier_tc is
  signal bus_clk                : std_logic                                               := '0';
  signal acc_clk                : std_logic                                               := '0';
  signal bus_reset              : std_logic                                               := '0';
  signal acc_reset              : std_logic                                               := '0';

  signal TbClock                : std_logic                                               := '0';
  signal TbReset                : std_logic                                               := '0';
  signal TbSimEnded             : std_logic                                               := '0';

  signal dirty                  : std_logic;

  signal slv_wreq_valid         : std_logic;
  signal slv_wreq_ready         : std_logic;
  signal slv_wreq_addr          : std_logic_vector(BUS_ADDR_WIDTH-1 downto 0);
  signal slv_wreq_len           : std_logic_vector(BUS_LEN_WIDTH-1 downto 0);
  signal slv_wreq_barrier       : std_logic;
  signal mst_wreq_valid         : std_logic;
  signal mst_wreq_ready         : std_logic;
  signal mst_wreq_addr          : std_logic_vector(BUS_ADDR_WIDTH-1 downto 0);
  signal mst_wreq_len           : std_logic_vector(BUS_LEN_WIDTH-1 downto 0);
  signal slv_resp_valid         : std_logic;
  signal slv_resp_ready         : std_logic;
  signal slv_resp_ok            : std_logic;
  signal mst_resp_valid         : std_logic;
  signal mst_resp_ready         : std_logic;
  signal mst_resp_ok            : std_logic;

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

    slv_wreq_valid   <= '0';
    slv_wreq_addr    <= slv(resize(unsigned(slv(x"deadbeef")), slv_wreq_addr'length));
    slv_wreq_len     <= slv(to_unsigned(3, slv_wreq_len'length));
    slv_wreq_barrier <= '0';
    slv_resp_ready   <= '1';
    mst_wreq_ready   <= '1';
    mst_resp_valid   <= '0';
    mst_resp_ok      <= '1';

    wait until rising_edge(TbClock);
    TbReset                     <= '0';
    wait until rising_edge(TbClock);

    handshake_out(TbClock, slv_wreq_ready, slv_wreq_valid);

    slv_wreq_barrier <= '1';
    handshake_out(TbClock, slv_wreq_ready, slv_wreq_valid);

    handshake_out(TbClock, mst_resp_ready, mst_resp_valid);
    wait until rising_edge(TbClock);
    handshake_out(TbClock, mst_resp_ready, mst_resp_valid);

    wait until rising_edge(TbClock);

    TbSimEnded                  <= '1';

    report "END OF TEST"  severity note;

    wait;

  end process;

  barrier_inst : MMBarrier
    generic map (
      BUS_ADDR_WIDTH            => BUS_ADDR_WIDTH,
      BUS_LEN_WIDTH             => BUS_LEN_WIDTH,
      MAX_OUTSTANDING           => 3
    )
    port map (
      clk                       => bus_clk,
      reset                     => bus_reset,
      dirty                     => dirty,

      -- Slave write request channel
      slv_wreq_valid            => slv_wreq_valid,
      slv_wreq_ready            => slv_wreq_ready,
      slv_wreq_addr             => slv_wreq_addr,
      slv_wreq_len              => slv_wreq_len,
      slv_wreq_barrier          => slv_wreq_barrier,
      -- Master write request channel
      mst_wreq_valid            => mst_wreq_valid,
      mst_wreq_ready            => mst_wreq_ready,
      mst_wreq_addr             => mst_wreq_addr,
      mst_wreq_len              => mst_wreq_len,

      -- Slave response channel
      slv_resp_valid            => slv_resp_valid,
      slv_resp_ready            => slv_resp_ready,
      slv_resp_ok               => slv_resp_ok,
      -- Master response channel
      mst_resp_valid            => mst_resp_valid,
      mst_resp_ready            => mst_resp_ready,
      mst_resp_ok               => mst_resp_ok
    );

end architecture;
