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
    MAX_OUTSTANDING_LOG2        : natural := 0
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

  constant ABI : nat_array := cumulative((
    3 => 1,
    2 => USER_WIDTH,
    1 => BUS_LEN_WIDTH,
    0 => BUS_ADDR_WIDTH
  ));

  type request_type is record
    valid  : std_logic;
    ready  : std_logic;
    addr   : std_logic_vector(BUS_ADDR_WIDTH-1 downto 0);
    len    : std_logic_vector(BUS_LEN_WIDTH-1 downto 0);
    user   : std_logic_vector(USER_WIDTH-1 downto 0);
    virt   : std_logic;
    concat : std_logic_vector(ABI(ABI'high)-1 downto 0);
  end record;

  function REQUEST_SER(x : request_type)
      return request_type is
    variable t : request_type;
  begin
    t := x;
    t.concat(ABI(1)-1 downto ABI(0)) := x.addr;
    t.concat(ABI(2)-1 downto ABI(1)) := x.len;
    t.concat(ABI(3)-1 downto ABI(2)) := x.user;
    t.concat(ABI(3))                 := x.virt;
    return t;
  end REQUEST_SER;

  function REQUEST_DESER(x : request_type)
      return request_type is
    variable t : request_type;
  begin
    t      := x;
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
  signal req_queue_in        : request_type;
  signal req_queue_out       : request_type;

  signal req_enable          : std_logic;
begin

  req_proc : process(int_slv_req, req_queue_in, req_queue_out, int_mst_req,
      req_ready, resp_valid, resp_virt, resp_phys, resp_mask) is
  begin
    -- Make request if necessary.
    req_queue_in.concat      <= int_slv_req.concat;
    req_queue_in             <= REQUEST_DESER(req_queue_in);
    req_addr                 <= int_slv_req.addr;
    if int_slv_req.valid = '1' then
      if u(int_slv_req.addr and VM_MASK) = VM_BASE then
        -- Address is in virtual space, request translation.
        req_enable           <= '1';
        req_queue_in.virt    <= '1';
      else
        -- Address is outside virtual space, do not request translation.
        req_enable           <= '0';
        req_queue_in.virt    <= '0';
      end if;
    end if;

    -- Wait for response if necessary.
    int_mst_req.concat       <= req_queue_out.concat;
    int_mst_req              <= REQUEST_DESER(int_mst_req);
    int_mst_req.virt         <= '0';
    int_mst_req.valid        <= '0';
    req_queue_out.ready      <= '0';
    resp_ready               <= '0';
    if req_queue_out.valid = '1' then
      if req_queue_out.virt = '1' then
        -- This request needs a translation response.
        int_mst_req.valid    <= resp_valid;
        req_queue_out.ready  <= resp_valid and int_mst_req.ready;
        resp_ready           <= int_mst_req.ready;
        int_mst_req.addr     <= resp_phys or (req_queue_out.addr and not resp_mask);
      else
        -- This request can be passed on as is.
        int_mst_req.valid    <= '1';
        req_queue_out.ready  <= '1';
      end if;
    end if;
  end process;

  sync_fifo_req : StreamSync
    generic map (
      NUM_INPUTS                  => 1,
      NUM_OUTPUTS                 => 2
    )
    port map (
      clk                         => clk,
      reset                       => reset,
      in_valid                    => int_slv_req.valid,
      in_ready                    => int_slv_req.ready,
      out_valid(0)                => req_queue_in.valid,
      out_valid(1)                => req_valid,
      out_ready(0)                => req_queue_in.ready,
      out_ready(1)                => req_ready,
      out_enable(0)               => '1',
      out_enable(1)               => req_enable
    );

  req_queue_in        <= REQUEST_SER(req_queue_in);
  req_queue_out       <= REQUEST_DESER(req_queue_out);
  resp_queue : StreamFIFO
    generic map (
      DEPTH_LOG2                  => OUTSTANDING_LOG2,
      DATA_WIDTH                  => ABI(ABI'high)
    )
    port map (
      in_clk                      => clk,
      in_reset                    => reset,
      out_clk                     => clk,
      out_reset                   => reset,
      in_valid                    => req_queue_in.valid,
      in_ready                    => req_queue_in.ready,
      in_data                     => req_queue_in.concat,
      out_valid                   => req_queue_out.valid,
      out_ready                   => req_queue_out.ready,
      out_data                    => req_queue_out.concat
    );

  slv_req.valid  <= slv_req_valid;
  slv_req_ready  <= slv_req.ready;
  slv_req.addr   <= slv_req_addr;
  slv_req.len    <= slv_req_len;
  slv_req.user   <= slv_req_user;
  slv_req        <= REQUEST_SER(slv_req);
  int_slv_req    <= REQUEST_DESER(int_slv_req);
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

  mst_req_valid  <= mst_req.valid;
  mst_req.ready  <= mst_req_ready;
  mst_req_addr   <= mst_req.addr;
  mst_req_len    <= mst_req.len;
  mst_req_user   <= mst_req.user;
  mst_req        <= REQUEST_DESER(mst_req);
  int_mst_req    <= REQUEST_SER(int_mst_req);
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

end architecture;

