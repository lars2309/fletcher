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
    SLV_SLICES                  : natural := 0;
    MST_SLICES                  : natural := 0;
    MAX_OUTSTANDING             : positive := 1;
    CACHE_SIZE                  : natural := 1
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

  type cache_type is array (CACHE_SIZE-1 downto 0) of map_type;
  signal cache  : cache_type;
  signal dcache : cache_type;

  constant ABI : nat_array := cumulative((
    3 => 1,
    2 => USER_WIDTH,
    1 => BUS_LEN_WIDTH,
    0 => BUS_ADDR_WIDTH
  ));

  type request_d_type is record
    addr   : std_logic_vector(BUS_ADDR_WIDTH-1 downto 0);
    len    : std_logic_vector(BUS_LEN_WIDTH-1 downto 0);
    user   : std_logic_vector(USER_WIDTH-1 downto 0);
    virt   : std_logic;
  end record;

  type request_type is record
    valid  : std_logic;
    ready  : std_logic;
    d      : request_d_type;
    concat : std_logic_vector(ABI(ABI'high)-1 downto 0);
  end record;

  function REQUEST_SER(x : request_type)
      return std_logic_vector is
    variable t : std_logic_vector(ABI(ABI'high)-1 downto 0);
  begin
    t(ABI(1)-1 downto ABI(0)) := x.d.addr;
    t(ABI(2)-1 downto ABI(1)) := x.d.len;
    t(ABI(3)-1 downto ABI(2)) := x.d.user;
    t(ABI(3))                 := x.d.virt;
    return t;
  end REQUEST_SER;

  function REQUEST_DESER(x : request_type)
      return request_d_type is
    variable t : request_d_type;
  begin
    t.addr := x.concat(ABI(1)-1 downto ABI(0));
    t.len  := x.concat(ABI(2)-1 downto ABI(1));
    t.user := x.concat(ABI(3)-1 downto ABI(2));
    t.virt := x.concat(ABI(3));
    return t;
  end REQUEST_DESER;

  signal slv_req             : request_type;
  signal mst_req             : request_type;
  signal int_slv_req         : request_type;
  signal int_mst_req         : request_type;
  signal cache_result_in     : request_type;
  signal cache_result_out    : request_type;
  signal req_queue_in        : request_type;
  signal req_queue_out       : request_type;

begin

  clk_proc : process(clk) is
  begin
    if rising_edge(clk) then
      cache <= dcache;
      if reset = '1' then
        for cidx in 0 to CACHE_SIZE-1 loop
          cache(cidx).valid <= '0';
        end loop;
      end if;
    end if;
  end process;

  req_proc : process(int_slv_req, req_queue_out, int_mst_req, cache_result_in,
      req_ready, resp_valid, resp_virt, resp_phys, resp_mask, cache) is
    variable lcache    : cache_type;
    variable in_cache  : boolean;
    variable cidx_m    : natural;
    variable handshake : std_logic;
  begin
    lcache   := cache;
    in_cache := false;

    -- Make request if necessary.
    cache_result_in.valid    <= int_slv_req.valid;
    int_slv_req.ready        <= cache_result_in.ready;
    cache_result_in.d        <= int_slv_req.d;
    if (int_slv_req.d.addr and VM_MASK) = slv(resize(VM_BASE, VM_MASK'length)) then
      -- Address is in virtual space, request translation.

      -- Check cache.
      for cidx in 0 to CACHE_SIZE-1 loop
        if cache(cidx).valid = '1'
          and (int_slv_req.d.addr and cache(cidx).mask) = cache(cidx).virt
        then
          in_cache := true;
          cidx_m   := cidx;
          exit;
        end if;
      end loop;

      if in_cache then
        -- Mark new address as a physical address.
        cache_result_in.d.virt   <= '0';
        cache_result_in.d.addr <= cache(cidx_m).phys or (int_slv_req.d.addr and not cache(cidx_m).mask);
      else
        -- Not found in cache, forward request for page table walk.
        cache_result_in.d.virt   <= '1';
      end if;
    else
      -- Address is outside virtual space, do not request translation.
      cache_result_in.d.virt     <= '0';
    end if;

    -- Wait for response if necessary.
    int_mst_req.d            <= req_queue_out.d;
    int_mst_req.d.virt       <= '0';
    int_mst_req.valid        <= '0';
    resp_ready               <= '0';
    handshake                := '0';
    if req_queue_out.valid = '1' then
      if req_queue_out.d.virt = '1' then
        -- This request needs a translation response.
        handshake            := resp_valid and int_mst_req.ready;
        int_mst_req.valid    <= resp_valid;
        resp_ready           <= int_mst_req.ready;
        int_mst_req.d.addr   <= resp_phys or (req_queue_out.d.addr and not resp_mask);

        -- Cache the response.
        if handshake = '1' then
          -- Shift all cached responses to make room.
          for cidx in CACHE_SIZE-1 downto 1 loop
            lcache(cidx)     := lcache(cidx-1);
          end loop;
          if CACHE_SIZE /= 0 then
            -- Save response at position 0.
            lcache(0).valid    := '1';
            lcache(0).virt     := resp_virt and resp_mask;
            lcache(0).phys     := resp_phys and resp_mask;
            lcache(0).mask     := resp_mask;
          end if;
        end if;
      else
        -- This request can be passed on as is.
        int_mst_req.valid    <= '1';
        handshake            := int_mst_req.ready;
      end if;
    end if;
    req_queue_out.ready      <= handshake;

    dcache <= lcache;
  end process;


  -- This slice is needed to latch the output of the cache lookup, before valid
  -- is asserted on the request channel. Since the cache contents can change
  -- concurrently, changing the data while valid is hish, which is illegal.
  cache_slice : StreamSlice
    generic map (
      DATA_WIDTH                  => cache_result_in.concat'length
    )
    port map (
      clk                         => clk,
      reset                       => reset,
      in_valid                    => cache_result_in.valid,
      in_ready                    => cache_result_in.ready,
      in_data                     => cache_result_in.concat,
      out_valid                   => cache_result_out.valid,
      out_ready                   => cache_result_out.ready,
      out_data                    => cache_result_out.concat
    );
  cache_result_in.concat     <= REQUEST_SER(cache_result_in);
  cache_result_out.d         <= REQUEST_DESER(cache_result_out);
  req_queue_in.d             <= cache_result_out.d;
  req_addr                   <= cache_result_out.d.addr;

  sync_fifo_req : StreamSync
    generic map (
      NUM_INPUTS                  => 1,
      NUM_OUTPUTS                 => 2
    )
    port map (
      clk                         => clk,
      reset                       => reset,
      in_valid(0)                 => cache_result_out.valid,
      in_ready(0)                 => cache_result_out.ready,
      out_valid(0)                => req_queue_in.valid,
      out_valid(1)                => req_valid,
      out_ready(0)                => req_queue_in.ready,
      out_ready(1)                => req_ready,
      out_enable(0)               => '1',
      out_enable(1)               => req_queue_in.d.virt
    );

  resp_queue : StreamBuffer
    generic map (
      MIN_DEPTH                   => MAX_OUTSTANDING,
      DATA_WIDTH                  => ABI(ABI'high)
    )
    port map (
      clk                         => clk,
      reset                       => reset,
      in_valid                    => req_queue_in.valid,
      in_ready                    => req_queue_in.ready,
      in_data                     => req_queue_in.concat,
      out_valid                   => req_queue_out.valid,
      out_ready                   => req_queue_out.ready,
      out_data                    => req_queue_out.concat
    );
  req_queue_in.concat        <= REQUEST_SER(req_queue_in);
  req_queue_out.d            <= REQUEST_DESER(req_queue_out);

  slv_req.valid    <= slv_req_valid;
  slv_req_ready    <= slv_req.ready;
  slv_req.d.addr   <= slv_req_addr;
  slv_req.d.len    <= slv_req_len;
  slv_req.d.user   <= slv_req_user;

  slv_slice: StreamBuffer
    generic map (
      MIN_DEPTH               => SLV_SLICES,
      DATA_WIDTH              => ABI(ABI'high)
    )
    port map (
      clk                     => clk,
      reset                   => reset,
      in_valid                => slv_req.valid,
      in_ready                => slv_req.ready,
      in_data                 => slv_req.concat,
      out_valid               => int_slv_req.valid,
      out_ready               => int_slv_req.ready,
      out_data                => int_slv_req.concat
    );
  slv_req.concat             <= REQUEST_SER(slv_req);
  int_slv_req.d              <= REQUEST_DESER(int_slv_req);

  mst_slice: StreamBuffer
    generic map (
      MIN_DEPTH               => MST_SLICES,
      DATA_WIDTH              => ABI(ABI'high)
    )
    port map (
      clk                     => clk,
      reset                   => reset,
      in_valid                => int_mst_req.valid,
      in_ready                => int_mst_req.ready,
      in_data                 => int_mst_req.concat,
      out_valid               => mst_req.valid,
      out_ready               => mst_req.ready,
      out_data                => mst_req.concat
    );
  int_mst_req.concat         <= REQUEST_SER(int_mst_req);
  mst_req.d                  <= REQUEST_DESER(mst_req);

  mst_req_valid  <= mst_req.valid;
  mst_req.ready  <= mst_req_ready;
  mst_req_addr   <= mst_req.d.addr;
  mst_req_len    <= mst_req.d.len;
  mst_req_user   <= mst_req.d.user;

end architecture;

