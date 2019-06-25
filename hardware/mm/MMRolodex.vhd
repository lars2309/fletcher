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
use work.UtilRam_pkg.all;
use work.MM_pkg.all;

entity MMRolodex is
  generic (
    MAX_ENTRIES                 : natural;
    ENTRY_WIDTH                 : natural
  );
  port (
    clk                         : in  std_logic;
    reset                       : in  std_logic;

    entry_valid                 : out std_logic;
    entry_ready                 : in  std_logic;
    entry_mark                  : in  std_logic;
    entry                       : out std_logic_vector(ENTRY_WIDTH-1 downto 0);
    entry_marked                : out std_logic;

    insert_valid                : in  std_logic;
    insert_ready                : out std_logic;
    insert_entry                : in  std_logic_vector(ENTRY_WIDTH-1 downto 0);

    delete_valid                : in  std_logic;
    delete_ready                : out std_logic;
    delete_entry                : in  std_logic_vector(ENTRY_WIDTH-1 downto 0)
  );
end MMRolodex;


architecture Behavioral of MMRolodex is
  type state_type is (RESET_ST, IDLE, DEL_SEARCH, DEL_SHIFT);

  type reg_type is record
    state                       : state_type;
    idx                         : unsigned(log2ceil(MAX_ENTRIES+1)-1 downto 0);
    mark                        : unsigned(log2ceil(MAX_ENTRIES+1)-1 downto 0);
    marked                      : std_logic;
    entries                     : unsigned(log2ceil(MAX_ENTRIES+1)-1 downto 0);
    needle                      : std_logic_vector(ENTRY_WIDTH-1 downto 0);
    r_valid                     : std_logic;
  end record;

  signal w_addr, r_addr         : std_logic_vector(log2ceil(MAX_ENTRIES)-1 downto 0);
  signal w_en                   : std_logic;
  signal w_data, r_data         : std_logic_vector(ENTRY_WIDTH-1 downto 0);

  signal r, d                   : reg_type;

begin

  process (clk) begin
    if rising_edge(clk) then
      if reset = '1' then
        r.state          <= RESET_ST;
        r.idx            <= (others => '0');
        r.entries        <= (others => '0');
        r.marked         <= '0';
        r.r_valid        <= '0';
      else
        r <= d;
      end if;
    end if;
  end process;

  process (r, r_data, entry_ready, entry_mark,
           insert_valid, insert_entry, delete_valid, delete_entry) is
    variable v : reg_type;
  begin
    v := r;

    w_addr       <= (others => 'U');
    w_data       <= (others => 'U');
    w_en         <= '0';

    entry_valid  <= '0';
    insert_ready <= '0';
    delete_ready <= '0';
    entry        <= r_data;
    entry_marked <= v.marked;

    case v.state is

    when RESET_ST =>
      v.state       := IDLE;

    when IDLE =>
      if v.entries /= 0 then
        entry_valid  <= v.r_valid;
      else
        entry_valid  <= '0';
      end if;
      v.r_valid      := '1';
      insert_ready   <= '1';
      delete_ready   <= '1';
      w_addr         <= slv(resize(v.entries, w_addr'length));
      w_data         <= insert_entry;
      if entry_mark = '1' then
        v.mark       := v.idx;
      end if;
      if insert_valid = '1' then
        w_en         <= '1';
        v.r_valid    := '0';
        v.marked     := '0';
        v.idx        := v.entries;
        v.entries    := v.entries + 1;
      end if;
      if entry_ready = '1' then
        v.idx        := v.idx + 1;
        if v.idx = v.entries then
          v.idx      := (others => '0');
        end if;
        if v.idx = v.mark then
          v.marked   := '1';
        end if;
      end if;
      if delete_valid = '1' and v.entries /= 0 then
        v.needle     := delete_entry;
        v.idx        := (others => '0');
        v.state      := DEL_SEARCH;
      end if;

    when DEL_SEARCH =>
      if r_data = v.needle then
        v.state      := DEL_SHIFT;
      end if;
      v.idx          := v.idx + 1;
      if v.idx = v.entries then
        v.idx        := (others => '0');
        v.entries    := v.entries - 1;
        v.state      := IDLE;
      end if;

    when DEL_SHIFT =>
      w_addr         <= slv(v.idx - 1);
      w_data         <= r_data;
      w_en           <= '1';
      v.r_valid      := '0';
      v.idx          := v.idx + 1;
      if v.idx = v.entries then
        v.idx        := (others => '0');
        v.entries    := v.entries - 1;
        v.state      := IDLE;
      end if;

    when others =>
    end case;

    r_addr       <= slv(resize(v.idx, r_addr'length));
    d <= v;
  end process;


  rolodex_mem : UtilRam1R1W
    generic map (
      -- Width of a data word.
      WIDTH                       => ENTRY_WIDTH,
      -- Depth of the memory as log2(depth in words).
      DEPTH_LOG2                  => log2ceil(MAX_ENTRIES)
    )
    port map (
      w_clk                       => clk,
      w_ena                       => w_en,
      w_addr                      => w_addr,
      w_data                      => w_data,

      r_clk                       => clk,
      r_addr                      => r_addr,
      r_data                      => r_data
    );
end architecture;

