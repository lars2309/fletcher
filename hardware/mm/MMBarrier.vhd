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

entity MMBarrier is
  generic (
    BUS_ADDR_WIDTH              : natural := 64;
    BUS_LEN_WIDTH               : natural := 8;
    MAX_OUTSTANDING             : natural := 31
  );
  port (
    clk                         : in  std_logic;
    reset                       : in  std_logic;
    dirty                       : out std_logic;

    -- Slave write request channel
    slv_wreq_valid              : in  std_logic;
    slv_wreq_ready              : out std_logic;
    slv_wreq_addr               : in  std_logic_vector(BUS_ADDR_WIDTH-1 downto 0);
    slv_wreq_len                : in  std_logic_vector(BUS_LEN_WIDTH-1 downto 0);
    slv_wreq_barrier            : in  std_logic;
    -- Master write request channel
    mst_wreq_valid              : out std_logic;
    mst_wreq_ready              : in  std_logic;
    mst_wreq_addr               : out std_logic_vector(BUS_ADDR_WIDTH-1 downto 0);
    mst_wreq_len                : out std_logic_vector(BUS_LEN_WIDTH-1 downto 0);

    -- Slave response channel
    slv_resp_valid              : out std_logic;
    slv_resp_ready              : in  std_logic := '1';
    slv_resp_ok                 : out std_logic;
    -- Master response channel
    mst_resp_valid              : in  std_logic;
    mst_resp_ready              : out std_logic;
    mst_resp_ok                 : in  std_logic
  );
end MMBarrier;


architecture Behavioral of MMBarrier is
  type reg_type is record
    outstanding : unsigned(log2ceil(MAX_OUTSTANDING) - 1 downto 0);
    barrier     : unsigned(log2ceil(MAX_OUTSTANDING) - 1 downto 0);
  end record;

  signal r : reg_type;
  signal d : reg_type;

begin

  reg_proc: process (clk) is
  begin
    if rising_edge(clk) then
      r <= d;

      if reset = '1' then
        r.outstanding <= (others => '0');
        r.barrier     <= (others => '0');
      end if;
    end if;
  end process;

  comb_proc: process(r,
    slv_wreq_valid, slv_wreq_addr, slv_wreq_len, slv_wreq_barrier,
    mst_wreq_ready, slv_resp_ready, mst_resp_valid, mst_resp_ok
  ) is
    variable v: reg_type;
    variable resp_handshake : boolean;
    variable wreq_handshake : boolean;
  begin
    v := r;

    slv_resp_valid <= mst_resp_valid;
    mst_resp_ready <= slv_resp_ready;
    slv_resp_ok    <= mst_resp_ok;

    mst_wreq_addr  <= slv_wreq_addr;
    mst_wreq_len   <= slv_wreq_len;

    resp_handshake := mst_resp_valid = '1' and slv_resp_ready = '1';

    if v.outstanding = MAX_OUTSTANDING and not resp_handshake then
      -- Reached maximum outstanding write requests, block further write requests.
      slv_wreq_ready <= '0';
      mst_wreq_valid <= '0';
      wreq_handshake := false;
    else
      -- Can accept a write request.
      slv_wreq_ready <= mst_wreq_ready;
      mst_wreq_valid <= slv_wreq_valid;
      wreq_handshake := mst_wreq_ready = '1' and slv_wreq_valid = '1';
    end if;

    if resp_handshake then
      v.outstanding := v.outstanding - 1;
      if v.barrier /= 0 then
        v.barrier := v.barrier - 1;
      end if;
    end if;

    if wreq_handshake then
      v.outstanding := v.outstanding + 1;
      if slv_wreq_barrier = '1' then
        v.barrier := v.outstanding;
      end if;
    end if;

    if v.barrier = 0 then
      dirty <= '0';
    else
      dirty <= '1';
    end if;

    d <= v;
  end process;
end architecture;

