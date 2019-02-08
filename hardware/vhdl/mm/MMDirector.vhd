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

entity MMDirector is
  generic (
    PAGE_SIZE_LOG2              : natural;
    MEM_REGIONS                 : natural;
    MEM_SIZES                   : nat_array;
    MEM_MAP_BASE                : unsigned(ADDR_WIDTH_LIMIT-1 downto 0);
    MEM_MAP_SIZE_LOG2           : natural;
    PT_ADDR                     : unsigned(ADDR_WIDTH_LIMIT-1 downto 0);
    PT_ENTRIES_LOG2             : natural;
    PTE_BITS                    : natural;

    ---------------------------------------------------------------------------
    -- Bus metrics and configuration
    ---------------------------------------------------------------------------
    -- Bus address width.
    BUS_ADDR_WIDTH              : natural := 64;

    -- Bus burst length width.
    BUS_LEN_WIDTH               : natural := 8;

    -- Bus data width.
    BUS_DATA_WIDTH              : natural := 512;

    -- Bus strobe width.
    BUS_STROBE_WIDTH            : natural := 512/BYTE_SIZE;

    -- Number of beats in a burst step.
    BUS_BURST_STEP_LEN          : natural := 4;

    -- Maximum number of beats in a burst.
    BUS_BURST_MAX_LEN           : natural := 16
  );
  port (
    clk                         : in  std_logic;
    reset                       : in  std_logic;
    cmd_region                  : in  std_logic_vector(log2ceil(MEM_REGIONS)-1 downto 0);
    cmd_addr                    : in  std_logic_vector(BUS_ADDR_WIDTH-1 downto 0);
    cmd_free                    : in  std_logic;
    cmd_alloc                   : in  std_logic;
    cmd_realloc                 : in  std_logic;
    cmd_valid                   : in  std_logic;
    cmd_ready                   : out std_logic;

    resp_addr                   : out std_logic_vector(BUS_ADDR_WIDTH-1 downto 0);
    resp_success                : out std_logic;
    resp_valid                  : out std_logic;
    resp_ready                  : in  std_logic;

    ---------------------------------------------------------------------------
    -- Bus write channels
    ---------------------------------------------------------------------------
    -- Request channel
    bus_wreq_valid              : out std_logic;
    bus_wreq_ready              : in  std_logic;
    bus_wreq_addr               : out std_logic_vector(BUS_ADDR_WIDTH-1 downto 0);
    bus_wreq_len                : out std_logic_vector(BUS_LEN_WIDTH-1 downto 0);

    -- Data channel             
    bus_wdat_valid              : out std_logic;
    bus_wdat_ready              : in  std_logic;
    bus_wdat_data               : out std_logic_vector(BUS_DATA_WIDTH-1 downto 0);
    bus_wdat_strobe             : out std_logic_vector(BUS_STROBE_WIDTH-1 downto 0);
    bus_wdat_last               : out std_logic;

    -- Read address channel
    bus_rreq_addr               : out std_logic_vector(BUS_ADDR_WIDTH-1 downto 0);
    bus_rreq_len                : out std_logic_vector(BUS_LEN_WIDTH-1 downto 0);
    bus_rreq_valid              : out std_logic;
    bus_rreq_ready              : in  std_logic;

    -- Read data channel
    bus_rdat_data               : in  std_logic_vector(BUS_DATA_WIDTH-1 downto 0);
    bus_rdat_last               : in  std_logic;
    bus_rdat_valid              : in  std_logic;
    bus_rdat_ready              : out std_logic
  );
end MMDirector;


architecture Behavioral of MMDirector is
  constant PT_SIZE              : natural := 2**(PT_ENTRIES_LOG2 + log2ceil( (PTE_BITS+BYTE_SIZE-1) / BYTE_SIZE))
  constant PT_PER_FRAME         : natural := 2**(PAGE_SIZE_LOG2 - PT_ENTRIES_LOG2 - log2ceil( (PTE_BITS+BYTE_SIZE-1) / BYTE_SIZE));

  function PAGE_OFFSET (addr : unsigned(BUS_ADDR_WIDTH-1 downto 0))
                    return natural is
  begin
    return to_integer(unsigned(addr(PAGE_SIZE_LOG2-1 downto 0)));
  end PAGE_OFFSET;

  function PAGE_BASE (addr : std_logic_vector(BUS_ADDR_WIDTH-1 downto 0))
                    return std_logic_vector is
    variable base : std_logic_vector(BUS_ADDR_WIDTH-1 downto 0) := (others => '0');
  begin
    base(BUS_ADDR_WIDTH-1 downto PAGE_SIZE_LOG2) := addr(BUS_ADDR_WIDTH-1 downto PAGE_SIZE_LOG2);
    return base;
  end PAGE_BASE;

  function PAGE_BASE (addr : unsigned(BUS_ADDR_WIDTH-1 downto 0))
                    return std_logic_vector is
  begin
    return PAGE_BASE(std_logic_vector(addr));
  end PAGE_BASE;

  function PAGE_BASE (addr : unsigned(BUS_ADDR_WIDTH-1 downto 0))
                    return unsigned is
  begin
    return unsigned(PAGE_BASE(std_logic_vector(addr)));
  end PAGE_BASE;

  signal frames_cmd_region      : std_logic_vector(log2ceil(MEM_REGIONS)-1 downto 0);
  signal frames_cmd_addr        : std_logic_vector(BUS_ADDR_WIDTH-1 downto 0);
  signal frames_cmd_free        : std_logic;
  signal frames_cmd_alloc       : std_logic;
  signal frames_cmd_find        : std_logic;
  signal frames_cmd_clear       : std_logic;
  signal frames_cmd_valid       : std_logic;
  signal frames_cmd_ready       : std_logic;

  signal frames_resp_addr       : std_logic_vector(BUS_ADDR_WIDTH-1 downto 0);
  signal frames_resp_success    : std_logic;
  signal frames_resp_valid      : std_logic;
  signal frames_resp_ready      : std_logic;

  signal addr, addr_next        : unsigned(BUS_ADDR_WIDTH-1 downto 0);
  signal region, region_next    : unsigned(log2ceil(MEM_REGIONS)-1 downto 0);
  signal arg, arg_next          : std_logic_vector(BYTE_SIZE-1 downto 0);

  type state_type is (RESET_ST, IDLE, FAIL, CLEAR_FRAMES, CLEAR_FRAMES_CHECK,
                      RESERVE_PT, RESERVE_PT_CHECK, PT0_INIT,
                      PT_FRAME_INIT_ADDR, PT_FRAME_INIT_DATA,
                      PT_NEW, PT_NEW_CHECK_BM, PT_NEW_MARK_BM_ADDR, PT_NEW_MARK_BM_DATA,
                      PT_NEW_CLEAR_ADDR, PT_NEW_CLEAR_DATA);
  signal state, state_next         : state_type;
  signal state_ret, state_ret_next : state_type;

begin

  assert PAGE_SIZE_LOG2 >= PT_ENTRIES_LOG2 + log2ceil( (PTE_BITS+BYTE_SIZE-1) / BYTE_SIZE)
    report "page table does not fit in a single page"
    severity failure;

  assert PT_PER_FRAME > 1;
    report "page table size equal to page size is not implemented (requires omission of bitmap)"
    severity failure;

  assert PT_PER_FRAME <= PT_SIZE * BYTE_SIZE;
    report "page table bitmap extends into frame's first page table"
    severity failure;

  assert div_floor(PT_SIZE * BYTE_SIZE, log2ceil(BUS_DATA_WIDTH)) = div_ceil(PT_SIZE * BYTE_SIZE, log2ceil(BUS_DATA_WIDTH))
    report "page table size is not a multiple of the bus width"
    severity failure;

  assert PT_PER_FRAME <= BUS_DATA_WIDTH
    report "pages will not be completely utilized for page tables (requires extension of implementation)"
    severity warning;

  process (clk) begin
    if rising_edge(clk) then
      if reset = '1' then
        state     <= RESET_ST;
        state_ret <= IDLE;
        addr      <= (others => '0');
        arg       <= (others => '0');
      else
        state     <= state_next;
        state_ret <= state_ret_next;
        addr      <= addr_next;
        arg       <= arg_next;
      end if;
    end if;
  end process;

  process (state, state_ret, arg,
           cmd_region, cmd_addr, cmd_free, cmd_alloc, cmd_realloc, cmd_valid,
           resp_ready,
           frames_cmd_ready, frames_resp_addr, frames_resp_success, frames_resp_valid,
           bus_wreq_ready, bus_wdat_ready,
           bus_rreq_ready, bus_rdat_data, bus_rdat_last, bus_rdat_valid) begin
    state_next     <= state;
    state_ret_next <= state_ret;
    addr_next      <= addr;
    arg_next       <= arg;

    resp_success <= '0';
    resp_valid   <= '0';
    cmd_ready    <= '0';

    frames_cmd_valid  <= '0';
    frames_cmd_region <= (others => 'U');
    frames_cmd_addr   <= (others => 'U');
    frames_cmd_free   <= '0';
    frames_cmd_alloc  <= '0';
    frames_cmd_find   <= '0';
    frames_cmd_clear  <= '0';
    frames_resp_ready <= '0';

    bus_wreq_valid  <= '0';
    bus_wreq_addr   <= (others => 'U'); --slv(addr);
    bus_wreq_len    <= (others => 'U'); --slv(to_unsigned(1, bus_wreq_len'length));

    bus_wdat_valid  <= '0';
    bus_wdat_data   <= (others => 'U'); --(others => '0');
    bus_wdat_strobe <= (others => 'U'); --(others => '1');
    bus_wdat_last   <= 'U'; --'0';

    bus_rreq_valid  <= '0';
    bus_rreq_addr   <= (others => 'U'); --slv(addr);
    bus_rreq_len    <= (others => 'U'); --slv(to_unsigned(1, bus_wreq_len'length));

    bus_rdat_ready  <= '0';

    case state is

    when RESET_ST =>
      state_next <= CLEAR_FRAMES;

    when CLEAR_FRAMES =>
      frames_cmd_valid <= '1';
      frames_cmd_clear <= '1';
      if frames_cmd_ready = '1' then
        state_next <= CLEAR_FRAMES_CHECK;
      end if;

    when CLEAR_FRAMES_CHECK =>
      frames_resp_ready <= '1';
      if frames_resp_valid = '1' then
        if frames_resp_success = '1' then
          state_next <= RESERVE_PT;
        else
          state_next <= FAIL;
        end if;
      end if;

    when RESERVE_PT =>
      -- Reserve the designated frame for the root page table
      frames_cmd_valid <= '1';
      frames_cmd_alloc <= '1';
      frames_cmd_addr  <= PAGE_BASE(PT_ADDR);
      if frames_cmd_ready = '1' then
        state_next <= RESERVE_PT_CHECK;
      end if;

    when RESERVE_PT_CHECK =>
      -- Check the address of the reserved frame
      frames_resp_ready <= '1';
      if frames_resp_valid = '1' then
        if (frames_resp_success = '1') and (frames_resp_addr = PAGE_BASE(PT_ADDR)) then
          state_next     <= PT_FRAME_INIT_ADDR;
          state_ret_next <= PT0_INIT;
          addr_next      <= PAGE_BASE(PT_ADDR);
        else
          state_next <= FAIL;
        end if;
      end if;

    when PT0_INIT =>
      state_next     <= PT_NEW;
      state_ret_next <= IDLE;
      addr_next      <= PT_ADDR;

    when PT_FRAME_INIT_ADDR =>
      -- Clear the usage bitmap of the frame at `addr'
      -- Can write further than the bitmap, because the entire frame should be unused at this point
      bus_wreq_valid <= '1';
      bus_wreq_addr  <= addr;
      bus_wreq_len   <= slv(to_unsigned(1, bus_wreq_len'length));
      if bus_wreq_ready = '1' then
        state_next <= PT_FRAME_INIT_DATA;
        if (PT_PER_FRAME > BUS_DATA_WIDTH) then
          -- Need another write on a higher address
          addr_next  <= unsigned(addr) + BUS_DATA_WIDTH / BYTE_SIZE;
        end if;
      end if;

    when PT_FRAME_INIT_DATA =>
      bus_wdat_valid  <= '1';
      bus_wdat_data   <= (others => '0');
      bus_wdat_strobe <= (others => '1');
      bus_wdat_last   <= '1';
      if bus_wdat_ready = '1' then
        if (PT_PER_FRAME < BUS_DATA_WIDTH) or (PAGE_OFFSET(addr) > PT_PER_FRAME / BYTE_SIZE) then
          -- Entire bitmap has been initialized
          state_next <= state_ret;
        else
          -- Need another write
          state_next <= PT_FRAME_INIT_ADDR;
        end if;
      end if;

    when PT_NEW =>
      -- Find a free spot for a PT
      bus_rreq_valid <= '1';
      bus_rreq_addr  <= PAGE_BASE(addr);
      bus_rreq_len   <= slv(to_unsigned(1, bus_rreq_len'length));
      -- TODO LOW implement finding empty spots past BUS_DATA_WIDTH entries
      if bus_rreq_ready = '1' then
        state_next <= PT_NEW_CHECK_BM;
      end if;

    when PT_NEW_CHECK_BM =>
      bus_rdat_ready <= '1';
      if bus_rdat_valid = '1' then
        for i in 0 to work.Utils.min(PT_PER_FRAME, BUS_DATA_WIDTH) loop
          if i = work.Utils.min(PT_PER_FRAME, BUS_DATA_WIDTH) then
            addr_next  <= PAGE_BASE(addr);
            state_next <= FAIL; -- TODO: try more bits or other frame
            exit;
          end if;
          if bus_rdat_data(i) = '0' then
            -- Bit 0 refers to the first possible page table in this frame,
            -- which exists on the first aligned location after the bitmap.
            addr_next   <= PAGE_BASE(addr) + (i+1) * 2**PT_ENTRIES_LOG2;
            state_next  <= PT_NEW_MARK_BM_ADDR;
            -- Save the byte that needs to be written
            arg_next    <= slv(resize(unsigned(bus_rdat_data((i/BYTE_SIZE)*BYTE_SIZE+BYTE_SIZE-1 downto (i/BYTE_SIZE)*BYTE_SIZE)), arg_next'length));
            arg_next(i mod BYTE_SIZE) <= '1';
            exit;
          end if;
        end loop;
      end if;

    when PT_NEW_MARK_BM_ADDR =>
      bus_wreq_valid <= '1';
      bus_wreq_addr  <= PAGE_BASE(addr);
      bus_wreq_len   <= slv(to_unsigned(1, bus_wreq_len'length));
      -- TODO: enable bitmap location > BUS_DATA_WIDTH
      if bus_wreq_ready = '1' then
        state_next <= PT_NEW_MARK_BM_DATA;
      end if;

    when PT_NEW_MARK_BM_DATA =>
      bus_wdat_valid  <= '1';
      bus_wdat_data   <= ;
      bus_wdat_strobe <= ;
      bus_wdat_last <= '1';
      if bus_wdat_ready = '1' then
        state_next <= PT_NEW_CLEAR_ADDR;
      end if;

    when PT_NEW_CLEAR_ADDR =>
      bus_wreq_valid <= '1';
      bus_wreq_addr  <= addr;
      bus_wreq_len   <= slv(to_unsigned(1, bus_wreq_len'length));
      if bus_wreq_ready = '1' then
        state_next <= PT_NEW_MARK_BM_DATA;
      end if;

    when PT_NEW_CLEAR_DATA =>
      bus_wdat_valid  <= '1';
      bus_wdat_data   <= (others => '0');
      bus_wdat_strobe <= (others => '1');
      bus_wdat_last <= '1';
      if bus_wdat_ready = '1' then
        state_next <= state_ret;
      end if;

    when IDLE =>


    when others =>
      resp_valid   <= '1';
      resp_success <= '0';

    end case;
  end process;

  framestore : MMFrames
    generic map (
      PAGE_SIZE_LOG2              => PAGE_SIZE_LOG2,
      MEM_REGIONS                 => MEM_REGIONS,
      MEM_SIZES                   => MEM_SIZES,
      MEM_MAP_BASE                => MEM_MAP_BASE,
      MEM_MAP_SIZE_LOG2           => MEM_MAP_SIZE_LOG2,
      BUS_ADDR_WIDTH              => BUS_ADDR_WIDTH
    )
    port map (
      clk                         => clk,
      reset                       => reset,
      cmd_region                  => frames_cmd_region,
      cmd_addr                    => frames_cmd_addr,
      cmd_free                    => frames_cmd_free,
      cmd_alloc                   => frames_cmd_alloc,
      cmd_find                    => frames_cmd_find,
      cmd_clear                   => frames_cmd_clear,
      cmd_valid                   => frames_cmd_valid,
      cmd_ready                   => frames_cmd_ready,

      resp_addr                   => frames_resp_addr,
      resp_success                => frames_resp_success,
      resp_valid                  => frames_resp_valid,
      resp_ready                  => frames_resp_ready
    );

end architecture;


