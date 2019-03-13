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

entity MMTranslator is
  generic (
    VM_BASE                     : unsigned(ADDR_WIDTH_LIMIT-1 downto 0);
    PT_ENTRIES_LOG2             : natural;
    PAGE_SIZE_LOG2              : natural;
    BUS_ADDR_WIDTH              : natural := 64;
    BUS_LEN_WIDTH               : natural := 8
  );
  port (
    clk                         : in  std_logic;
    reset                       : in  std_logic;

    -- Slave request channel
    slv_req_valid               : in  std_logic;
    slv_req_ready               : out std_logic;
    slv_req_addr                : in  std_logic_vector(BUS_ADDR_WIDTH-1 downto 0);
    slv_req_len                 : in  std_logic_vector(BUS_LEN_WIDTH-1 downto 0);
    -- Master request channel
    mst_req_valid               : out std_logic;
    mst_req_ready               : in  std_logic;
    mst_req_addr                : out std_logic_vector(BUS_ADDR_WIDTH-1 downto 0);
    mst_req_len                 : out std_logic_vector(BUS_LEN_WIDTH-1 downto 0);

    -- Translate request channel
    req_valid                   : out std_logic;
    req_ready                   : in  std_logic;
    req_addr                    : out std_logic_vector(BUS_ADDR_WIDTH-1 downto 0);
    -- Translate response channel
    resp_valid                  : in  std_logic;
    resp_ready                  : out std_logic;
    resp_virt                   : in  std_logic_vector(BUS_ADDR_WIDTH-1 downto 0);
    resp_phys                   : in  std_logic_vector(BUS_ADDR_WIDTH-1 downto 0);
    resp_mask                   : in  std_logic_vector(BUS_ADDR_WIDTH-1 downto 0)
  );
end MMTranslator;


architecture Behavioral of MMTranslator is
  constant VM_SIZE_LOG2 : natural := PAGE_SIZE_LOG2 + PT_ENTRIES_LOG2 * 2;
  constant VM_MASK      : std_logic_vector(BUS_ADDR_WIDTH-1 downto 0)
      := slv(shift_left(unsigned(to_signed(-1, BUS_ADDR_WIDTH)), VM_SIZE_LOG2));

  type map_type is record
    valid : std_logic;
    virt  : std_logic_vector(BUS_ADDR_WIDTH-1 downto 0);
    phys  : std_logic_vector(BUS_ADDR_WIDTH-1 downto 0);
    mask  : std_logic_vector(BUS_ADDR_WIDTH-1 downto 0);
  end record;

  type reg_type is record
    req_cur  : std_logic;
    req_next : std_logic;
    map_cur  : map_type;
    map_next : map_type;
  end record;

  signal r : reg_type;
  signal d : reg_type;

begin

  reg_proc: process (clk) is
  begin
    if rising_edge(clk) then
      r <= d;

      if reset = '1' then
        r.req_cur        <= '0';
        r.req_next       <= '0';
        r.map_cur.valid  <= '0';
        r.map_next.valid <= '0';
      end if;
    end if;
  end process;

  comb_proc: process(r, mst_req_ready, slv_req_valid, slv_req_addr, slv_req_len,
      req_ready, resp_valid, resp_virt, resp_phys, resp_mask) is
    variable v: reg_type;
  begin
    v := r;

    mst_req_valid        <= '0';
    mst_req_addr         <= (others => 'U');
    mst_req_len          <= slv_req_len;

    slv_req_ready        <= '0';

    req_valid            <= '0';
    req_addr             <= (others => 'U');

    resp_ready           <= '1';

    if resp_valid = '1' then
      if v.req_cur = '1' then
        v.req_cur        := '0';

        v.map_cur.valid  := '1';
        v.map_cur.virt   := resp_virt;
        v.map_cur.phys   := resp_phys;
        v.map_cur.mask   := resp_mask;
      else
        v.map_next.valid := '1';
        v.map_next.virt  := resp_virt;
        v.map_next.phys  := resp_phys;
        v.map_next.mask  := resp_mask;
      end if;
    end if;

    if slv_req_valid = '1' then
      if u(slv_req_addr and VM_MASK) /= VM_BASE then
        -- Pass through address not within virtual address space.
        mst_req_addr     <= slv_req_addr;
        mst_req_valid    <= '1';
        slv_req_ready    <= mst_req_ready;
      elsif v.map_cur.valid = '1'
        and (slv_req_addr and v.map_cur.mask) = v.map_cur.virt
      then
        -- Match on stored current map
        mst_req_addr     <= v.map_cur.phys or (slv_req_addr and not v.map_cur.mask);
        mst_req_valid    <= '1';
        slv_req_ready    <= mst_req_ready;

      elsif v.map_next.valid = '1'
        and (slv_req_addr and v.map_cur.mask) = v.map_cur.virt
      then
        -- Match on next stored map, move to current map.
        v.map_cur        := v.map_next;
        v.map_next.valid := '0';
        mst_req_addr     <= v.map_cur.phys or (slv_req_addr and not v.map_cur.mask);
        mst_req_valid    <= '1';
        slv_req_ready    <= mst_req_ready;

      elsif v.req_cur = '0' then
        -- No match, request table walk.
        req_valid        <= '1';
        req_addr         <= slv_req_addr;
        if req_ready = '1' then
          v.req_cur      := '1';
        end if;
      end if;
    end if;

    d <= v;
  end process;
end architecture;

