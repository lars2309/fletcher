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
    VM_BASE                     : unsigned(ADDR_WIDTH_LIMIT-1 downto 0);
    PT_ADDR                     : unsigned(ADDR_WIDTH_LIMIT-1 downto 0);
    PT_ENTRIES_LOG2             : natural;
    PTE_BITS                    : natural;

    MAX_OUTSTANDING_TRANSACTIONS: natural := 63;

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
    cmd_region                  : in  std_logic_vector(log2ceil(MEM_REGIONS+1)-1 downto 0);
    cmd_addr                    : in  std_logic_vector(BUS_ADDR_WIDTH-1 downto 0);
    cmd_size                    : in  std_logic_vector(BUS_ADDR_WIDTH-1 downto 0);
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

    -- Response channel
    bus_resp_valid              : in  std_logic;
    bus_resp_ready              : out std_logic;
    bus_resp_ok                 : in  std_logic;

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
  constant BUS_DATA_BYTES       : natural := BUS_DATA_WIDTH / BYTE_SIZE;
  constant PT_SIZE_LOG2         : natural := PT_ENTRIES_LOG2 + log2ceil(DIV_CEIL(PTE_BITS, BYTE_SIZE));
  constant PT_SIZE              : natural := 2**PT_SIZE_LOG2;
  -- Offset of the first usable PT into the frame (first space is taken by bitmap)
  constant PT_FIRST_NR          : natural := 1;
  constant PT_PER_FRAME         : natural := 2**(PAGE_SIZE_LOG2 - PT_ENTRIES_LOG2 - log2ceil( DIV_CEIL(PTE_BITS, BYTE_SIZE) )) - PT_FIRST_NR;
  constant PTE_SIZE             : natural := 2**log2ceil(DIV_CEIL(PTE_BITS, BYTE_SIZE));
  constant PTE_WIDTH            : natural := PTE_SIZE * BYTE_SIZE;

  constant PTE_MAPPED           : natural := 0;
  constant PTE_PRESENT          : natural := 1;
  constant PTE_BOUNDARY         : natural := 2;

  constant VM_SIZE_L2_LOG2      : natural := PAGE_SIZE_LOG2;
  constant VM_SIZE_L1_LOG2      : natural := VM_SIZE_L2_LOG2 + PT_ENTRIES_LOG2;
  constant VM_SIZE_L0_LOG2      : natural := VM_SIZE_L1_LOG2 + PT_ENTRIES_LOG2;

  function CLAMP (val   : unsigned;
                  clamp : natural)
    return unsigned is
    variable ret : unsigned(log2ceil(clamp+1)-1 downto 0);
  begin
    if val > clamp then
      ret := to_unsigned(clamp, ret'length);
    else
      ret := val(ret'length-1 downto 0);
    end if;
    return ret;
  end CLAMP;

  function TAKE_EVERY (vec      : unsigned;
                       interval : natural;
                       offset   : natural)
    return unsigned is
    variable ret : unsigned(vec'length / interval - 1 downto 0);
  begin
    for N in 0 to vec'length / interval - 1 loop
      ret(N) := vec(interval * N + offset);
    end loop;
    return ret;
  end TAKE_EVERY;

  function FIND_GAP (mask  : unsigned;
                     rsize : unsigned)
    return unsigned is
    variable csize : unsigned(rsize'length-1 downto 0);
    variable start : unsigned(rsize'length-1 downto 0);
  begin
    csize := (others => '0');
    start := (others => '0');
    for N in 0 to mask'length-1 loop
      if mask(N) = '0' then
        csize := csize + 1;
      else
        csize := (others => '0');
        start := to_unsigned(N + 1, start'length);
      end if;
      exit when csize = rsize;
    end loop;
    return start & csize;
  end FIND_GAP;

  function FIND_GAP_SIZE (mask  : unsigned;
                          rsize : unsigned)
    return unsigned is
    variable ret : unsigned(rsize'length*2-1 downto 0);
  begin
    ret := FIND_GAP(mask, rsize);
    return ret(rsize'length-1 downto 0);
  end FIND_GAP_SIZE;

  function FIND_GAP_START (mask  : unsigned;
                           rsize : unsigned)
    return unsigned is
    variable ret : unsigned(rsize'length*2-1 downto 0);
  begin
    ret := FIND_GAP(mask, rsize);
    return ret(rsize'length*2-1 downto rsize'length);
  end FIND_GAP_START;

  function PAGE_OFFSET (addr : unsigned(BUS_ADDR_WIDTH-1 downto 0))
    return unsigned is
  begin
    return resize(addr(PAGE_SIZE_LOG2-1 downto 0), addr'length);
  end PAGE_OFFSET;

  function PT_OFFSET (addr : unsigned(BUS_ADDR_WIDTH-1 downto 0))
    return unsigned is
  begin
    return resize(addr(PT_SIZE_LOG2-1 downto 0), addr'length);
  end PT_OFFSET;

  function PAGE_BASE (addr : unsigned(BUS_ADDR_WIDTH-1 downto 0))
    return unsigned is
  begin
    return align_beq(addr, PAGE_SIZE_LOG2);
  end PAGE_BASE;

  -- Convert a size to a number of pages, rounding up.
  function PAGE_COUNT (size : unsigned)
    return unsigned is
    variable ret : unsigned(BUS_ADDR_WIDTH-1 downto 0);
  begin
    ret := resize(size, ret'length);
    -- Set bits that cannot be used in our address space to '0'.
    ret(ret'high downto VM_SIZE_L0_LOG2) := (others => '0');
    -- Round up to pages.
    ret := shift_right_round_up(size, PAGE_SIZE_LOG2);
    return ret;
  end PAGE_COUNT;

  function PT_INDEX (addr : unsigned(BUS_ADDR_WIDTH-1 downto 0))
    return unsigned is
  begin
    return shift_right(PT_OFFSET(addr), log2ceil(PTE_SIZE));
  end PT_INDEX;

  function PTE_TO_VA (addr_in  : unsigned(BUS_ADDR_WIDTH-1 downto 0);
                      index    : unsigned;
                      pt_level : natural)
    return unsigned is
    variable addr : unsigned(BUS_ADDR_WIDTH-1 downto 0);
  begin
    assert index(index'high downto PT_ENTRIES_LOG2) = 0
      report "PTE_TO_VA: index high bits are not 0"
      severity failure;
    addr := VM_BASE;
    addr := OVERLAY(addr_in(VM_SIZE_L0_LOG2-1 downto 0), addr);
    if pt_level = 1 then
      addr := OVERLAY(index(PT_ENTRIES_LOG2-1 downto 0), addr, PAGE_SIZE_LOG2 + PT_ENTRIES_LOG2);
    elsif pt_level = 2 then
      addr := OVERLAY(index(PT_ENTRIES_LOG2-1 downto 0), addr, PAGE_SIZE_LOG2);
    else
      addr := (others => 'X');
    end if;
    return addr;
  end PTE_TO_VA;

  function PTE_TO_VA (index    : unsigned;
                      pt_level : natural)
    return unsigned is
  begin
    return PTE_TO_VA(to_unsigned(0, BUS_ADDR_WIDTH), index, pt_level);
  end PTE_TO_VA;

  function VA_TO_PTE (pt_base : unsigned(BUS_ADDR_WIDTH-1 downto 0);
                      vm_addr : unsigned(BUS_ADDR_WIDTH-1 downto 0);
                      pt_level: natural)
    return unsigned is
    variable index : unsigned(PT_ENTRIES_LOG2-1 downto 0);
    variable ret : unsigned(BUS_ADDR_WIDTH-1 downto 0) := (others => '0');
  begin
    if pt_level = 1 then
      index := EXTRACT(vm_addr, PAGE_SIZE_LOG2 + PT_ENTRIES_LOG2, PT_ENTRIES_LOG2);
    elsif pt_level = 2 then
      index := EXTRACT(vm_addr, PAGE_SIZE_LOG2, PT_ENTRIES_LOG2);
    else
      index := (others => 'X');
    end if;
    return OVERLAY(
      shift_left(
        resize(index, index'length + log2ceil(PTE_SIZE)),
        log2ceil(PTE_SIZE)),
      pt_base);
  end VA_TO_PTE;

  function ADDR_BUS_ALIGN (addr : unsigned(BUS_ADDR_WIDTH-1 downto 0))
    return unsigned is
  begin
    return OVERLAY(to_unsigned(0, log2ceil(BUS_DATA_BYTES)), addr);
  end ADDR_BUS_ALIGN;

  function ADDR_BUS_OFFSET (addr : unsigned(BUS_ADDR_WIDTH-1 downto 0))
    return unsigned is
  begin
    return resize(addr(log2ceil(BUS_DATA_BYTES)-1 downto 0), addr'length);
  end ADDR_BUS_OFFSET;

  function BYTES_IN_BEATS (beats : unsigned)
    return unsigned is
  begin
    return beats & to_unsigned(0, log2ceil(BUS_DATA_BYTES));
  end function;

  signal int_bus_wreq_valid     : std_logic;
  signal int_bus_wreq_ready     : std_logic;
  signal int_bus_wreq_addr      : std_logic_vector(BUS_ADDR_WIDTH-1 downto 0);
  signal int_bus_wreq_len       : std_logic_vector(BUS_LEN_WIDTH-1 downto 0);
  signal int_bus_wreq_barrier   : std_logic;
  signal int_bus_dirty          : std_logic;

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

  type state_type is (RESET_ST, IDLE, FAIL, CLEAR_FRAMES, CLEAR_FRAMES_CHECK,
                      RESERVE_PT, RESERVE_PT_CHECK, PT0_INIT,

                      VMALLOC, VMALLOC_CHECK_PT0, VMALLOC_CHECK_PT0_DATA,
                      VMALLOC_RESERVE_FRAME, VMALLOC_FINISH,

                      SET_PTE_RANGE, SET_PTE_RANGE_L1_CHECK,
                      SET_PTE_RANGE_L1_UPDATE_ADDR, SET_PTE_RANGE_L1_UPDATE_DAT,
                      SET_PTE_RANGE_L2_UPDATE_ADDR, SET_PTE_RANGE_L2_UPDATE_DAT,

                      PT_NEW, PT_NEW_CHECK_BM, PT_NEW_MARK_BM_ADDR,
                      PT_NEW_MARK_BM_DATA, PT_NEW_CLEAR_ADDR, PT_NEW_CLEAR_DATA,

                      PT_FRAME_INIT_ADDR, PT_FRAME_INIT_DATA );
  constant STATE_STACK_DEPTH : natural := 4;
  type state_stack_type is array (STATE_STACK_DEPTH-1 downto 0) of state_type;

  function pop_state(stack : state_stack_type) return state_stack_type is
    variable ret : state_stack_type := (others => FAIL);
  begin
    ret(ret'high-1 downto 0) := stack(stack'high downto 1);
    return ret;
  end pop_state;

  function push_state(stack : state_stack_type; arg : state_type) return state_stack_type is
    variable ret : state_stack_type := (others => FAIL);
  begin
    ret(ret'high downto 1) := stack(stack'high-1 downto 0);
    ret(0) := arg;
    return ret;
  end push_state;

  type reg_type is record
    state_stack                 : state_stack_type;
    addr                        : unsigned(BUS_ADDR_WIDTH-1 downto 0);
    addr_vm                     : unsigned(BUS_ADDR_WIDTH-1 downto 0);
    addr_pt                     : unsigned(BUS_ADDR_WIDTH-1 downto 0);
    size                        : unsigned(BUS_ADDR_WIDTH-1 downto 0);
    region                      : unsigned(log2ceil(MEM_REGIONS+1)-1 downto 0);
    arg                         : unsigned(1 downto 0);
    byte_buffer                 : unsigned(BYTE_SIZE-1 downto 0);
    beat                        : unsigned(log2ceil(BUS_BURST_MAX_LEN+1)-1 downto 0);
  end record;

  signal r                      : reg_type;
  signal d                      : reg_type;

begin
  assert PAGE_SIZE_LOG2 >= PT_ENTRIES_LOG2 + log2ceil( DIV_CEIL(PTE_BITS, BYTE_SIZE))
    report "page table does not fit in a single page"
    severity failure;

  assert PT_PER_FRAME /= 1
    report "page table size equal to page size is not implemented (requires omission of bitmap)"
    severity failure;

  assert PT_PER_FRAME <= PT_SIZE * BYTE_SIZE
    report "page table bitmap extends into frame's first page table"
    severity failure;

  assert PT_SIZE / BUS_DATA_BYTES = DIV_CEIL(PT_SIZE, BUS_DATA_BYTES)
    report "page table size is not a multiple of the bus width"
    severity failure;

  assert BUS_DATA_BYTES / PTE_SIZE = DIV_CEIL(BUS_DATA_BYTES, PTE_SIZE)
    report "bus width is not a multiple of page table entry size"
    severity failure;

  assert PT_PER_FRAME <= BUS_DATA_WIDTH
    report "pages will not be completely utilized for page tables (requires extension of bitmap implementation)"
    severity warning;

  assert log2ceil(BUS_BURST_MAX_LEN) = log2floor(BUS_BURST_MAX_LEN)
    report "BUS_BURST_MAX_LEN is not a power of two; this may cause bursts to cross 4k boundaries"
    severity warning;

-- TODO: assert that L1 PT address refers to first possible PT in that frame.

  process (clk) begin
    if rising_edge(clk) then
      if reset = '1' then
        r.state_stack    <= (others => FAIL);
        r.state_stack(0) <= RESET_ST;
        r.addr           <= (others => '0');
        r.addr_vm        <= (others => '0');
        r.addr_pt        <= (others => '0');
        r.arg            <= (others => '0');
        r.byte_buffer    <= (others => '0');
        r.size           <= (others => '0');
        r.beat           <= (others => '0');
      else
        r <= d;
      end if;
    end if;
  end process;

  process (r,
           cmd_region, cmd_addr, cmd_free, cmd_alloc, cmd_realloc, cmd_valid, cmd_size,
           resp_ready,
           frames_cmd_ready, frames_resp_addr, frames_resp_success, frames_resp_valid,
           int_bus_wreq_ready, bus_wdat_ready, int_bus_dirty,
           bus_rreq_ready, bus_rdat_data, bus_rdat_last, bus_rdat_valid) is
    variable v : reg_type;
  begin
    v := r;

    resp_success <= '0';
    resp_valid   <= '0';
    resp_addr    <= (others => '0');
    cmd_ready    <= '0';

    frames_cmd_valid  <= '0';
    frames_cmd_region <= (others => '0');
    frames_cmd_addr   <= (others => '0');
    frames_cmd_free   <= '0';
    frames_cmd_alloc  <= '0';
    frames_cmd_find   <= '0';
    frames_cmd_clear  <= '0';
    frames_resp_ready <= '0';

    int_bus_wreq_valid   <= '0';
    int_bus_wreq_addr    <= (others => '0'); --slv(addr);
    int_bus_wreq_len     <= (others => '0'); --slv(to_unsigned(1, bus_wreq_len'length));
    int_bus_wreq_barrier <= '1';

    bus_wdat_valid  <= '0';
    bus_wdat_data   <= (others => '0');
    bus_wdat_strobe <= (others => '1');
    bus_wdat_last   <= '0';

    bus_rreq_valid  <= '0';
    bus_rreq_addr   <= (others => '0'); --slv(addr);
    bus_rreq_len    <= (others => '0'); --slv(to_unsigned(1, bus_wreq_len'length));

    bus_rdat_ready  <= '0';

--pragma synthesis_off
    resp_addr         <= (others => 'U');
    frames_cmd_region <= (others => 'U');
    frames_cmd_addr   <= (others => 'U');
    int_bus_wreq_addr <= (others => 'U');
    int_bus_wreq_len  <= (others => 'U');
    bus_wdat_data     <= (others => 'U');
    bus_wdat_strobe   <= (others => 'U');
    bus_wdat_last     <= 'U';
    bus_rreq_addr     <= (others => 'U');
    bus_rreq_len      <= (others => 'U');
--pragma synthesis_on

    case v.state_stack(0) is

    when RESET_ST =>
      v.state_stack(0) := CLEAR_FRAMES;

    when CLEAR_FRAMES =>
      -- Clear the frames utilization bitmap.
      frames_cmd_valid <= '1';
      frames_cmd_clear <= '1';
      if frames_cmd_ready = '1' then
        v.state_stack(0) := CLEAR_FRAMES_CHECK;
      end if;

    when CLEAR_FRAMES_CHECK =>
      -- Check the clear command response.
      frames_resp_ready <= '1';
      if frames_resp_valid = '1' then
        if frames_resp_success = '1' then
          v.state_stack(0) := RESERVE_PT;
        else
          v.state_stack(0) := FAIL;
        end if;
      end if;

    when RESERVE_PT =>
      -- Reserve the designated frame for the root page table.
      frames_cmd_valid <= '1';
      frames_cmd_alloc <= '1';
      frames_cmd_addr  <= slv(PAGE_BASE(PT_ADDR));
      if frames_cmd_ready = '1' then
        v.state_stack(0) := RESERVE_PT_CHECK;
      end if;

    when RESERVE_PT_CHECK =>
      -- Check the address of the reserved frame.
      -- Execute the `frame initialize' routine to set bitmap, continue to PT0_INIT.
      frames_resp_ready <= '1';
      if frames_resp_valid = '1' then
        if (frames_resp_success = '1') and (u(frames_resp_addr) = PAGE_BASE(PT_ADDR)) then
          v.state_stack(0) := PT_FRAME_INIT_ADDR;
          v.state_stack(1) := PT0_INIT;
          v.addr           := PAGE_BASE(PT_ADDR);
        else
          v.state_stack(0) := FAIL;
        end if;
      end if;

    when PT0_INIT =>
      -- Initialize the root page table by executing the `new page table' routine.
      v.state_stack(0) := PT_NEW;
      v.state_stack(1) := IDLE;
      v.addr           := PT_ADDR;

    when IDLE =>
      if cmd_valid = '1' then

        if cmd_alloc = '1' then
          if unsigned(cmd_region) = 0 then
            -- TODO: host allocation
            v.state_stack(0) := FAIL;
          else
            v.state_stack := push_state(v.state_stack, VMALLOC);
          end if;

        elsif cmd_free = '1' then
          -- TODO
          v.state_stack(0) := FAIL;

        elsif cmd_realloc = '1' then
          -- TODO
          v.state_stack(0) := FAIL;
        end if;
      end if;

    -- === START OF VMALLOC ROUTINE ===
    -- Find big enough free chunk in virtual address space.
    -- Allocate single frame for start of allocation in the given region.
    -- `addr_vm' will contain virtual address of allocation.

    when VMALLOC =>
      -- Request the L0 page table to find a high-level gap.
      -- TODO: find gaps in lower level page tables.
      v.addr           := PT_ADDR;
      v.size           := shift_left(
                              shift_right_round_up(unsigned(cmd_size), VM_SIZE_L1_LOG2),
                              VM_SIZE_L1_LOG2
                            );
      v.addr_vm        := PTE_TO_VA(PT_INDEX(v.addr), 1);
      v.state_stack(0) := VMALLOC_CHECK_PT0;

    when VMALLOC_CHECK_PT0 =>
      bus_rreq_addr  <= slv(v.addr);
      bus_rreq_len   <= slv(to_unsigned(1, bus_rreq_len'length));
      if int_bus_dirty = '0' then
        bus_rreq_valid <= '1';
        if bus_rreq_ready = '1' then
          v.state_stack(0) := VMALLOC_CHECK_PT0_DATA;
        end if;
      end if;

    when VMALLOC_CHECK_PT0_DATA =>
      -- Check the returned PTEs for allocation gaps.
      -- v.size tracks the remaining gap size to be found, rounded up to L1 PTE coverage.
      bus_rdat_ready <= '1';
      if bus_rdat_valid = '1' then
        -- needed size: CLAMP(shift_right(v.size, VM_SIZE_L1_LOG2), BUS_DATA_BYTES / PTE_SIZE)
        if
          -- Not a continuation
          FIND_GAP_START(
              TAKE_EVERY(u(bus_rdat_data), PTE_WIDTH, PTE_MAPPED),
              CLAMP(shift_right(v.size, VM_SIZE_L1_LOG2), BUS_DATA_BYTES / PTE_SIZE)
          ) /= 0
        then
          -- New gap was started
          v.addr_vm := PTE_TO_VA(
              PT_INDEX(v.addr) + FIND_GAP_START(
                    TAKE_EVERY(u(bus_rdat_data), PTE_WIDTH, PTE_MAPPED),
                    CLAMP(shift_right(v.size, VM_SIZE_L1_LOG2), BUS_DATA_BYTES / PTE_SIZE)),
              1);
          -- Subtract the gap size from requested size.
          v.size := shift_left(
              shift_right_round_up(unsigned(cmd_size), VM_SIZE_L1_LOG2)
              - FIND_GAP_SIZE(
                TAKE_EVERY(u(bus_rdat_data), PTE_WIDTH, PTE_MAPPED),
                CLAMP(shift_right(v.size, VM_SIZE_L1_LOG2), BUS_DATA_BYTES / PTE_SIZE)
              ),
              VM_SIZE_L1_LOG2);
        else
          -- Subtract the gap size from leftover size.
          v.size := shift_left(
              shift_right(v.size, VM_SIZE_L1_LOG2)
              - FIND_GAP_SIZE(
                TAKE_EVERY(u(bus_rdat_data), PTE_WIDTH, PTE_MAPPED),
                CLAMP(shift_right(v.size, VM_SIZE_L1_LOG2), BUS_DATA_BYTES / PTE_SIZE)
              ),
              VM_SIZE_L1_LOG2);
        end if;

        -- Next set of PTEs
        v.addr           := v.addr + BUS_DATA_BYTES;

        if 0 = EXTRACT(v.size, VM_SIZE_L1_LOG2, VM_SIZE_L0_LOG2 - VM_SIZE_L1_LOG2) then
          -- Gap is big enough, continue to allocate a frame
          v.state_stack(0) := VMALLOC_RESERVE_FRAME;
        else
          -- Check more L0 entries
          v.state_stack(0) := VMALLOC_CHECK_PT0;
        end if;
      end if;

    when VMALLOC_RESERVE_FRAME =>
      -- TODO: capture reserved frame in register, so that setPTERange can use the frame allocator.
      -- Find a frame in the given region, result will be available later.
      frames_cmd_valid  <= '1';
      frames_cmd_find   <= '1';
      frames_cmd_region <= slv(resize(unsigned(cmd_region) - 1, frames_cmd_region'length));

      if frames_cmd_ready = '1' then
        cmd_ready        <= '1';
        -- addr_vm  : virtual base address to start at
        -- cmd_size : length to set
        v.state_stack    := push_state(v.state_stack, SET_PTE_RANGE);
        v.state_stack(1) := VMALLOC_FINISH;
        v.size           := unsigned(cmd_size);
        -- Take first page mapping from frame allocator
        v.arg            := to_unsigned(1, v.arg'length);
        v.addr           := v.addr_vm;
      end if;

    when VMALLOC_FINISH =>
      resp_success <= '1';
      resp_addr    <= slv(v.addr_vm);
      if int_bus_dirty = '0' then
        resp_valid   <= '1';
        if resp_ready = '1' then
          v.state_stack := pop_state(v.state_stack);
        end if;
      end if;

    -- === START OF SET_PTE_RANGE ROUTINE ===
    -- Set mapping for a range of virtual addresses, create page tables as needed.
    -- `addr_vm` contains address to start mapping at.
    -- `size`    contains length of mapping.
    -- `addr`    must be initialized to `addr_vm`. (Is used to keep track of progress)
    -- arg(0) = '1' -> Take first frame from frame allocator.
    -- arg(1) = '1' -> Conditional allocation: stop when already mapped. TODO

    when SET_PTE_RANGE =>
      -- Get the L1 PTE
      bus_rreq_addr  <= slv(ADDR_BUS_ALIGN(VA_TO_PTE(PT_ADDR, v.addr, 1)));
      bus_rreq_len   <= slv(to_unsigned(1, bus_rreq_len'length));
      if int_bus_dirty = '0' then
        bus_rreq_valid <= '1';
        if bus_rreq_ready = '1' then
          v.state_stack(0) := SET_PTE_RANGE_L1_CHECK;
        end if;
      end if;

    when SET_PTE_RANGE_L1_CHECK =>
      bus_rdat_ready <= '1';
      if bus_rdat_valid = '1' then
        -- Check PRESENT bit of PTE referred to by addr.
        -- We ignore any present entries without checking the L2 table for simplicity of implementation.
        if bus_rdat_data(
             PTE_SIZE * int(ADDR_BUS_OFFSET(VA_TO_PTE(PT_ADDR, v.addr, 1)))
             + PTE_PRESENT
           ) = '1'
        then
          -- Page table already exists, get address from the read data.
          v.addr_pt := align_beq(
              EXTRACT(
                unsigned(bus_rdat_data),
                BYTE_SIZE * int(ADDR_BUS_OFFSET(VA_TO_PTE(PT_ADDR, v.addr, 1))),
                BYTE_SIZE * PTE_SIZE
              ),
              PT_SIZE_LOG2);
          v.state_stack(0) := SET_PTE_RANGE_L2_UPDATE_ADDR;
        else
          -- Need to allocate a page table.
          v.state_stack    := push_state(v.state_stack, PT_NEW);
          v.state_stack(1) := SET_PTE_RANGE_L1_UPDATE_ADDR;
        end if;
      end if;

    when SET_PTE_RANGE_L1_UPDATE_ADDR =>
      -- A new PT was allocated, update the corresponding L1 entry.
      int_bus_wreq_valid <= '1';
      int_bus_wreq_addr  <= slv(ADDR_BUS_ALIGN(VA_TO_PTE(PT_ADDR, v.addr, 1)));
      int_bus_wreq_len   <= slv(to_unsigned(1, int_bus_wreq_len'length));
      if int_bus_wreq_ready = '1' then
        v.state_stack(0) := SET_PTE_RANGE_L1_UPDATE_DAT;
      end if;

    when SET_PTE_RANGE_L1_UPDATE_DAT =>
      -- Update the PTE
      bus_wdat_valid  <= '1';
      bus_wdat_last   <= '1';
      -- Duplicate the address over the data bus
      for i in 0 to BUS_DATA_BYTES/PTE_SIZE-1 loop
        bus_wdat_data(PTE_WIDTH * (i+1) - 1 downto PTE_WIDTH * i) <= slv(v.addr_pt);
        -- Mark the entry as mapped and present
        bus_wdat_data(PTE_WIDTH * i + PTE_MAPPED)  <= '1';
        bus_wdat_data(PTE_WIDTH * i + PTE_PRESENT) <= '1';
      end loop;
      -- Use strobe to write the correct entry
      bus_wdat_strobe <= slv(OVERLAY(
          not to_unsigned(0, PTE_SIZE),
          to_unsigned(0, bus_wdat_strobe'length),
          int(ADDR_BUS_OFFSET(VA_TO_PTE(PT_ADDR, v.addr, 1)))));
      if bus_wdat_ready = '1' then
        v.state_stack(0) := SET_PTE_RANGE_L2_UPDATE_ADDR;
      end if;

    when SET_PTE_RANGE_L2_UPDATE_ADDR =>
      int_bus_wreq_valid <= '1';
      int_bus_wreq_addr  <= slv(ADDR_BUS_ALIGN(VA_TO_PTE(v.addr_pt, v.addr, 2)));
      int_bus_wreq_len   <= slv(to_unsigned(1, int_bus_wreq_len'length));
      if int_bus_wreq_ready = '1' then
        v.state_stack(0) := SET_PTE_RANGE_L2_UPDATE_DAT;
      end if;

    when SET_PTE_RANGE_L2_UPDATE_DAT =>
      if v.arg(0) = '1' then
        frames_resp_ready <= '1';
      end if;
      if frames_resp_valid = '1' or v.arg(0) = '0' then
        bus_wdat_valid  <= '1';
      end if;
      bus_wdat_last   <= '1';
      -- Duplicate the address over the data bus.
      for i in 0 to BUS_DATA_BYTES/PTE_SIZE-1 loop
        if v.arg(0) = '1' then
          -- Map to the allocated frame.
          bus_wdat_data(PTE_WIDTH * (i+1) - 1 downto PTE_WIDTH * i) <= frames_resp_addr;
          -- Mark the entry as mapped and present.
          bus_wdat_data(PTE_WIDTH * i + PTE_MAPPED)  <= '1';
          bus_wdat_data(PTE_WIDTH * i + PTE_PRESENT) <= '1';
        else
          -- Mark as mapped, but do not allocate frames.
          bus_wdat_data(PTE_WIDTH * (i+1) - 1 downto PTE_WIDTH * i) <= (others => '0');
          bus_wdat_data(PTE_WIDTH * i + PTE_MAPPED)  <= '1';
        end if;
        if PAGE_BASE(v.addr) + LOG2_TO_UNSIGNED(VM_SIZE_L2_LOG2)
          = PAGE_BASE(v.addr_vm) + shift_left(PAGE_COUNT(v.size), PAGE_SIZE_LOG2)
        then
          -- Last entry of mapping
          bus_wdat_data(PTE_WIDTH * i + PTE_BOUNDARY) <= '1';
        end if;
      end loop;
      -- Use strobe to write the correct entry.
      bus_wdat_strobe <= slv(OVERLAY(
          not to_unsigned(0, PTE_SIZE),
          to_unsigned(0, bus_wdat_strobe'length),
          int(ADDR_BUS_OFFSET(VA_TO_PTE(v.addr_pt, v.addr, 2)))));
      if bus_wdat_ready = '1' then
        -- Do not try to use allocated frame on next iteration.
        v.arg(0) := '0';
        -- Next address is increased by the size addressable by the written entries
        v.addr := v.addr + LOG2_TO_UNSIGNED(VM_SIZE_L2_LOG2);
        if PAGE_BASE(v.addr) = PAGE_BASE(v.addr_vm) + shift_left(PAGE_COUNT(v.size), PAGE_SIZE_LOG2) then
          -- Allocated enough space
          v.state_stack := pop_state(v.state_stack);
        elsif (EXTRACT(v.addr, PAGE_SIZE_LOG2, PT_ENTRIES_LOG2)) = 0 then
          -- At end of L2 page table, go to next table through L1.
          v.state_stack(0) := SET_PTE_RANGE;
        else
          -- Continue with next PTE.
          v.state_stack(0) := SET_PTE_RANGE_L2_UPDATE_ADDR;
        end if;
      end if;

    -- === START OF FRAME_INIT ROUTINE ===
    -- Clear the usage bitmap of the frame at `addr'.
    -- `addr' is not preserved, but will continue to point into the same frame.
    -- Does not preserve contents of the frame.

    when PT_FRAME_INIT_ADDR =>
      -- Can write further than the bitmap,
      -- because the entire frame should be unused at this point.
      int_bus_wreq_valid <= '1';
      int_bus_wreq_addr  <= slv(v.addr);
      int_bus_wreq_len   <= slv(to_unsigned(1, int_bus_wreq_len'length));
      if int_bus_wreq_ready = '1' then
        v.state_stack(0) := PT_FRAME_INIT_DATA;
        if (PT_PER_FRAME > BUS_DATA_WIDTH) then
          -- Need another write on a higher address
          v.addr := unsigned(v.addr) + BUS_DATA_BYTES;
        end if;
      end if;

    when PT_FRAME_INIT_DATA =>
      bus_wdat_valid  <= '1';
      bus_wdat_data   <= (others => '0');
      bus_wdat_strobe <= (others => '1');
      bus_wdat_last   <= '1';
      if bus_wdat_ready = '1' then
        if (PT_PER_FRAME < BUS_DATA_WIDTH) or (PAGE_OFFSET(v.addr) > PT_PER_FRAME / BYTE_SIZE) then
          -- Entire bitmap has been initialized
          v.state_stack := pop_state(v.state_stack);
        else
          -- Need another write
          v.state_stack(0) := PT_FRAME_INIT_ADDR;
        end if;
      end if;

    -- === START OF PT_NEW ROUTINE ===
    -- Find a free spot for a page table.
    -- mark it as used, and initialize the page table.
    -- `addr_pt' will contain the base address of the new page table.
    -- `addr` remains unchanged.

    when PT_NEW =>
      -- Find a free spot for a PT
      -- Use addr_pt to store addr
      v.addr_pt      := v.addr;
      v.addr         := PT_ADDR;
      bus_rreq_addr  <= slv(PAGE_BASE(v.addr));
      bus_rreq_len   <= slv(to_unsigned(1, bus_rreq_len'length));
      -- TODO implement finding empty spots past BUS_DATA_WIDTH entries
      if int_bus_dirty = '0' then
        bus_rreq_valid <= '1';
        if bus_rreq_ready = '1' then
          v.state_stack(0) := PT_NEW_CHECK_BM;
        end if;
      end if;

    when PT_NEW_CHECK_BM =>
      -- Load the adjacent bitmap bits before marking a bit.
      -- We need this, because the write strobe has byte granularity.
      bus_rdat_ready <= '1';
      if bus_rdat_valid = '1' then
        for i in 0 to work.Utils.min(PT_PER_FRAME, BUS_DATA_WIDTH) loop
          if i = work.Utils.min(PT_PER_FRAME, BUS_DATA_WIDTH) then
            v.state_stack(0) := FAIL; -- TODO: try more bits or other frame
            exit;
          end if;
          if bus_rdat_data(i) = '0' then
            -- Bit 0 refers to the first possible page table in this frame,
            -- which exists on the first aligned location after the bitmap.
            v.state_stack(0) := PT_NEW_MARK_BM_ADDR;
            v.addr           := OVERLAY(
                                    shift_left(to_unsigned(i+1, PAGE_SIZE_LOG2), PT_SIZE_LOG2),
                                    PAGE_BASE(v.addr));
            -- Save the byte that needs to be written
            v.byte_buffer    := EXTRACT(
                                    unsigned(bus_rdat_data),
                                    (i/BYTE_SIZE)*BYTE_SIZE,
                                    BYTE_SIZE
                                  );
            v.byte_buffer(i mod BYTE_SIZE) := '1';
            exit;
          end if;
        end loop;
      end if;

    when PT_NEW_MARK_BM_ADDR =>
      -- Set address for marking bit in bitmap
      int_bus_wreq_valid <= '1';
      int_bus_wreq_addr  <= slv(PAGE_BASE(v.addr));
      int_bus_wreq_len   <= slv(to_unsigned(1, int_bus_wreq_len'length));
      -- TODO: enable bitmap location > BUS_DATA_WIDTH
      if int_bus_wreq_ready = '1' then
        v.state_stack(0) := PT_NEW_MARK_BM_DATA;
      end if;

    when PT_NEW_MARK_BM_DATA =>
      bus_wdat_valid  <= '1';
      for i in 0 to BUS_DATA_BYTES-1 loop
        bus_wdat_data(BYTE_SIZE*(i+1)-1 downto BYTE_SIZE*i) <= slv(v.byte_buffer);
      end loop;
      bus_wdat_strobe <= (others => '0');
      -- Get page table number referenced by addr and figure out which byte of the bitmap it is in.
      bus_wdat_strobe(int(
        div_floor(
          shift_right_cut(PAGE_OFFSET(v.addr), PT_SIZE_LOG2) - PT_FIRST_NR,
          BYTE_SIZE)
        )) <= '1';
      bus_wdat_last <= '1';
      if bus_wdat_ready = '1' then
        v.state_stack(0) := PT_NEW_CLEAR_ADDR;
      end if;

    when PT_NEW_CLEAR_ADDR =>
      int_bus_wreq_valid <= '1';
      int_bus_wreq_addr  <= slv(v.addr);
      -- The number of beats in the burst
      v.beat         := to_unsigned(
                        work.Utils.min(
                          BUS_BURST_MAX_LEN,
                          int(div_ceil(
                            to_unsigned(PT_SIZE, log2ceil(PT_SIZE+1)) - PT_OFFSET(v.addr),
                            BUS_DATA_BYTES))
                        ),
                        v.beat'length);
      int_bus_wreq_len   <= slv(resize(v.beat, int_bus_wreq_len'length));
      if int_bus_wreq_ready = '1' then
        v.state_stack(0) := PT_NEW_CLEAR_DATA;
        v.addr           := v.addr + BYTES_IN_BEATS(v.beat);
      end if;

    when PT_NEW_CLEAR_DATA =>
      bus_wdat_valid  <= '1';
      bus_wdat_data   <= (others => '0');
      bus_wdat_strobe <= (others => '1');
      if bus_wdat_ready = '1' then
        -- One beat processed
        v.beat := v.beat - 1;
        bus_wdat_last <= '0';
        if v.beat = 0 then
          bus_wdat_last <= '1';
          -- This is the last beat
          if PT_OFFSET(v.addr) = 0 then
            -- Set return and restore addr
            v.addr_pt     := r.addr - PT_SIZE;
            v.addr        := r.addr_pt;
            v.state_stack := pop_state(v.state_stack);
          else
            v.state_stack(0) := PT_NEW_CLEAR_ADDR;
          end if;
        end if;
      end if;

    when others =>
      resp_valid   <= '1';
      resp_success <= '0';

    end case;

    d <= v;
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

  barrier : MMBarrier
    generic map (
      BUS_ADDR_WIDTH              => BUS_ADDR_WIDTH,
      BUS_LEN_WIDTH               => BUS_LEN_WIDTH,
      MAX_OUTSTANDING             => MAX_OUTSTANDING_TRANSACTIONS
    )
    port map (
      clk                         => clk,
      reset                       => reset,
      dirty                       => int_bus_dirty,

      -- Slave write request channel
      slv_wreq_valid              => int_bus_wreq_valid,
      slv_wreq_ready              => int_bus_wreq_ready,
      slv_wreq_addr               => int_bus_wreq_addr,
      slv_wreq_len                => int_bus_wreq_len,
      slv_wreq_barrier            => int_bus_wreq_barrier,
      -- Master write request channel
      mst_wreq_valid              => bus_wreq_valid,
      mst_wreq_ready              => bus_wreq_ready,
      mst_wreq_addr               => bus_wreq_addr,
      mst_wreq_len                => bus_wreq_len,

      -- Slave response channel
      slv_resp_valid              => open,
      slv_resp_ready              => open,
      slv_resp_ok                 => open,
      -- Master response channel
      mst_resp_valid              => bus_resp_valid,
      mst_resp_ready              => bus_resp_ready,
      mst_resp_ok                 => bus_resp_ok
    );

end architecture;


