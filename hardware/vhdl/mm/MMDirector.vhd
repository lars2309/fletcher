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

    mmu_req_valid               : in  std_logic := '0';
    mmu_req_ready               : out std_logic;
    mmu_req_addr                : in  std_logic_vector(BUS_ADDR_WIDTH-1 downto 0) := (others => '0');

    mmu_resp_valid              : out std_logic;
    mmu_resp_ready              : in  std_logic := '1';
    mmu_resp_addr               : out std_logic_vector(BUS_ADDR_WIDTH-1 downto 0);

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
  constant PT_MAX_AMOUNT        : natural := 2**PT_ENTRIES_LOG2 + 1;
  constant PT_PER_FRAME         : natural := 2**(PAGE_SIZE_LOG2 - PT_ENTRIES_LOG2 - log2ceil( DIV_CEIL(PTE_BITS, BYTE_SIZE) )) - PT_FIRST_NR;
  constant PTE_SIZE             : natural := 2**log2ceil(DIV_CEIL(PTE_BITS, BYTE_SIZE));
  constant PTE_WIDTH            : natural := PTE_SIZE * BYTE_SIZE;

  constant PTE_MAPPED           : natural := 0;
  constant PTE_PRESENT          : natural := 1;
  constant PTE_BOUNDARY         : natural := 2;

  constant FRAME_IDX_WIDTH      : natural := MEM_MAP_SIZE_LOG2 + MEM_REGIONS - PAGE_SIZE_LOG2;

  constant VM_SIZE_L2_LOG2      : natural := PAGE_SIZE_LOG2;
  constant VM_SIZE_L1_LOG2      : natural := VM_SIZE_L2_LOG2 + PT_ENTRIES_LOG2;
  constant VM_SIZE_L0_LOG2      : natural := VM_SIZE_L1_LOG2 + PT_ENTRIES_LOG2;

  function CLAMP (val   : unsigned;
                  clamp : natural)
    return unsigned is
    variable ret : unsigned(val'length-1 downto 0);
  begin
    if val > clamp then
      ret := to_unsigned(clamp, ret'length);
    else
      ret := val;
    end if;
    -- Make it easier for synthesis tools to deduce these will always be zero.
    -- Shortening the returned vector does not work with Vivado.
    ret(ret'length-1 downto log2ceil(clamp+1)) := (others => '0');
    return ret;
  end CLAMP;

  function CLAMP_PTES_PER_BUS (val : unsigned)
    return unsigned is
    variable ret : unsigned(val'length-1 downto 0);
  begin
    ret := CLAMP(val, BUS_DATA_BYTES / PTE_SIZE);
    return ret( log2ceil(BUS_DATA_BYTES / PTE_SIZE + 1) - 1 downto 0);
  end CLAMP_PTES_PER_BUS;

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
    variable ret : unsigned(VM_SIZE_L0_LOG2 - PAGE_SIZE_LOG2 - 1 downto 0);
  begin
    ret := resize(shift_right_round_up(size, PAGE_SIZE_LOG2), ret'length);
    return ret(VM_SIZE_L0_LOG2 - PAGE_SIZE_LOG2 - 1 downto 0);
  end PAGE_COUNT;

  function PT_BITMAP_IDX (addr : unsigned(BUS_ADDR_WIDTH-1 downto 0))
    return unsigned is
  begin
    return shift_right_cut(
          resize(addr, PAGE_SIZE_LOG2),
          PT_SIZE_LOG2
        ) - PT_FIRST_NR;
  end PT_BITMAP_IDX;

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

  function ADDR_TO_ROLODEX (addr : unsigned(BUS_ADDR_WIDTH-1 downto 0))
    return std_logic_vector is
  begin
    return slv(EXTRACT(addr, PAGE_SIZE_LOG2, FRAME_IDX_WIDTH));
  end ADDR_TO_ROLODEX;

  function ROLODEX_TO_ADDR (dex : std_logic_vector(FRAME_IDX_WIDTH-1 downto 0))
    return unsigned is
  begin
    return OVERLAY(u(dex), MEM_MAP_BASE, PAGE_SIZE_LOG2);
  end ROLODEX_TO_ADDR;

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

  signal gap_q_valid            : std_logic;
  signal gap_q_ready            : std_logic;
  signal gap_q_holes            : std_logic_vector(BUS_DATA_WIDTH / PTE_WIDTH - 1 downto 0);
  signal gap_q_size             : std_logic_vector(log2ceil(BUS_DATA_WIDTH / PTE_WIDTH + 1) - 1 downto 0);
  signal gap_a_valid            : std_logic;
  signal gap_a_ready            : std_logic;
  signal gap_a_offset           : std_logic_vector(log2ceil(BUS_DATA_WIDTH / PTE_WIDTH + 1) - 1 downto 0);
  signal gap_a_size             : std_logic_vector(log2ceil(BUS_DATA_WIDTH / PTE_WIDTH + 1) - 1 downto 0);

  signal rolodex_entry_valid    : std_logic;
  signal rolodex_entry_ready    : std_logic;
  signal rolodex_entry_mark     : std_logic;
  signal rolodex_entry          : std_logic_vector(FRAME_IDX_WIDTH-1 downto 0);
  signal rolodex_entry_marked   : std_logic;

  signal rolodex_insert_valid   : std_logic;
  signal rolodex_insert_ready   : std_logic;
  signal rolodex_insert_entry   : std_logic_vector(FRAME_IDX_WIDTH-1 downto 0);

  signal rolodex_delete_valid   : std_logic;
  signal rolodex_delete_ready   : std_logic;
  signal rolodex_delete_entry   : std_logic_vector(FRAME_IDX_WIDTH-1 downto 0);

  type state_type is (RESET_ST, IDLE, FAIL, CLEAR_FRAMES, CLEAR_FRAMES_CHECK,
                      RESERVE_PT, RESERVE_PT_CHECK, PT0_INIT,

                      MMU_GET_L1_ADDR, MMU_GET_L1_DAT,
                      MMU_GET_L2_ADDR, MMU_GET_L2_DAT, MMU_RESP,
                      MMU_SET_L2_ADDR, MMU_SET_L2_DAT,

                      VMALLOC, VMALLOC_CHECK_PT0, VMALLOC_CHECK_PT0_DATA,
                      VMALLOC_RESERVE_FRAME, VMALLOC_FINISH,

                      VFREE, VFREE_FINISH,

                      SET_PTE_RANGE,
                      SET_PTE_RANGE_L1_ADDR, SET_PTE_RANGE_L1_CHECK,
                      SET_PTE_RANGE_L1_UPDATE_ADDR, SET_PTE_RANGE_L1_UPDATE_DAT,
                      SET_PTE_RANGE_FRAME, SET_PTE_RANGE_L2_CHECK_ADDR,
                      SET_PTE_RANGE_L2_UPDATE_ADDR, SET_PTE_RANGE_L2_UPDATE_DAT,

                      PT_DEL, PT_DEL_MARK_BM_ADDR, PT_DEL_MARK_BM_DATA,
                      PT_DEL_ROLODEX, PT_DEL_FRAME,

                      PT_NEW, PT_NEW_REQ_BM, PT_NEW_CHECK_BM, PT_NEW_MARK_BM_ADDR,
                      PT_NEW_FRAME, PT_NEW_FRAME_CHECK,
                      PT_NEW_MARK_BM_DATA, PT_NEW_CLEAR_ADDR, PT_NEW_CLEAR_DATA,

                      PT_FRAME_INIT_ADDR, PT_FRAME_INIT_DATA, PT_FRAME_INIT_ROLODEX );
  constant STATE_STACK_DEPTH : natural := 5;
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
    addr_vm                     : unsigned(BUS_ADDR_WIDTH-1 downto 0); --TODO: reduce width to VA space
    addr_pt                     : unsigned(BUS_ADDR_WIDTH-1 downto 0);
    size                        : unsigned(BUS_ADDR_WIDTH-1 downto 0);
    pages                       : unsigned(VM_SIZE_L0_LOG2 - PAGE_SIZE_LOG2 - 1 downto 0);
    region                      : unsigned(log2ceil(MEM_REGIONS+1)-1 downto 0);
    arg                         : unsigned(1 downto 0);
    pt_empty                    : std_logic;
    in_mapping                  : std_logic;
    byte_buffer                 : unsigned(BYTE_SIZE-1 downto 0);
    beat                        : unsigned(log2ceil(BUS_BURST_MAX_LEN+1)-1 downto 0);
  end record;

  signal r                      : reg_type;
  signal d                      : reg_type;

begin
  assert PAGE_SIZE_LOG2 >= PT_ENTRIES_LOG2 + log2ceil( DIV_CEIL(PTE_BITS, BYTE_SIZE))
    report "page table does not fit in a single page"
    severity failure;

  assert PAGE_SIZE_LOG2 /= PT_ENTRIES_LOG2 + log2ceil( DIV_CEIL(PTE_BITS, BYTE_SIZE))
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

  assert PTE_SEGMENT + log2ceil(MEM_REGIONS+1)-1 < PAGE_SIZE_LOG2
    report "Too few bits available for segment ID in PTE"
    severity failure;

-- TODO: assert that L1 PT address refers to first possible PT in that frame.

  process (clk) begin
    if rising_edge(clk) then
      if reset = '1' then
        r.state_stack    <= (others => FAIL);
        r.state_stack(0) <= RESET_ST;
      else
        r <= d;
      end if;
    end if;
  end process;

  process (r,
           cmd_region, cmd_addr, cmd_free, cmd_alloc, cmd_realloc, cmd_valid, cmd_size,
           resp_ready,
           frames_cmd_ready, frames_resp_addr, frames_resp_success, frames_resp_valid,
           gap_a_valid, gap_a_size, gap_a_offset, gap_q_ready,
           rolodex_entry_valid, rolodex_entry_marked, rolodex_entry,
           rolodex_insert_ready, rolodex_delete_ready,
           int_bus_wreq_ready, bus_wdat_ready, int_bus_dirty,
           bus_rreq_ready, bus_rdat_data, bus_rdat_last, bus_rdat_valid,
           mmu_req_valid, mmu_req_addr, mmu_resp_ready) is
    variable v : reg_type;
  begin
    v := r;

    resp_success <= '0';
    resp_valid   <= '0';
    resp_addr    <= (others => '0');
    cmd_ready    <= '0';

    frames_cmd_valid  <= '0';
    frames_cmd_region <= (others => 'U');
    frames_cmd_addr   <= (others => 'U');
    frames_cmd_free   <= '0';
    frames_cmd_alloc  <= '0';
    frames_cmd_find   <= '0';
    frames_cmd_clear  <= '0';
    frames_resp_ready <= '0';

    gap_q_valid       <= '0';
    gap_q_holes       <= (others => 'U');
    gap_q_size        <= (others => 'U');
    gap_a_ready       <= '0';

    rolodex_entry_ready  <= '0';
    rolodex_entry_mark   <= '0';
    rolodex_insert_valid <= '0';
    rolodex_insert_entry <= (others => 'U');
    rolodex_delete_valid <= '0';
    rolodex_delete_entry <= (others => 'U');

    int_bus_wreq_valid   <= '0';
    int_bus_wreq_addr    <= (others => 'U'); --slv(addr);
    int_bus_wreq_len     <= (others => 'U'); --slv(to_unsigned(1, bus_wreq_len'length));
    int_bus_wreq_barrier <= '1';

    bus_wdat_valid  <= '0';
    bus_wdat_data   <= (others => 'U');
    bus_wdat_strobe <= (others => 'U');
    bus_wdat_last   <= 'U';

    bus_rreq_valid  <= '0';
    bus_rreq_addr   <= (others => 'U'); --slv(addr);
    bus_rreq_len    <= (others => 'U'); --slv(to_unsigned(1, bus_wreq_len'length));

    bus_rdat_ready  <= '0';

    mmu_req_ready   <= '0';

    mmu_resp_valid  <= '0';
    mmu_resp_addr   <= (others => 'U');

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
      mmu_req_ready <= '1';
      if mmu_req_valid = '1' then
        v.state_stack := push_state(v.state_stack, MMU_GET_L1_ADDR);
        v.addr_vm     := u(mmu_req_addr);

      elsif cmd_valid = '1' then

        if cmd_alloc = '1' then
          if unsigned(cmd_region) = 0 then
            -- TODO: host allocation
            v.state_stack(0) := FAIL;
          else
            v.state_stack := push_state(v.state_stack, VMALLOC);
          end if;

        elsif cmd_free = '1' then
          v.state_stack   := push_state(v.state_stack, VFREE);

        elsif cmd_realloc = '1' then
          -- TODO
          v.state_stack(0) := FAIL;
        end if;
      end if;

    -- === START OF FRAME ALLOCATION ROUTINE ===
    -- Allocates a frame for an already mapped virtual address, `addr_vm`.
    -- Response is given on MMU channel.

    when MMU_GET_L1_ADDR =>
      -- Get the L1 PTE
      bus_rreq_addr  <= slv(ADDR_BUS_ALIGN(VA_TO_PTE(PT_ADDR, v.addr_vm, 1)));
      bus_rreq_len   <= slv(to_unsigned(1, bus_rreq_len'length));
      -- Wait for any outstanding writes to be completed.
      if int_bus_dirty = '0' then
        bus_rreq_valid <= '1';
        if bus_rreq_ready = '1' then
          v.state_stack(0) := MMU_GET_L1_DAT;
        end if;
      end if;

    when MMU_GET_L1_DAT =>
      bus_rdat_ready <= '1';
      if bus_rdat_valid = '1' then
        -- Check PRESENT bit of PTE referred to by addr_vm.
        if bus_rdat_data(
             PTE_SIZE * int(ADDR_BUS_OFFSET(VA_TO_PTE(PT_ADDR, v.addr_vm, 1)))
             + PTE_PRESENT
           ) /= '1'
        then
          -- Given address isn't mapped.
          v.state_stack(0) := FAIL;
        else
          -- Get address of L2 page table from the read data.
          v.addr_pt := align_beq(
              EXTRACT(
                unsigned(bus_rdat_data),
                BYTE_SIZE * int(ADDR_BUS_OFFSET(VA_TO_PTE(PT_ADDR, v.addr_vm, 1))),
                BYTE_SIZE * PTE_SIZE
              ),
              PT_SIZE_LOG2);
          v.state_stack(0) := MMU_GET_L2_ADDR;
        end if;
      end if;

    when MMU_GET_L2_ADDR =>
      -- Get the L1 PTE
      bus_rreq_addr  <= slv(ADDR_BUS_ALIGN(VA_TO_PTE(v.addr_pt, v.addr_vm, 2)));
      bus_rreq_len   <= slv(to_unsigned(1, bus_rreq_len'length));
      bus_rreq_valid <= '1';
      if bus_rreq_ready = '1' then
        v.state_stack(0) := MMU_GET_L2_DAT;
      end if;

    when MMU_GET_L2_DAT =>
      if bus_rdat_valid = '1' then

        if bus_rdat_data(
             PTE_SIZE * int(ADDR_BUS_OFFSET(VA_TO_PTE(v.addr_pt, v.addr_vm, 2)))
             + PTE_MAPPED
           ) /= '1'
        then
          -- Given address isn't mapped.
          bus_rdat_ready   <= '1';
          v.state_stack(0) := FAIL;

        elsif bus_rdat_data(
             PTE_SIZE * int(ADDR_BUS_OFFSET(VA_TO_PTE(v.addr_pt, v.addr_vm, 2)))
             + PTE_PRESENT
           ) = '1'
        then
          -- Given address is already present, return the mapping.
          mmu_resp_valid  <= '1';
          mmu_resp_addr   <= slv(align_beq(
              EXTRACT(
                unsigned(bus_rdat_data),
                BYTE_SIZE * int(ADDR_BUS_OFFSET(VA_TO_PTE(v.addr_pt, v.addr_vm, 2))),
                BYTE_SIZE * PTE_SIZE
              ),
              PT_SIZE_LOG2));
          if mmu_resp_ready = '1' then
            bus_rdat_ready <= '1';
            v.state_stack  := pop_state(v.state_stack);
          end if;

        else
          -- Get segment of mapped address from the read data.
          frames_cmd_valid  <= '1';
          frames_cmd_find   <= '1';
          if log2ceil(MEM_REGIONS) > 0 then
            frames_cmd_region <= slv(
                resize(
                  EXTRACT(
                    unsigned(bus_rdat_data),
                    BYTE_SIZE * int(ADDR_BUS_OFFSET(VA_TO_PTE(v.addr_pt, v.addr_vm, 2))) + PTE_SEGMENT,
                    log2ceil(MEM_REGIONS+1)
                  ) - 1,
                  log2ceil(MEM_REGIONS)));
          end if;
          -- Store all flags of the mapping (skip the address itself)
          v.addr            := resize(
              EXTRACT(
                unsigned(bus_rdat_data),
                BYTE_SIZE * int(ADDR_BUS_OFFSET(VA_TO_PTE(v.addr_pt, v.addr_vm, 2))),
                PAGE_SIZE_LOG2
              ),
              v.addr'length
            );
          if frames_cmd_ready = '1' then
            bus_rdat_ready   <= '1';
            v.state_stack(0) := MMU_RESP;
          end if;
        end if;
      end if;

    when MMU_RESP =>
      -- Respond with the frame address as soon as possible.
      mmu_resp_valid <= frames_resp_valid;
      mmu_resp_addr  <= frames_resp_addr;
      if mmu_resp_ready = '1' then
        v.state_stack(0) := MMU_SET_L2_ADDR;
      end if;

    when MMU_SET_L2_ADDR =>
      -- Update the PTE.
      int_bus_wreq_valid <= '1';
      int_bus_wreq_addr  <= slv(ADDR_BUS_ALIGN(VA_TO_PTE(v.addr_pt, v.addr_vm, 2)));
      int_bus_wreq_len   <= slv(to_unsigned(1, int_bus_wreq_len'length));
      if int_bus_wreq_ready = '1' then
        v.state_stack(0) := MMU_SET_L2_DAT;
      end if;

    when MMU_SET_L2_DAT =>
      bus_wdat_valid  <= frames_resp_valid;
      bus_wdat_last   <= '1';
      -- Duplicate the address over the data bus.
      for i in 0 to BUS_DATA_BYTES/PTE_SIZE-1 loop
        -- Copy the existing flags.
        bus_wdat_data(PTE_WIDTH * (i+1) - 1 downto PTE_WIDTH * i) <= slv(v.addr);
        -- Mark the entry as present.
        bus_wdat_data(PTE_WIDTH * i + PTE_PRESENT) <= '1';
        -- Map to the allocated frame.
        bus_wdat_data(PTE_WIDTH * (i+1) - 1 downto PTE_WIDTH * i + PAGE_SIZE_LOG2)
            <= slv(EXTRACT(u(frames_resp_addr), PAGE_SIZE_LOG2, PTE_WIDTH-PAGE_SIZE_LOG2));
      end loop;
      -- Use strobe to write the correct entry.
      bus_wdat_strobe <= slv(OVERLAY(
          not to_unsigned(0, PTE_SIZE),
          to_unsigned(0, bus_wdat_strobe'length),
          int(ADDR_BUS_OFFSET(VA_TO_PTE(v.addr_pt, v.addr_vm, 2)))));
      if bus_wdat_ready = '1' then
        frames_resp_ready <= '1';
        v.state_stack     := pop_state(v.state_stack);
      end if;

    -- === START OF VMALLOC ROUTINE ===
    -- Find big enough free chunk in virtual address space.
    -- Allocate single frame for start of allocation in the given region.
    -- `addr_vm' will contain virtual address of allocation.

    when VMALLOC =>
      -- Request the L0 page table to find a high-level gap.
      -- TODO: find gaps in lower level page tables.
      v.addr           := PT_ADDR;
      -- Ignore bits that are used for indexing with this page level,
      -- and bits for unsupported sizes.
      v.size           := resize(
                            shift_left(
                              shift_right_round_up(
                                resize(unsigned(cmd_size), VM_SIZE_L0_LOG2),
                                VM_SIZE_L1_LOG2
                              ),
                              VM_SIZE_L1_LOG2),
                            v.size'length);
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
      gap_q_valid    <= bus_rdat_valid;
      bus_rdat_ready <= gap_q_ready;
      gap_q_holes    <= slv(TAKE_EVERY(u(bus_rdat_data), PTE_WIDTH, PTE_MAPPED));
      gap_q_size     <= slv(CLAMP_PTES_PER_BUS(shift_right(v.size, VM_SIZE_L1_LOG2)));
      gap_a_ready    <= '1';

      if gap_a_valid = '1' then
        if u(gap_a_offset) /= 0 then
          -- New gap was started
          v.addr_vm := PTE_TO_VA(
              PT_INDEX(v.addr) + u(gap_a_offset),
              1);
          -- Subtract the gap size from requested size.
          -- Ignore bits that are used for indexing with this page level,
          -- and bits for unsupported sizes.
          v.size := resize(
              shift_left(
                shift_right_round_up(
                  resize(unsigned(cmd_size), VM_SIZE_L0_LOG2),
                  VM_SIZE_L1_LOG2
                ) - u(gap_a_size),
                VM_SIZE_L1_LOG2),
              v.size'length);
        else
          -- Subtract the gap size from leftover size.
          -- Ignore bits that are used for indexing with this page level,
          -- and bits for unsupported sizes.
          v.size := resize(
              shift_left(
                shift_right(
                  resize(v.size, VM_SIZE_L0_LOG2),
                  VM_SIZE_L1_LOG2
                ) - u(gap_a_size),
                VM_SIZE_L1_LOG2),
              v.size'length);
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
--      frames_cmd_valid  <= '1';
--      frames_cmd_find   <= '1';
--      frames_cmd_region <= slv(resize(unsigned(cmd_region) - 1, frames_cmd_region'length));

--      if frames_cmd_ready = '1' then
        cmd_ready        <= '1';
        -- addr_vm  : virtual base address to start at
        -- cmd_size : length to set
        v.state_stack    := push_state(v.state_stack, SET_PTE_RANGE);
        v.state_stack(1) := VMALLOC_FINISH;
        v.size           := unsigned(cmd_size);
        v.pages          := PAGE_COUNT(unsigned(cmd_size));
        v.region         := unsigned(cmd_region);
        -- Take first page mapping from frame allocator
        v.arg            := to_unsigned(1, v.arg'length);
--      end if;

    when VMALLOC_FINISH =>
      resp_success <= '1';
      resp_addr    <= slv(v.addr_vm);
      resp_valid   <= '1';
      if resp_ready = '1' then
        v.state_stack := pop_state(v.state_stack);
      end if;


    -- === START OF VFREE ROUTINE ===

    when VFREE =>
      v.state_stack(0) := VFREE_FINISH;
      v.state_stack    := push_state(v.state_stack, SET_PTE_RANGE);
      v.addr_vm        := PAGE_BASE(unsigned(cmd_addr));
      v.arg            := (others => '0');
      v.arg(1)         := '1'; -- deallocate
      cmd_ready        <= '1';

    when VFREE_FINISH =>
      resp_success <= '1';
      resp_addr    <= (others => '0');
      resp_valid   <= '1';
      if resp_ready = '1' then
        v.state_stack := pop_state(v.state_stack);
      end if;


    -- === START OF SET_PTE_RANGE ROUTINE ===
    -- Set mapping for a range of virtual addresses, create page tables as needed.
    -- `addr_vm` contains address to start mapping at.
    -- `region`  region is recorded in the page tables, and used for allocation.
    -- `pages`   must be initialized to the number of pages in the mapping.
    -- arg(0) = '1' -> Take first frame from frame allocator.
    -- arg(1) = '1' -> Deallocate
    -- arg(2) = '1' -> Conditional allocation: stop when already mapped. TODO

    when SET_PTE_RANGE =>
      v.addr           := v.addr_vm;
      -- This will be set when v.addr reaches the intended mapping.
      v.in_mapping     := '0';
      if v.arg(1) = '1' then
        -- Length for deallocation is not known in advance, set it to maximum.
        v.pages        := not to_unsigned(0, v.pages'length);
        -- Start at beginning of L2 page table,
        -- to check whether it is in use by another allocation.
        v.addr         := align_beq(v.addr_vm, VM_SIZE_L1_LOG2);
      end if;
      v.state_stack(0) := SET_PTE_RANGE_L1_ADDR;

    when SET_PTE_RANGE_L1_ADDR =>
      -- Get the L1 PTE
      bus_rreq_addr    <= slv(ADDR_BUS_ALIGN(VA_TO_PTE(PT_ADDR, v.addr, 1)));
      bus_rreq_len     <= slv(to_unsigned(1, bus_rreq_len'length));

      -- Start off by assuming the L2 page table is unused.
      v.pt_empty       := '1';

      -- Wait for any outstanding writes to be completed.
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
        -- Ignore (overwrite) any present entries in the L2 table for simplicity of implementation.

        -- Get PT address from the read data.
        v.addr_pt := align_beq(
            EXTRACT(
              unsigned(bus_rdat_data),
              BYTE_SIZE * int(ADDR_BUS_OFFSET(VA_TO_PTE(PT_ADDR, v.addr, 1))),
              BYTE_SIZE * PTE_SIZE
            ),
            PT_SIZE_LOG2);
        if v.arg(1) = '1' then
          -- Deallocate; request the mapping to do so.
          v.state_stack(0)   := SET_PTE_RANGE_L2_CHECK_ADDR;
        else
          -- Allocate
          if v.arg(0) = '1' then
            -- Request a frame for this mapping.
            v.state_stack(0) := SET_PTE_RANGE_FRAME;
          else
            -- Start updating the L2 page table.
            v.state_stack(0) := SET_PTE_RANGE_L2_UPDATE_ADDR;
          end if;
        end if;

        if bus_rdat_data(
             BYTE_SIZE * int(ADDR_BUS_OFFSET(VA_TO_PTE(PT_ADDR, v.addr, 1)))
             + PTE_PRESENT
           ) = '0'
        then
          -- L2 PT does not exist, need to allocate one.
          v.state_stack      := push_state(v.state_stack, PT_NEW);
        elsif v.arg(1) = '0' then
          -- Indicate the L1 entry does not need updating.
          v.pt_empty         := '0';
        end if;
      end if;

    when SET_PTE_RANGE_L1_UPDATE_ADDR =>
      -- A new PT was allocated, update the corresponding L1 entry.
      int_bus_wreq_valid <= '1';
      int_bus_wreq_addr  <= slv(ADDR_BUS_ALIGN(VA_TO_PTE(PT_ADDR, PAGE_BASE(v.addr)-1, 1)));
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
        if v.arg(1) = '0' then
          -- Mark the entry as mapped and present
          bus_wdat_data(PTE_WIDTH * i + PTE_MAPPED)  <= '1';
          bus_wdat_data(PTE_WIDTH * i + PTE_PRESENT) <= '1';
        end if;
      end loop;
      -- Use strobe to write the correct entry
      bus_wdat_strobe <= slv(OVERLAY(
          not to_unsigned(0, PTE_SIZE),
          to_unsigned(0, bus_wdat_strobe'length),
          int(ADDR_BUS_OFFSET(VA_TO_PTE(PT_ADDR, PAGE_BASE(v.addr)-1, 1)))));
      if bus_wdat_ready = '1' then
        if v.pages = 0 then
          -- Done (de)allocating.
          v.state_stack    := pop_state(v.state_stack);
        else
          v.state_stack(0) := SET_PTE_RANGE_L1_ADDR;
        end if;
      end if;

    when SET_PTE_RANGE_FRAME =>
      -- Allocate a single frame for the mapping.
      frames_cmd_valid   <= '1';
      frames_cmd_find    <= '1';
      frames_cmd_region  <= slv(resize(v.region - 1, frames_cmd_region'length));
      if frames_cmd_ready = '1' then
        v.state_stack(0) := SET_PTE_RANGE_L2_UPDATE_ADDR;
      end if;

    when SET_PTE_RANGE_L2_CHECK_ADDR =>
      -- Request the existing mapping, to do stuff with it later on.
      bus_rreq_valid     <= '1';
      bus_rreq_addr      <= slv(ADDR_BUS_ALIGN(VA_TO_PTE(v.addr_pt, v.addr, 2)));
      bus_rreq_len       <= slv(to_unsigned(1, int_bus_wreq_len'length));
      if bus_rreq_ready = '1' then
        v.state_stack(0) := SET_PTE_RANGE_L2_UPDATE_ADDR;
      end if;

    when SET_PTE_RANGE_L2_UPDATE_ADDR =>
      -- L2 page table entry address
      int_bus_wreq_addr  <= slv(ADDR_BUS_ALIGN(VA_TO_PTE(v.addr_pt, v.addr, 2)));
      int_bus_wreq_len   <= slv(to_unsigned(1, int_bus_wreq_len'length));

      if  shift_right(v.addr,    VM_SIZE_L2_LOG2 + log2ceil(BUS_DATA_BYTES / PTE_SIZE))
        = shift_right(v.addr_vm, VM_SIZE_L2_LOG2 + log2ceil(BUS_DATA_BYTES / PTE_SIZE))
      then
        -- Current address is in the mapping of interest.
        v.in_mapping  := '1';
      end if;

      if v.in_mapping = '0' then
        -- Skip write if before the start address, or after the end address.
        v.state_stack(0) := SET_PTE_RANGE_L2_UPDATE_DAT;
      else
        if int_bus_wreq_ready = '1' then
          v.state_stack(0) := SET_PTE_RANGE_L2_UPDATE_DAT;
        end if;
        if v.arg(1) = '1' then
          -- Wait until read is done to prevent deadlock
          int_bus_wreq_valid <= bus_rdat_valid;
        else
          int_bus_wreq_valid <= '1';
        end if;
      end if;

    when SET_PTE_RANGE_L2_UPDATE_DAT =>
      -- Update the L2 page table entries (whole bus word)
      -- TODO: skip write if before the start address, or when pages=0
      if r.in_mapping = '0' then
        -- Not inside of mapping. This only happens with deallocation.
        -- Consume requested data, do not write.
        bus_rdat_ready    <= '1';
        bus_wdat_valid    <= '0';
      elsif v.arg(1) = '1' then
        -- Deallocate
        bus_rdat_ready    <= bus_wdat_ready;
        bus_wdat_valid    <= bus_rdat_valid;
      elsif v.arg(0) = '1' then
        -- Use allocated frame in mapping.
        frames_resp_ready <= bus_wdat_ready;
        bus_wdat_valid    <= frames_resp_valid;
      else
        -- Create mapping without allocation.
        bus_wdat_valid    <= '1';
      end if;
      bus_wdat_last   <= '1';

      -- Loop over the PTEs on the data bus.
      for i in 0 to BUS_DATA_BYTES/PTE_SIZE-1 loop

        -- Default to a zero'd entry
        bus_wdat_data(PTE_WIDTH * (i+1) - 1 downto PTE_WIDTH * i) <= (others => '0');

        if v.arg(1) = '1' then
          -- Deallocate
          if v.in_mapping = '0' and
            bus_rdat_data(PTE_WIDTH * i + PTE_MAPPED) = '1'
          then
            -- An entry is mapped outside of the deleted mapping.
            v.pt_empty   := '0';
          end if;
          if bus_rdat_data(PTE_WIDTH * i + PTE_BOUNDARY) = '1' then
            -- Last entry of the mapping, number of pages now known.
            v.pages := to_unsigned(i+1, v.pages'length);
            v.in_mapping := '0';
          end if;
        end if;

        -- First entry
        if v.arg(0) = '1' and -- Allocate first entry.
          -- This offset is the first entry for the mapping.
          PAGE_BASE(v.addr) + shift_left(to_unsigned(i, v.addr_vm'length), VM_SIZE_L2_LOG2) = PAGE_BASE(v.addr_vm)
        then
          -- Map to the allocated frame.
          bus_wdat_data(PTE_WIDTH * (i+1) - 1 downto PTE_WIDTH * i) <= frames_resp_addr;
          -- Mark the entry as present.
          bus_wdat_data(PTE_WIDTH * i + PTE_PRESENT) <= '1';
        end if;

        -- Last entry
        if r.pages - i - 1 = 0 then
          bus_wdat_data(PTE_WIDTH * i + PTE_BOUNDARY) <= '1';
        end if;

        -- Mark as mapped / not mapped
        bus_wdat_data(PTE_WIDTH * i + PTE_MAPPED)  <= not v.arg(1);

        -- Write region
        bus_wdat_data(PTE_WIDTH * i + PTE_SEGMENT + v.region'length - 1 downto PTE_WIDTH * i + PTE_SEGMENT) <= slv(v.region);
      end loop;

      -- current = v.addr
      -- start   = v.addr_vm
      -- target  = v.addr_vm + v.size
      -- todo    = pages

      -- Use strobe to write the correct entries.
      if 0 = ADDR_BUS_OFFSET(VA_TO_PTE(v.addr_pt, v.addr, 2)) then
        -- First PTE is aligned to start of bus word.
        -- Shift a vector of ones to the right to get the correct strobe.
        bus_wdat_strobe <= slv(
            shift_right(
              not to_unsigned(0, bus_wdat_strobe'length),
              PTE_SIZE * ((BUS_DATA_BYTES / PTE_SIZE) -
                -- Amount of PTEs in this bus word
                int(CLAMP(
                  -- Amount of PTEs left
                  v.pages,
                  BUS_DATA_BYTES / PTE_SIZE)))));
      else
        -- First PTE is not aligned to bus word. This should not currently happen.
        -- TODO: allow these unaligned allocations.
        v.state_stack(0)   := FAIL;
      end if;

      -- Check for handshake
      if
        (
          r.in_mapping = '0'
          and bus_rdat_valid = '1'
        ) or (
          r.in_mapping = '1' and v.arg(1) = '1'
          and bus_rdat_valid = '1' and bus_wdat_ready = '1'
        ) or (
          r.in_mapping = '1' and v.arg(0) = '1'
          and frames_resp_valid = '1' and bus_wdat_ready = '1'
        ) or (
          r.in_mapping = '1' and v.arg(1) = '0' and v.arg(0) = '0'
          and bus_wdat_ready = '1'
        )
      then
        -- Do not try to use allocated frame on next iteration.
        v.arg(0) := '0';

        -- Next address is increased by the size addressable by the written entries.
        v.addr := PAGE_BASE(v.addr) +
            shift_left(
              to_unsigned(BUS_DATA_BYTES / PTE_SIZE, v.addr'length),
              VM_SIZE_L2_LOG2);

        -- Update pages left to process.
        v.pages  := v.pages -
            -- Amount of PTEs in this bus word
            CLAMP(
              -- Amount of PTEs left
              v.pages,
              BUS_DATA_BYTES / PTE_SIZE);

        if v.arg(1) = '0' and v.pages = 0 then
          -- Allocated enough space.
          if v.pt_empty = '1' then
            -- New PT, update L1 entry.
            v.state_stack(0) := SET_PTE_RANGE_L1_UPDATE_ADDR;
          else
            -- Allocation is done.
            v.state_stack    := pop_state(v.state_stack);
          end if;

        -- Not done for allocation, maybe done for deallocation.
        elsif EXTRACT(v.addr, PAGE_SIZE_LOG2, PT_ENTRIES_LOG2) = 0 then
          -- At end of L2 PT, go to next table through L1.
          if v.pt_empty = '1' then
            -- New PT, or delete PT: update L1 entry.
            v.state_stack(0) := SET_PTE_RANGE_L1_UPDATE_ADDR;
            if v.arg(1) = '1' then
              -- Delete page table.
              v.state_stack  := push_state(v.state_stack, PT_DEL);
            end if;

          -- No new or deleted PT.
          elsif v.arg(1) = '1' then
            -- Done deallocating.
            v.state_stack    := pop_state(v.state_stack);
          else
            -- Not done allocating, continue to next L1 entry.
            v.state_stack(0) := SET_PTE_RANGE_L1_ADDR;
          end if;

        -- Not done in L2 table.
        elsif v.arg(1) = '1' then
          -- Continue with next PTE, check for end of mapping.
          v.state_stack(0)   := SET_PTE_RANGE_L2_CHECK_ADDR;
        else
          -- Continue with next PTE.
          v.state_stack(0)   := SET_PTE_RANGE_L2_UPDATE_ADDR;
        end if;

      else
        -- No handshake, do not update in_mapping just yet.
        v.in_mapping := r.in_mapping;
        v.pt_empty   := r.pt_empty;
      end if;


    -- === START OF FRAME_INIT ROUTINE ===
    -- Clear the usage bitmap of the frame at `addr' and add it to the rolodex.
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
        if (PT_PER_FRAME <= BUS_DATA_WIDTH) or (PAGE_OFFSET(v.addr) * BYTE_SIZE > PT_PER_FRAME) then
          -- Entire bitmap has been initialized
          v.state_stack(0) := PT_FRAME_INIT_ROLODEX;
        else
          -- Need another write
          v.state_stack(0) := PT_FRAME_INIT_ADDR;
        end if;
      end if;

    when PT_FRAME_INIT_ROLODEX =>
      rolodex_insert_entry <= ADDR_TO_ROLODEX(v.addr);
      rolodex_insert_valid <= '1';
      if rolodex_insert_ready = '1' then
        v.state_stack := pop_state(v.state_stack);
      end if;

    -- === START OF PT_DEL ROUTINE ===
    -- Mark the page table at `addr_pt` as unused and remove the frame from
    -- the PT pool if the frame contains no more page tables.

    when PT_DEL =>
      bus_rreq_addr  <= slv(PAGE_BASE(v.addr_pt) + PT_BITMAP_IDX(v.addr_pt) / BUS_DATA_WIDTH);
      bus_rreq_len   <= slv(to_unsigned(1, bus_rreq_len'length));
      bus_rreq_valid <= '1';
      if bus_rreq_ready = '1' then
        v.state_stack(0) := PT_DEL_MARK_BM_ADDR;
      end if;

    when PT_DEL_MARK_BM_ADDR =>
      -- Set address for marking bit in bitmap
      int_bus_wreq_valid <= bus_rdat_valid;
      bus_rdat_ready     <= int_bus_wreq_ready;
      int_bus_wreq_addr  <= slv(PAGE_BASE(v.addr_pt) + PT_BITMAP_IDX(v.addr_pt) / BUS_DATA_WIDTH);
      int_bus_wreq_len   <= slv(to_unsigned(1, int_bus_wreq_len'length));
      -- Copy the byte that has to be written back.
      v.byte_buffer      := EXTRACT(
          u(bus_rdat_data),
          int(align_beq(PT_BITMAP_IDX(v.addr_pt), BYTE_SIZE) mod BUS_DATA_WIDTH),
          BYTE_SIZE);
      -- Mark PT as unused in bitmap's byte.
      v.byte_buffer(int(PT_BITMAP_IDX(v.addr_pt) mod BYTE_SIZE)) := '0';
      if int_bus_wreq_ready = '1' then
        -- TODO: make this work for bitmaps > BUS_DATA_WIDTH
        if BIT_COUNT(bus_rdat_data(work.Utils.min(PT_PER_FRAME, BUS_DATA_WIDTH) downto 0)) = 1 then
          -- This was the last page table in the frame, delete it.
          v.state_stack(0) := PT_DEL_ROLODEX;
        else
          v.state_stack(0) := PT_DEL_MARK_BM_DATA;
        end if;
      end if;

    when PT_DEL_ROLODEX =>
      rolodex_delete_entry <= ADDR_TO_ROLODEX(v.addr_pt);
      rolodex_delete_valid <= '1';
      if rolodex_delete_ready = '1' then
        v.state_stack(0) := PT_DEL_FRAME;
      end if;

    when PT_DEL_FRAME =>
      frames_cmd_valid <= '1';
      frames_cmd_free  <= '1';
      frames_cmd_addr  <= slv(PAGE_BASE(v.addr_pt));
      if frames_cmd_ready = '1' then
        v.state_stack(0) := PT_DEL_MARK_BM_DATA;
      end if;

    when PT_DEL_MARK_BM_DATA =>
      bus_wdat_valid  <= '1';
      for i in 0 to BUS_DATA_BYTES-1 loop
        bus_wdat_data(BYTE_SIZE*(i+1)-1 downto BYTE_SIZE*i) <= slv(v.byte_buffer);
      end loop;
      bus_wdat_strobe <= (others => '0');
      -- Get page table number referenced by addr and figure out which byte of the bitmap it is in.
      bus_wdat_strobe(int(
        div_floor(
          PT_BITMAP_IDX(v.addr_pt) mod BUS_DATA_WIDTH,
          BYTE_SIZE)
        )) <= '1';
      bus_wdat_last <= '1';
      if bus_wdat_ready = '1' then
        v.state_stack := pop_state(v.state_stack);
      end if;


    -- === START OF PT_NEW ROUTINE ===
    -- Find a free spot for a page table.
    -- mark it as used, and initialize the page table.
    -- `addr_pt' will contain the base address of the new page table.
    -- `addr` remains unchanged.

    when PT_NEW =>
      -- Use addr_pt to store addr
      v.addr_pt          := v.addr;
      -- Mark current rolodex entry, to detect wrap around
      rolodex_entry_mark <= '1';
      if rolodex_entry_valid = '1' and int_bus_dirty = '0' then
        v.state_stack(0) := PT_NEW_REQ_BM;
      end if;

    when PT_NEW_REQ_BM =>
      -- Find a free spot for a PT
      v.addr         := ROLODEX_TO_ADDR(rolodex_entry);
      bus_rreq_addr  <= slv(v.addr);
      bus_rreq_len   <= slv(to_unsigned(1, bus_rreq_len'length));
      -- TODO implement finding empty spots past BUS_DATA_WIDTH entries
      if rolodex_entry_valid = '1' then
        if rolodex_entry_marked = '1' then
          -- Tried all existing PT frames.
          v.state_stack(0) := PT_NEW_FRAME;
        else
          bus_rreq_valid <= '1';
          if bus_rreq_ready = '1' then
            v.state_stack(0) := PT_NEW_CHECK_BM;
          end if;
        end if;
      end if;

    when PT_NEW_FRAME =>
      frames_cmd_valid   <= '1';
      frames_cmd_alloc   <= '1';
      frames_cmd_addr    <= slv(PAGE_BASE(PT_ADDR));
      if frames_cmd_ready = '1' then
        v.state_stack(0) := PT_NEW_FRAME_CHECK;
      end if;

    when PT_NEW_FRAME_CHECK =>
      -- Execute the `frame initialize' routine to set bitmap.
      if frames_resp_valid = '1' then
        frames_resp_ready  <= '1';
        if frames_resp_success = '1' then
          v.state_stack(0) := PT_NEW_REQ_BM;
          v.state_stack    := push_state(v.state_stack, PT_FRAME_INIT_ADDR);
          v.addr           := PAGE_BASE(u(frames_resp_addr));
        else
          v.state_stack(0) := FAIL;
        end if;
      end if;

    when PT_NEW_CHECK_BM =>
      -- Load the adjacent bitmap bits before marking a bit.
      -- We need this, because the write strobe has byte granularity.
      bus_rdat_ready <= '1';
      if bus_rdat_valid = '1' then
        for i in 0 to work.Utils.min(PT_PER_FRAME, BUS_DATA_WIDTH) loop
          if i = work.Utils.min(PT_PER_FRAME, BUS_DATA_WIDTH) then
            -- All checked places are occupied in this frame
            -- Try next entry in rolodex
            rolodex_entry_ready <= '1';
            v.state_stack(0) := PT_NEW_REQ_BM;
            exit;
          end if;
          if bus_rdat_data(i) = '0' then
            -- Bit 0 refers to the first possible page table in this frame.
            v.state_stack(0) := PT_NEW_MARK_BM_ADDR;
            v.addr           := OVERLAY(
                                    shift_left(
                                        to_unsigned(i+PT_FIRST_NR, PAGE_SIZE_LOG2),
                                        PT_SIZE_LOG2),
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
          PT_BITMAP_IDX(v.addr),
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
      if v.beat = 1 then
        bus_wdat_last <= '1';
      else
        bus_wdat_last <= '0';
      end if;
      if bus_wdat_ready = '1' then
        if v.beat = 1 then
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
        -- One beat processed
        v.beat := v.beat - 1;
      end if;

    when others =>
      resp_valid   <= '1';
      resp_success <= '0';

    end case;

    d <= v;
  end process;

  ptframes : MMRolodex
    generic map (
      MAX_ENTRIES                 => DIV_CEIL(PT_MAX_AMOUNT, PT_PER_FRAME),
      ENTRY_WIDTH                 => FRAME_IDX_WIDTH
    )
    port map (
      clk                         => clk,
      reset                       => reset,

      entry_valid                 => rolodex_entry_valid,
      entry_ready                 => rolodex_entry_ready,
      entry_mark                  => rolodex_entry_mark,
      entry                       => rolodex_entry,
      entry_marked                => rolodex_entry_marked,

      insert_valid                => rolodex_insert_valid,
      insert_ready                => rolodex_insert_ready,
      insert_entry                => rolodex_insert_entry,

      delete_valid                => rolodex_delete_valid,
      delete_ready                => rolodex_delete_ready,
      delete_entry                => rolodex_delete_entry
    );

  gapfinder : MMGapFinder
    generic map (
      MASK_WIDTH                  => BUS_DATA_WIDTH / PTE_WIDTH,
      SLV_SLICE                   => false,
      MST_SLICE                   => true
    )
    port map (
      clk                         => clk,
      reset                       => reset,

      req_valid                   => gap_q_valid,
      req_ready                   => gap_q_ready,
      req_holes                   => gap_q_holes,
      req_size                    => gap_q_size,

      gap_valid                   => gap_a_valid,
      gap_ready                   => gap_a_ready,
      gap_offset                  => gap_a_offset,
      gap_size                    => gap_a_size
    );

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


