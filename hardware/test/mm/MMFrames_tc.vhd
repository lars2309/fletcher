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

entity MMFrames_tc is
end MMFrames_tc;

architecture tb of MMFrames_tc is
  signal bus_clk                : std_logic                                               := '0';
  signal acc_clk                : std_logic                                               := '0';
  signal bus_reset              : std_logic                                               := '0';
  signal acc_reset              : std_logic                                               := '0';
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
    wait until rising_edge(TbClock);

    frames_resp_ready           <= '0';

    -- Clear frames
    frames_cmd_clear            <= '1';
    handshake_out(TbClock, frames_cmd_ready, frames_cmd_valid);
    frames_cmd_clear            <= '0';
    handshake_in(TbClock, frames_resp_ready, frames_resp_valid);

    -- Reserve frame for page table
    frames_cmd_alloc            <= '1';
    frames_cmd_addr             <= PT_ADDR;
    handshake_out(TbClock, frames_cmd_ready, frames_cmd_valid);
    frames_cmd_alloc            <= '0';
    handshake_in(TbClock, frames_resp_ready, frames_resp_valid);

    -- Reserve other frame by address
    frames_cmd_alloc            <= '1';
    frames_cmd_addr             <= std_logic_vector(unsigned(PT_ADDR) + 7);
    handshake_out(TbClock, frames_cmd_ready, frames_cmd_valid);
    handshake_in(TbClock, frames_resp_ready, frames_resp_valid);

    -- Try to reserve it again, should give other address
    handshake_out(TbClock, frames_cmd_ready, frames_cmd_valid);
    handshake_in(TbClock, frames_resp_ready, frames_resp_valid);
    frames_cmd_alloc            <= '0';

    -- Find arbitrary free frame in given region
    frames_cmd_find             <= '1';
    frames_cmd_region           <= "1";
    handshake_out(TbClock, frames_cmd_ready, frames_cmd_valid);
    handshake_in(TbClock, frames_resp_ready, frames_resp_valid);
    frames_cmd_find             <= '0';


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

end architecture;
