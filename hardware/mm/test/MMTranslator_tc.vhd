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
use work.UtilInt_pkg.all;
use work.UtilConv_pkg.all;
use work.MM_pkg.all;
use work.MM_tc_params.all;

entity MMTranslator_tc is
end MMTranslator_tc;

architecture tb of MMTranslator_tc is
  signal bus_clk                : std_logic                                               := '0';
  signal acc_clk                : std_logic                                               := '0';
  signal bus_reset              : std_logic                                               := '0';
  signal acc_reset              : std_logic                                               := '0';
  -- Slave request channel
  signal slv_req_valid          : std_logic;
  signal slv_req_ready          : std_logic;
  signal slv_req_addr           : std_logic_vector(BUS_ADDR_WIDTH-1 downto 0);
  signal slv_req_len            : std_logic_vector(BUS_LEN_WIDTH-1 downto 0);
  -- Master request channel
  signal mst_req_valid          : std_logic;
  signal mst_req_ready          : std_logic;
  signal mst_req_addr           : std_logic_vector(BUS_ADDR_WIDTH-1 downto 0);
  signal mst_req_len            : std_logic_vector(BUS_LEN_WIDTH-1 downto 0);

  -- Translate request channel
  signal req_valid              : std_logic;
  signal req_ready              : std_logic;
  signal req_addr               : std_logic_vector(BUS_ADDR_WIDTH-1 downto 0);
  -- Translate response channel
  signal resp_valid             : std_logic;
  signal resp_ready             : std_logic;
  signal resp_virt              : std_logic_vector(BUS_ADDR_WIDTH-1 downto 0);
  signal resp_phys              : std_logic_vector(BUS_ADDR_WIDTH-1 downto 0);
  signal resp_mask              : std_logic_vector(BUS_ADDR_WIDTH-1 downto 0);

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

    slv_req_valid               <= '0';
    mst_req_ready               <= '1';
    req_ready                   <= '0';
    resp_valid                  <= '0';

    wait until rising_edge(TbClock);
    TbReset                     <= '0';

    wait until rising_edge(TbClock);

    -- Address request
    slv_req_addr                <= slv(to_unsigned(314159*(BUS_DATA_WIDTH/BYTE_SIZE), BUS_ADDR_WIDTH));
    slv_req_valid               <= '1';
    -- Accept translate request
    handshake_in(TbClock, req_ready, req_valid);

    -- Provide translate response
    resp_mask                   <= std_logic_vector(shift_left(to_signed(-1, BUS_ADDR_WIDTH), PAGE_SIZE_LOG2));
    wait until rising_edge(TbClock);
    resp_phys                   <= slv(to_unsigned(6626070*(BUS_DATA_WIDTH/BYTE_SIZE), BUS_ADDR_WIDTH)) and resp_mask;
    resp_virt                   <= slv(to_unsigned(314159*(BUS_DATA_WIDTH/BYTE_SIZE), BUS_ADDR_WIDTH)) and resp_mask;
    handshake_out(TbClock, resp_ready, resp_valid);
    resp_phys                   <= (others => 'U');
    resp_virt                   <= (others => 'U');
    -- Address request should get accepted
    handshake_out(TbClock, slv_req_ready, slv_req_valid);

    wait until rising_edge(TbClock);

    -- Write request in same page
    slv_req_addr                <= slv(unsigned(slv_req_addr and resp_mask) + 2**PAGE_SIZE_LOG2 - (BUS_DATA_WIDTH/BYTE_SIZE));
    handshake_out(TbClock, slv_req_ready, slv_req_valid);

    -- Write request in next page
    slv_req_addr                <= slv(unsigned(slv_req_addr and resp_mask) + 2**PAGE_SIZE_LOG2);
    slv_req_valid               <= '1';
    -- Accept translate request
    handshake_in(TbClock, req_ready, req_valid);

    wait until rising_edge(TbClock);
    -- Provide translate response (physical on second page)
    resp_phys                   <= slv(to_unsigned(2**PAGE_SIZE_LOG2, BUS_ADDR_WIDTH)) and resp_mask;
    resp_virt                   <= slv_req_addr and resp_mask;
    handshake_out(TbClock, resp_ready, resp_valid);
    resp_phys                   <= (others => 'U');
    resp_virt                   <= (others => 'U');
    handshake_out(TbClock, slv_req_ready, slv_req_valid);

    wait until rising_edge(TbClock);

    TbSimEnded                  <= '1';

    report "END OF TEST"  severity note;

    wait;

  end process;

  transl_inst : MMTranslator
    generic map (
      VM_BASE                   => VM_BASE,
      PT_ENTRIES_LOG2           => PT_ENTRIES_LOG2,
      PAGE_SIZE_LOG2            => PAGE_SIZE_LOG2,
      BUS_ADDR_WIDTH            => BUS_ADDR_WIDTH,
      BUS_LEN_WIDTH             => BUS_LEN_WIDTH
    )
    port map (
      clk                       => bus_clk,
      reset                     => bus_reset,

      -- Slave request channel
      slv_req_valid             => slv_req_valid,
      slv_req_ready             => slv_req_ready,
      slv_req_addr              => slv_req_addr,
      slv_req_len               => slv_req_len,
      -- Master request channel
      mst_req_valid             => mst_req_valid,
      mst_req_ready             => mst_req_ready,
      mst_req_addr              => mst_req_addr,
      mst_req_len               => mst_req_len,

      -- Translate request channel
      req_valid                 => req_valid,
      req_ready                 => req_ready,
      req_addr                  => req_addr,
      -- Translate response channel
      resp_valid                => resp_valid,
      resp_ready                => resp_ready,
      resp_virt                 => resp_virt,
      resp_phys                 => resp_phys,
      resp_mask                 => resp_mask
    );


end architecture;
