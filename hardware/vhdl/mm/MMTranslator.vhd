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
use work.Streams.all;

entity MMTranslator is
  generic (
    VM_BASE                     : unsigned(ADDR_WIDTH_LIMIT-1 downto 0) := (others => '0');
    PT_ENTRIES_LOG2             : natural := 64/2; -- Default to 64-bit VM address space.
    PAGE_SIZE_LOG2              : natural := 0;
    PREFETCH_LOG2               : natural := 22;
    BUS_ADDR_WIDTH              : natural := 64;
    BUS_LEN_WIDTH               : natural := 8;
    USER_WIDTH                  : natural := 1;
    SLV_SLICE                   : boolean := false;
    MST_SLICE                   : boolean := false
  );
  port (
    clk                         : in  std_logic;
    reset                       : in  std_logic;

    -- Slave request channel
    slv_req_valid               : in  std_logic;
    slv_req_ready               : out std_logic;
    slv_req_addr                : in  std_logic_vector(BUS_ADDR_WIDTH-1 downto 0);
    slv_req_len                 : in  std_logic_vector(BUS_LEN_WIDTH-1 downto 0);
    slv_req_user                : in  std_logic_vector(USER_WIDTH-1 downto 0) := (others => '0');
    -- Master request channel
    mst_req_valid               : out std_logic;
    mst_req_ready               : in  std_logic;
    mst_req_addr                : out std_logic_vector(BUS_ADDR_WIDTH-1 downto 0);
    mst_req_len                 : out std_logic_vector(BUS_LEN_WIDTH-1 downto 0);
    mst_req_user                : out std_logic_vector(USER_WIDTH-1 downto 0);

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
    req_cur     : std_logic;
    req_next    : std_logic;
    do_req_next : std_logic;
    map_cur     : map_type;
    map_next    : map_type;
  end record;

  signal r : reg_type;
  signal d : reg_type;

  constant ABI : nat_array := cumulative((
    2 => USER_WIDTH,
    1 => BUS_LEN_WIDTH,
    0 => BUS_ADDR_WIDTH
  ));

  signal int_slv_req_valid      : std_logic;
  signal int_slv_req_ready      : std_logic;
  signal int_slv_req_addr       : std_logic_vector(BUS_ADDR_WIDTH-1 downto 0);
  signal int_slv_req_len        : std_logic_vector(BUS_LEN_WIDTH-1 downto 0);
  signal int_slv_req_user       : std_logic_vector(USER_WIDTH-1 downto 0);
  signal slv_data               : std_logic_vector(ABI(ABI'high)-1 downto 0);
  signal int_slv_data           : std_logic_vector(ABI(ABI'high)-1 downto 0);

  signal int_mst_req_valid      : std_logic;
  signal int_mst_req_ready      : std_logic;
  signal int_mst_req_addr       : std_logic_vector(BUS_ADDR_WIDTH-1 downto 0);
  signal int_mst_req_len        : std_logic_vector(BUS_LEN_WIDTH-1 downto 0);
  signal int_mst_req_user       : std_logic_vector(USER_WIDTH-1 downto 0);
  signal int_mst_data           : std_logic_vector(ABI(ABI'high)-1 downto 0);
  signal mst_data               : std_logic_vector(ABI(ABI'high)-1 downto 0);
begin

  reg_proc: process (clk) is
  begin
    if rising_edge(clk) then
      r <= d;

      if reset = '1' then
        r.req_cur        <= '0';
        r.req_next       <= '0';
        r.do_req_next    <= '0';
        r.map_cur.valid  <= '0';
        r.map_next.valid <= '0';
      end if;
    end if;
  end process;

  input_slice_gen: if SLV_SLICE generate
  begin
    slice_inst: StreamSlice
      generic map (
        DATA_WIDTH              => int_slv_data'length
      )
      port map (
        clk                     => clk,
        reset                   => reset,
        in_valid                => slv_req_valid,
        in_ready                => slv_req_ready,
        in_data                 => slv_data,
        out_valid               => int_slv_req_valid,
        out_ready               => int_slv_req_ready,
        out_data                => int_slv_data
      );
    slv_data(ABI(1)-1 downto ABI(0)) <= slv_req_addr;
    slv_data(ABI(2)-1 downto ABI(1)) <= slv_req_len;
    slv_data(ABI(3)-1 downto ABI(2)) <= slv_req_user;
    int_slv_req_addr <= int_slv_data(ABI(1)-1 downto ABI(0));
    int_slv_req_len  <= int_slv_data(ABI(2)-1 downto ABI(1));
    int_slv_req_user <= int_slv_data(ABI(3)-1 downto ABI(2));
  end generate;
  no_input_slice_gen: if not SLV_SLICE generate
  begin
    int_slv_req_valid <= slv_req_valid;
    slv_req_ready     <= int_slv_req_ready;
    int_slv_req_addr  <= slv_req_addr;
    int_slv_req_len   <= slv_req_len;
    int_slv_req_user  <= slv_req_user;
  end generate;

  output_slice_gen: if MST_SLICE generate
  begin
    slice_inst: StreamSlice
      generic map (
        DATA_WIDTH              => mst_data'length
      )
      port map (
        clk                     => clk,
        reset                   => reset,
        in_valid                => int_mst_req_valid,
        in_ready                => int_mst_req_ready,
        in_data                 => int_mst_data,
        out_valid               => mst_req_valid,
        out_ready               => mst_req_ready,
        out_data                => mst_data
      );
    int_mst_data(ABI(1)-1 downto ABI(0)) <= int_mst_req_addr;
    int_mst_data(ABI(2)-1 downto ABI(1)) <= int_mst_req_len;
    int_mst_data(ABI(3)-1 downto ABI(2)) <= int_mst_req_user;
    mst_req_addr <= mst_data(ABI(1)-1 downto ABI(0));
    mst_req_len  <= mst_data(ABI(2)-1 downto ABI(1));
    mst_req_user <= mst_data(ABI(3)-1 downto ABI(2));
  end generate;
  no_output_slice_gen: if not MST_SLICE generate
  begin
    mst_req_valid     <= int_mst_req_valid;
    int_mst_req_ready <= mst_req_ready;
    mst_req_addr      <= int_mst_req_addr;
    mst_req_len       <= int_mst_req_len;
    mst_req_user      <= int_mst_req_user;
  end generate;

  comb_proc: process(r, int_mst_req_ready,
      int_slv_req_valid, int_slv_req_addr, int_slv_req_len, int_slv_req_user,
      req_ready, resp_valid, resp_virt, resp_phys, resp_mask) is
    variable v: reg_type;
  begin
    v := r;

    int_mst_req_valid    <= '0';
    int_mst_req_addr     <= (others => 'U');
    int_mst_req_len      <= int_slv_req_len;
    int_mst_req_user     <= int_slv_req_user;

    int_slv_req_ready    <= '0';

    req_valid            <= '0';
    req_addr             <= (others => 'U');

    resp_ready           <= '1';

    -- Handle lookup responses.
    if resp_valid = '1' then
      if v.req_cur = '1' then
        v.req_cur        := '0';

        v.map_cur.valid  := '1';
        v.map_cur.virt   := resp_virt;
        v.map_cur.phys   := resp_phys;
        v.map_cur.mask   := resp_mask;
      else
        v.req_next       := '0';
        v.do_req_next    := '0';

        v.map_next.valid := '1';
        v.map_next.virt  := resp_virt;
        v.map_next.phys  := resp_phys;
        v.map_next.mask  := resp_mask;
      end if;
    end if;

    -- Preemptively request table walk for next page.
    if v.do_req_next = '1' and v.req_next = '0' then
      req_valid          <= '1';
      req_addr           <= slv(u(v.map_cur.virt) + u(not v.map_cur.mask) + 1);
      if req_ready = '1' then
        v.req_next       := '1';
      end if;
    end if;

    -- Translate bus requests.
    if int_slv_req_valid = '1' then
      if u(int_slv_req_addr and VM_MASK) /= VM_BASE then
        -- Pass through address not within virtual address space.
        int_mst_req_addr  <= int_slv_req_addr;
        int_mst_req_valid <= '1';
        int_slv_req_ready <= int_mst_req_ready;
      elsif v.map_cur.valid = '1'
        and (int_slv_req_addr and v.map_cur.mask) = v.map_cur.virt
      then
        -- Match on stored current map
        int_mst_req_addr  <= v.map_cur.phys or (int_slv_req_addr and not v.map_cur.mask);
        int_mst_req_valid <= '1';
        int_slv_req_ready <= int_mst_req_ready;

        -- Close to edge of current map? -> Look up next page.
        -- When current translation is the highest page in the current mapping.
        -- Create new mask with '1' bits indicating the address bits that have
        -- to be '1' for the address to be in the highest page of the current
        -- mapping. Then check whether these bits are indeed '1' (inverted check).
        if v.map_next.valid = '0'
          and ( 0 = (
            align_beq(u(not v.map_cur.mask), PREFETCH_LOG2) and u(not int_slv_req_addr) ) )
        then
          --v.do_req_next  := '1';
        end if;

      elsif v.map_next.valid = '1'
        and (int_slv_req_addr and v.map_next.mask) = v.map_next.virt
      then
        -- Match on next stored map, move to current map.
        v.map_cur         := v.map_next;
        v.map_next.valid  := '0';
        int_mst_req_addr  <= v.map_cur.phys or (int_slv_req_addr and not v.map_cur.mask);
        int_mst_req_valid <= '1';
        int_slv_req_ready <= int_mst_req_ready;

      elsif v.req_cur = '0' and v.do_req_next = '0' then
        -- No match, request table walk.
        -- Check on do_req_next is required to prevent this from changing
        -- an ongoing request.
        req_valid        <= '1';
        req_addr         <= int_slv_req_addr;
        if req_ready = '1' then
          v.req_cur      := '1';
        end if;
      end if;
    end if;

    d <= v;
  end process;
end architecture;

