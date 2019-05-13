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
use work.SimUtils.all;
use work.Buffers.all;
use work.Interconnect.all;
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
    BUS_BURST_MAX_LEN           : natural := 16;

    BUS_RREQ_SLICE              : boolean := false;
    BUS_RDAT_SLICE              : boolean := false
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

  type bus_req_t is record
    valid   : std_logic;
    ready   : std_logic;
    addr    : std_logic_vector(BUS_ADDR_WIDTH-1 downto 0);
    len     : std_logic_vector(BUS_LEN_WIDTH-1 downto 0);
    barrier : std_logic;
    dirty   : std_logic;
  end record bus_req_t;

  type bus_dat_t is record
    valid   : std_logic;
    ready   : std_logic;
    last    : std_logic;
    data    : std_logic_vector(BUS_DATA_WIDTH-1 downto 0);
    strobe  : std_logic_vector(BUS_STROBE_WIDTH-1 downto 0);
  end record bus_dat_t;

  type bus_resp_t is record
    valid   : std_logic;
    ready   : std_logic;
    ok      : std_logic;
  end record bus_resp_t;


  signal my_bus_wreq            : bus_req_t;
  signal my_bus_wreq_b          : bus_req_t;
  signal my_bus_resp_b          : bus_resp_t;
  signal my_bus_wdat            : bus_dat_t;
  signal my_bus_rreq            : bus_req_t;
  signal my_bus_rdat            : bus_dat_t;
  signal pt_bus_rreq            : bus_req_t;
  signal pt_bus_rdat            : bus_dat_t;
  signal mmu_bus_rreq           : bus_req_t;
  signal mmu_bus_rdat           : bus_dat_t;
  signal mmu_bus_wreq           : bus_req_t;
  signal mmu_bus_wreq_b         : bus_req_t;
  signal mmu_bus_resp_b         : bus_resp_t;
  signal mmu_bus_wdat           : bus_dat_t;

  signal pt_reader_cmd_valid    : std_logic;
  signal pt_reader_cmd_ready    : std_logic;
  signal pt_reader_cmd_firstIdx : std_logic_vector(PT_ENTRIES_LOG2 - log2ceil(BUS_DATA_WIDTH / PTE_WIDTH) downto 0);
  signal pt_reader_cmd_lastIdx  : std_logic_vector(PT_ENTRIES_LOG2 - log2ceil(BUS_DATA_WIDTH / PTE_WIDTH) downto 0);
  signal pt_reader_cmd_baseAddr : std_logic_vector(BUS_ADDR_WIDTH-1 downto 0);

  signal pt_reader              : bus_dat_t;

  constant FCI : nat_array := cumulative((
    2 => MM_FRAMES_CMD_WIDTH,
    1 => BUS_ADDR_WIDTH,
    0 => log2ceil(MEM_REGIONS)
  ));

  constant FRI : nat_array := cumulative((
    1 => BUS_ADDR_WIDTH,
    0 => 1
  ));

  signal frames_cmd_region      : std_logic_vector(log2ceil(MEM_REGIONS)-1 downto 0);
  signal frames_cmd_addr        : std_logic_vector(BUS_ADDR_WIDTH-1 downto 0);
  signal frames_cmd_action      : std_logic_vector(MM_FRAMES_CMD_WIDTH-1 downto 0);
  signal frames_cmd_valid       : std_logic;
  signal frames_cmd_ready       : std_logic;
  signal frames_cmd_ser         : std_logic_vector(FCI(FCI'high)-1 downto 0);

  signal dir_frames_cmd_region  : std_logic_vector(log2ceil(MEM_REGIONS)-1 downto 0);
  signal dir_frames_cmd_addr    : std_logic_vector(BUS_ADDR_WIDTH-1 downto 0);
  signal dir_frames_cmd_action  : std_logic_vector(MM_FRAMES_CMD_WIDTH-1 downto 0);
  signal dir_frames_cmd_valid   : std_logic;
  signal dir_frames_cmd_ready   : std_logic;
  signal dir_frames_cmd_ser     : std_logic_vector(FCI(FCI'high)-1 downto 0);

  signal mmu_frames_cmd_region  : std_logic_vector(log2ceil(MEM_REGIONS)-1 downto 0);
  signal mmu_frames_cmd_addr    : std_logic_vector(BUS_ADDR_WIDTH-1 downto 0);
  signal mmu_frames_cmd_action  : std_logic_vector(MM_FRAMES_CMD_WIDTH-1 downto 0);
  signal mmu_frames_cmd_valid   : std_logic;
  signal mmu_frames_cmd_ready   : std_logic;
  signal mmu_frames_cmd_ser     : std_logic_vector(FCI(FCI'high)-1 downto 0);

  signal frames_resp_addr       : std_logic_vector(BUS_ADDR_WIDTH-1 downto 0);
  signal frames_resp_success    : std_logic;
  signal frames_resp_valid      : std_logic;
  signal frames_resp_ready      : std_logic;
  signal frames_resp_ser        : std_logic_vector(FRI(FRI'high)-1 downto 0);

  signal dir_frames_resp_addr   : std_logic_vector(BUS_ADDR_WIDTH-1 downto 0);
  signal dir_frames_resp_success: std_logic;
  signal dir_frames_resp_valid  : std_logic;
  signal dir_frames_resp_ready  : std_logic;
  signal dir_frames_resp_ser    : std_logic_vector(FRI(FRI'high)-1 downto 0);

  signal mmu_frames_resp_addr   : std_logic_vector(BUS_ADDR_WIDTH-1 downto 0);
  signal mmu_frames_resp_success: std_logic;
  signal mmu_frames_resp_valid  : std_logic;
  signal mmu_frames_resp_ready  : std_logic;
  signal mmu_frames_resp_ser    : std_logic_vector(FRI(FRI'high)-1 downto 0);

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

  type state_mmu_type is (
      RESET_ST, IDLE, FAIL,
      MMU_GET_L1_ADDR, MMU_GET_L1_DAT,
      MMU_GET_L2_ADDR, MMU_GET_L2_DAT, MMU_RESP,
      MMU_SET_L2_ADDR, MMU_SET_L2_DAT );

  type state_type is (
      RESET_ST, IDLE, FAIL, CLEAR_FRAMES, CLEAR_FRAMES_CHECK,
      RESERVE_PT, RESERVE_PT_CHECK, PT0_INIT,

      VMALLOC, VMALLOC_CHECK_PT0, VMALLOC_CHECK_PT0_DATA,
      VMALLOC_RESERVE_FRAME, VMALLOC_FINISH,

      VREALLOC, VREALLOC_MOVE, VREALLOC_FREE, VREALLOC_RESPONSE,

      VFREE, VFREE_FINISH,

      FIND_GAP, FIND_GAP_PT0, FIND_GAP_PT0_DATA,

      SET_PTE_RANGE,
      SET_PTE_RANGE_L1_ADDR, SET_PTE_RANGE_L1_CHECK,
      SET_PTE_RANGE_L1_UPDATE_ADDR, SET_PTE_RANGE_L1_UPDATE_DAT,
      SET_PTE_RANGE_SRC_L1_ADDR, SET_PTE_RANGE_SRC_L2_REQ,
      SET_PTE_RANGE_FRAME, SET_PTE_RANGE_L2_REQ_PT,
      SET_PTE_RANGE_L2_DEALLOC_FRAME_C, SET_PTE_RANGE_L2_DEALLOC_FRAME_R,
      SET_PTE_RANGE_L2_UPDATE_ADDR, SET_PTE_RANGE_L2_UPDATE_DAT,
      SET_PTE_RANGE_FINISH,

      PT_DEL, PT_DEL_MARK_BM_ADDR, PT_DEL_MARK_BM_DATA,
      PT_DEL_ROLODEX, PT_DEL_FRAME, PT_DEL_FRAME_CHECK,

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

  type pt_arg_type is record
    unmap                       : std_logic;
    dealloc                     : std_logic;
    copy                        : std_logic;
    alloc_first                 : std_logic;
  end record;
  constant PT_ARG_DEFAULT : pt_arg_type := ('0', '0', '0', '0');

  type reg_type is record
    state_stack                 : state_stack_type;
    addr                        : unsigned(BUS_ADDR_WIDTH-1 downto 0);
    addr_vm                     : unsigned(BUS_ADDR_WIDTH-1 downto 0); --TODO: reduce width to VA space
    addr_vm_src                 : unsigned(BUS_ADDR_WIDTH-1 downto 0); --TODO: reduce width to VA space
    addr_pt                     : unsigned(BUS_ADDR_WIDTH-1 downto 0);
    size                        : unsigned(BUS_ADDR_WIDTH-1 downto 0);
    pages                       : unsigned(VM_SIZE_L0_LOG2 - PAGE_SIZE_LOG2 - 1 downto 0);
    region                      : unsigned(log2ceil(MEM_REGIONS+1)-1 downto 0);
    pt_arg                      : pt_arg_type;
    pt_empty                    : std_logic;
    in_mapping                  : std_logic;
    pt_reader_outstanding       : std_logic;
    bus_pte_idx                 : unsigned(log2ceil(DIV_CEIL(BUS_DATA_BYTES, PTE_SIZE))-1 downto 0);
    byte_buffer                 : unsigned(BYTE_SIZE-1 downto 0);
    beat                        : unsigned(log2ceil(BUS_BURST_MAX_LEN+1)-1 downto 0);
  end record;

  type reg_mmu_type is record
    state                       : state_mmu_type;
    addr                        : unsigned(BUS_ADDR_WIDTH-1 downto 0);
    addr_vm                     : unsigned(BUS_ADDR_WIDTH-1 downto 0); --TODO: reduce width to VA space
    addr_pt                     : unsigned(BUS_ADDR_WIDTH-1 downto 0);
  end record;

  signal r                      : reg_type;
  signal d                      : reg_type;

  signal r_mmu                  : reg_mmu_type;
  signal d_mmu                  : reg_mmu_type;

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
        r_mmu.state      <= RESET_ST;
      else
        r     <= d;
        r_mmu <= d_mmu;
      end if;
    end if;
  end process;

  process (r,
           cmd_region, cmd_addr, cmd_free, cmd_alloc, cmd_realloc, cmd_valid, cmd_size,
           resp_ready,
           pt_reader_cmd_ready, pt_reader,
           dir_frames_cmd_ready,
           dir_frames_resp_addr, dir_frames_resp_success, dir_frames_resp_valid,
           gap_a_valid, gap_a_size, gap_a_offset, gap_q_ready,
           rolodex_entry_valid, rolodex_entry_marked, rolodex_entry,
           rolodex_insert_ready, rolodex_delete_ready,
           my_bus_wreq, my_bus_wdat,
           my_bus_rreq, my_bus_rdat,
           mmu_req_valid, mmu_req_addr, mmu_resp_ready) is
    variable v : reg_type;
    variable handshake : std_logic;
  begin
    v := r;

    handshake := 'U';

    resp_success <= '0';
    resp_valid   <= '0';
    resp_addr    <= (others => '0');
    cmd_ready    <= '0';

    pt_reader_cmd_valid    <= '0';
    pt_reader_cmd_firstIdx <= (others => 'U');
    pt_reader_cmd_lastIdx  <= (others => 'U');
    pt_reader_cmd_baseAddr <= (others => 'U');
    pt_reader.ready        <= '0';

    dir_frames_cmd_valid  <= '0';
    dir_frames_cmd_region <= (others => 'U');
    dir_frames_cmd_addr   <= (others => 'U');
    dir_frames_cmd_action <= (others => 'U');
    dir_frames_resp_ready <= '0';

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

    my_bus_wreq.valid   <= '0';
    my_bus_wreq.addr    <= (others => 'U'); --slv(addr);
    my_bus_wreq.len     <= (others => 'U'); --slv(to_unsigned(1, bus_wreq_len'length));
    my_bus_wreq.barrier <= '1';

    my_bus_wdat.valid  <= '0';
    my_bus_wdat.data   <= (others => 'U');
    my_bus_wdat.strobe <= (others => 'U');
    my_bus_wdat.last   <= 'U';

    my_bus_rreq.valid  <= '0';
    my_bus_rreq.addr   <= (others => 'U'); --slv(addr);
    my_bus_rreq.len    <= (others => 'U'); --slv(to_unsigned(1, bus_wreq_len'length));

    my_bus_rdat.ready  <= '0';

    if false then
    case v.state_stack(0) is
      when RESET_ST =>
        report "state: RESET_ST" severity note;
      when IDLE =>
        report "state: IDLE" severity note;
      when FAIL =>
        report "state: FAIL" severity note;
      when CLEAR_FRAMES =>
        report "state: CLEAR_FRAMES" severity note;
      when CLEAR_FRAMES_CHECK =>
        report "state: CLEAR_FRAMES_CHECK" severity note;
      when RESERVE_PT =>
        report "state: RESERVE_PT" severity note;
      when RESERVE_PT_CHECK =>
        report "state: RESERVE_PT_CHECK" severity note;
      when PT0_INIT =>
        report "state: PT0_INIT" severity note;
      when VMALLOC =>
        report "state: VMALLOC" severity note;
      when VMALLOC_CHECK_PT0 =>
        report "state: VMALLOC_CHECK_PT0" severity note;
      when VMALLOC_CHECK_PT0_DATA =>
        report "state: VMALLOC_CHECK_PT0_DATA" severity note;
      when VMALLOC_RESERVE_FRAME =>
        report "state: VMALLOC_RESERVE_FRAME" severity note;
      when VMALLOC_FINISH =>
        report "state: VMALLOC_FINISH" severity note;
      when VREALLOC =>
        report "state: VREALLOC" severity note;
      when VREALLOC_MOVE =>
        report "state: VREALLOC_MOVE" severity note;
      when VREALLOC_FREE =>
        report "state: VREALLOC_FREE" severity note;
      when VREALLOC_RESPONSE =>
        report "state: VREALLOC_RESPONSE" severity note;
      when VFREE =>
        report "state: VFREE" severity note;
      when VFREE_FINISH =>
        report "state: VFREE_FINISH" severity note;
      when FIND_GAP =>
        report "state: FIND_GAP" severity note;
      when FIND_GAP_PT0 =>
        report "state: FIND_GAP_PT0" severity note;
      when FIND_GAP_PT0_DATA =>
        report "state: FIND_GAP_PT0_DATA" severity note;
      when SET_PTE_RANGE =>
        report "state: SET_PTE_RANGE" severity note;
      when SET_PTE_RANGE_L1_ADDR =>
        report "state: SET_PTE_RANGE_L1_ADDR" severity note;
      when SET_PTE_RANGE_L1_CHECK =>
        report "state: SET_PTE_RANGE_L1_CHECK" severity note;
      when SET_PTE_RANGE_L1_UPDATE_ADDR =>
        report "state: SET_PTE_RANGE_L1_UPDATE_ADDR" severity note;
      when SET_PTE_RANGE_L1_UPDATE_DAT =>
        report "state: SET_PTE_RANGE_L1_UPDATE_DAT" severity note;
      when SET_PTE_RANGE_SRC_L1_ADDR =>
        report "state: SET_PTE_RANGE_SRC_L1_ADDR" severity note;
      when SET_PTE_RANGE_SRC_L2_REQ =>
        report "state: SET_PTE_RANGE_SRC_L2_REQ" severity note;
      when SET_PTE_RANGE_FRAME =>
        report "state: SET_PTE_RANGE_FRAME" severity note;
      when SET_PTE_RANGE_L2_REQ_PT =>
        report "state: SET_PTE_RANGE_L2_REQ_PT" severity note;
      when SET_PTE_RANGE_L2_DEALLOC_FRAME_C =>
        report "state: SET_PTE_RANGE_L2_DEALLOC_FRAME_C" severity note;
      when SET_PTE_RANGE_L2_DEALLOC_FRAME_R =>
        report "state: SET_PTE_RANGE_L2_DEALLOC_FRAME_R" severity note;
      when SET_PTE_RANGE_L2_UPDATE_ADDR =>
        report "state: SET_PTE_RANGE_L2_UPDATE_ADDR" severity note;
      when SET_PTE_RANGE_L2_UPDATE_DAT =>
        report "state: SET_PTE_RANGE_L2_UPDATE_DAT" severity note;
      when SET_PTE_RANGE_FINISH =>
        report "state: SET_PTE_RANGE_FINISH" severity note;
      when PT_DEL =>
        report "state: PT_DEL" severity note;
      when PT_DEL_MARK_BM_ADDR =>
        report "state: PT_DEL_MARK_BM_ADDR" severity note;
      when PT_DEL_MARK_BM_DATA =>
        report "state: PT_DEL_MARK_BM_DATA" severity note;
      when PT_DEL_ROLODEX =>
        report "state: PT_DEL_ROLODEX" severity note;
      when PT_DEL_FRAME =>
        report "state: PT_DEL_FRAME" severity note;
      when PT_DEL_FRAME_CHECK =>
        report "state: PT_DEL_FRAME_CHECK" severity note;
      when PT_NEW =>
        report "state: PT_NEW" severity note;
      when PT_NEW_REQ_BM =>
        report "state: PT_NEW_REQ_BM" severity note;
      when PT_NEW_CHECK_BM =>
        report "state: PT_NEW_CHECK_BM" severity note;
      when PT_NEW_MARK_BM_ADDR =>
        report "state: PT_NEW_MARK_BM_ADDR" severity note;
      when PT_NEW_FRAME =>
        report "state: PT_NEW_FRAME" severity note;
      when PT_NEW_FRAME_CHECK =>
        report "state: PT_NEW_FRAME_CHECK" severity note;
      when PT_NEW_MARK_BM_DATA =>
        report "state: PT_NEW_MARK_BM_DATA" severity note;
      when PT_NEW_CLEAR_ADDR =>
        report "state: PT_NEW_CLEAR_ADDR" severity note;
      when PT_NEW_CLEAR_DATA =>
        report "state: PT_NEW_CLEAR_DATA" severity note;
      when PT_FRAME_INIT_ADDR =>
        report "state: PT_FRAME_INIT_ADDR" severity note;
      when PT_FRAME_INIT_DATA =>
        report "state: PT_FRAME_INIT_DATA" severity note;
      when PT_FRAME_INIT_ROLODEX =>
        report "state: PT_FRAME_INIT_ROLODEX" severity note;
      when others =>
        report "state: unknown" severity note;
    end case;
    end if;

    case v.state_stack(0) is

    when RESET_ST =>
      v.state_stack(0) := CLEAR_FRAMES;

    when CLEAR_FRAMES =>
      -- Clear the frames utilization bitmap.
      dir_frames_cmd_valid  <= '1';
      dir_frames_cmd_action <= MM_FRAMES_CLEAR;
      if frames_cmd_ready = '1' then
        v.state_stack(0) := CLEAR_FRAMES_CHECK;
      end if;

    when CLEAR_FRAMES_CHECK =>
      -- Check the clear command response.
      dir_frames_resp_ready <= '1';
      if dir_frames_resp_valid = '1' then
        if dir_frames_resp_success = '1' then
          v.state_stack(0) := RESERVE_PT;
        else
          v.state_stack(0) := FAIL;
        end if;
      end if;

    when RESERVE_PT =>
      -- Reserve the designated frame for the root page table.
      dir_frames_cmd_valid  <= '1';
      dir_frames_cmd_action <= MM_FRAMES_ALLOC;
      dir_frames_cmd_addr   <= slv(PAGE_BASE(PT_ADDR));
      if dir_frames_cmd_ready = '1' then
        v.state_stack(0) := RESERVE_PT_CHECK;
      end if;

    when RESERVE_PT_CHECK =>
      -- Check the address of the reserved frame.
      -- Execute the `frame initialize' routine to set bitmap, continue to PT0_INIT.
      dir_frames_resp_ready <= '1';
      if dir_frames_resp_valid = '1' then
        if (dir_frames_resp_success = '1') and (u(dir_frames_resp_addr) = PAGE_BASE(PT_ADDR)) then
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
          v.state_stack   := push_state(v.state_stack, VFREE);

        elsif cmd_realloc = '1' then
          v.state_stack   := push_state(v.state_stack, VREALLOC);
        end if;
      end if;

    -- === START OF VMALLOC ROUTINE ===
    -- Find big enough free chunk in virtual address space.
    -- Allocate single frame for start of allocation in the given region.
    -- `addr_vm' will contain virtual address of allocation.

    when VMALLOC =>
      v.state_stack(0) := VMALLOC_RESERVE_FRAME;
      v.state_stack    := push_state(v.state_stack, FIND_GAP);

    when VMALLOC_RESERVE_FRAME =>
        cmd_ready            <= '1';
        -- addr_vm  : virtual base address to start at
        -- cmd_size : length to set
        v.state_stack(0)     := VMALLOC_FINISH;
        v.state_stack        := push_state(v.state_stack, SET_PTE_RANGE);
        v.pages              := PAGE_COUNT(unsigned(cmd_size));
        v.region             := unsigned(cmd_region);
        v.pt_arg             := PT_ARG_DEFAULT;
        v.pt_arg.alloc_first := '1'; -- Take first page mapping from frame allocator

    when VMALLOC_FINISH =>
      resp_success <= '1';
      resp_addr    <= slv(v.addr_vm);
      -- Only give response after page table updates hit main memory.
      if my_bus_wreq.dirty = '0' then
        resp_valid   <= '1';
        if resp_ready = '1' then
          v.state_stack := pop_state(v.state_stack);
        end if;
      end if;


    -- === START OF VREALLOC ROUTINE ===

    when VREALLOC =>
      v.state_stack(0) := VREALLOC_MOVE;
      v.state_stack    := push_state(v.state_stack, FIND_GAP);

    when VREALLOC_MOVE =>
      -- addr_vm  : virtual base address to start at
      -- cmd_size : length to set
      v.state_stack(0) := VREALLOC_FREE;
      v.state_stack    := push_state(v.state_stack, SET_PTE_RANGE);
      v.pages          := PAGE_COUNT(unsigned(cmd_size));
      v.addr_vm_src    := PAGE_BASE(unsigned(cmd_addr));
      v.pt_arg         := PT_ARG_DEFAULT;
      v.pt_arg.copy    := '1';

    when VREALLOC_FREE =>
      cmd_ready        <= '1';
      v.state_stack(0) := VREALLOC_RESPONSE;
      v.state_stack    := push_state(v.state_stack, SET_PTE_RANGE);
      v.addr_vm_src    := v.addr_vm;
      v.addr_vm        := PAGE_BASE(unsigned(cmd_addr));
      v.pt_arg         := PT_ARG_DEFAULT;
      v.pt_arg.unmap   := '1';

    when VREALLOC_RESPONSE =>
      resp_success <= '1';
      resp_addr    <= slv(v.addr_vm_src);
      -- Only give response after page table updates hit main memory.
      if my_bus_wreq.dirty = '0' then
        resp_valid   <= '1';
        if resp_ready = '1' then
          v.state_stack := pop_state(v.state_stack);
        end if;
      end if;


    -- === START OF VFREE ROUTINE ===

    when VFREE =>
      -- MMU can update page tables and assign new frames.
      -- Make sure we see all those writes.
      -- TODO This could wait indefinitely.
      if mmu_bus_wreq.dirty = '0' then
        v.state_stack(0) := VFREE_FINISH;
        v.state_stack    := push_state(v.state_stack, SET_PTE_RANGE);
      end if;
      v.addr_vm        := PAGE_BASE(unsigned(cmd_addr));
      v.pt_arg         := PT_ARG_DEFAULT;
      v.pt_arg.dealloc := '1';
      v.pt_arg.unmap   := '1';
      cmd_ready        <= '1';

    when VFREE_FINISH =>
      resp_success <= '1';
      resp_addr    <= (others => '0');
      -- Only give response after page table updates hit main memory.
      if my_bus_wreq.dirty = '0' then
        resp_valid   <= '1';
        if resp_ready = '1' then
          v.state_stack := pop_state(v.state_stack);
        end if;
      end if;

    -- === START OF FIND_GAP ROUTINE ===
    -- Find a free contiguous space in VM.
    -- `cmd_size` The requested gap size in bytes. Will be rounded up to some convenient size.
    -- `addr_vm`  Start address of the found gap.
    -- `addr`     Is used internally.
    -- `size`     Is used internally.

    when FIND_GAP =>
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
      v.state_stack(0) := FIND_GAP_PT0;

    when FIND_GAP_PT0 =>
      my_bus_rreq.addr  <= slv(v.addr);
      my_bus_rreq.len   <= slv(to_unsigned(1, my_bus_rreq.len'length));
      my_bus_rreq.valid <= '1';
      if my_bus_rreq.ready = '1' then
        v.state_stack(0) := FIND_GAP_PT0_DATA;
      end if;

    when FIND_GAP_PT0_DATA =>
      -- Check the returned PTEs for allocation gaps.
      -- v.size tracks the remaining gap size to be found, rounded up to L1 PTE coverage.
      gap_q_valid    <= my_bus_rdat.valid;
      my_bus_rdat.ready <= gap_q_ready;
      gap_q_holes    <= slv(TAKE_EVERY(u(my_bus_rdat.data), PTE_WIDTH, PTE_MAPPED));
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
          v.state_stack    := pop_state(v.state_stack);
        else
          -- Check more L0 entries
          v.state_stack(0) := FIND_GAP_PT0;
        end if;
      end if;


    -- === START OF SET_PTE_RANGE ROUTINE ===
    -- Set mapping for a range of virtual addresses, create page tables as needed.
    -- `addr_vm` contains address to start mapping at.
    -- `region`  region is recorded in the page tables, and used for allocation.
    -- `pages`   must be initialized to the number of pages in the mapping.

    when SET_PTE_RANGE =>
      v.addr           := v.addr_vm;
      -- This will be set when v.addr reaches the intended mapping.
      v.in_mapping     := '0';
      v.pt_reader_outstanding := '0';
      if v.pt_arg.unmap = '1' then
        -- Length for unmap is not known in advance, set it to maximum.
        v.pages        := not to_unsigned(0, v.pages'length);
        -- Start at beginning of L2 page table,
        -- to check whether it is in use by another allocation.
        v.addr         := align_beq(v.addr_vm, VM_SIZE_L1_LOG2);
      end if;
      v.state_stack(0) := SET_PTE_RANGE_L1_ADDR;

    when SET_PTE_RANGE_L1_ADDR =>
      -- Get the L1 PTE
      my_bus_rreq.addr    <= slv(ADDR_BUS_ALIGN(VA_TO_PTE(PT_ADDR, v.addr, 1)));
      my_bus_rreq.len     <= slv(to_unsigned(1, my_bus_rreq.len'length));

      -- Start off by assuming the L2 page table is unused.
      v.pt_empty       := '1';

      my_bus_rreq.valid <= '1';
      if my_bus_rreq.ready = '1' then
        v.state_stack(0) := SET_PTE_RANGE_L1_CHECK;
      end if;

    when SET_PTE_RANGE_L1_CHECK =>
      my_bus_rdat.ready <= '1';
      if my_bus_rdat.valid = '1' then
        -- Check PRESENT bit of PTE referred to by addr.
        -- Ignore (overwrite) any present entries in the L2 table for simplicity of implementation.

        -- Get PT address from the read data.
        v.addr_pt := align_beq(
            EXTRACT(
              unsigned(my_bus_rdat.data),
              BYTE_SIZE * int(ADDR_BUS_OFFSET(VA_TO_PTE(PT_ADDR, v.addr, 1))),
              BYTE_SIZE * PTE_SIZE
            ),
            PT_SIZE_LOG2);
        if v.pt_arg.unmap = '1' then
          -- unmap; request the mapping to do so.
          v.state_stack(0)   := SET_PTE_RANGE_L2_REQ_PT;
        elsif v.pt_arg.copy = '1' then
          v.state_stack(0)   := SET_PTE_RANGE_SRC_L1_ADDR;
        else
          -- map
          if v.pt_arg.alloc_first = '1' then
            -- Request a frame for this mapping.
            v.state_stack(0) := SET_PTE_RANGE_FRAME;
          else
            -- Start updating the L2 page table.
            v.state_stack(0) := SET_PTE_RANGE_L2_UPDATE_ADDR;
          end if;
        end if;

        if my_bus_rdat.data(
             BYTE_SIZE * int(ADDR_BUS_OFFSET(VA_TO_PTE(PT_ADDR, v.addr, 1)))
             + PTE_PRESENT
           ) = '0'
        then
          -- L2 PT does not exist, need to allocate one.
          v.state_stack      := push_state(v.state_stack, PT_NEW);
        elsif v.pt_arg.unmap = '0' then
          -- Indicate the L1 entry does not need updating.
          v.pt_empty         := '0';
        end if;
      end if;

    when SET_PTE_RANGE_L1_UPDATE_ADDR =>
      -- A new PT was allocated, update the corresponding L1 entry.
      my_bus_wreq.valid <= '1';
      my_bus_wreq.addr  <= slv(ADDR_BUS_ALIGN(VA_TO_PTE(PT_ADDR, PAGE_BASE(v.addr)-1, 1)));
      my_bus_wreq.len   <= slv(to_unsigned(1, my_bus_wreq.len'length));
      if my_bus_wreq.ready = '1' then
        v.state_stack(0) := SET_PTE_RANGE_L1_UPDATE_DAT;
      end if;

    when SET_PTE_RANGE_L1_UPDATE_DAT =>
      -- Update the PTE
      my_bus_wdat.valid  <= '1';
      my_bus_wdat.last   <= '1';
      -- Duplicate the address over the data bus
      for i in 0 to BUS_DATA_BYTES/PTE_SIZE-1 loop
        my_bus_wdat.data(PTE_WIDTH * (i+1) - 1 downto PTE_WIDTH * i) <= slv(v.addr_pt);
        if v.pt_arg.unmap = '0' then
          -- Mark the entry as mapped and present
          my_bus_wdat.data(PTE_WIDTH * i + PTE_MAPPED)  <= '1';
          my_bus_wdat.data(PTE_WIDTH * i + PTE_PRESENT) <= '1';
        end if;
      end loop;
      -- Use strobe to write the correct entry
      my_bus_wdat.strobe <= slv(OVERLAY(
          not to_unsigned(0, PTE_SIZE),
          to_unsigned(0, my_bus_wdat.strobe'length),
          int(ADDR_BUS_OFFSET(VA_TO_PTE(PT_ADDR, PAGE_BASE(v.addr)-1, 1)))));
      if my_bus_wdat.ready = '1' then
        if v.pages = 0 then
          -- Done (de)allocating.
          v.state_stack(0) := SET_PTE_RANGE_FINISH;
        else
          v.state_stack(0) := SET_PTE_RANGE_L1_ADDR;
        end if;
      end if;

    when SET_PTE_RANGE_FRAME =>
      -- Allocate a single frame for the mapping.
      dir_frames_cmd_valid   <= '1';
      dir_frames_cmd_action  <= MM_FRAMES_FIND;
      dir_frames_cmd_region  <= slv(resize(v.region - 1, dir_frames_cmd_region'length));
      if dir_frames_cmd_ready = '1' then
        v.state_stack(0) := SET_PTE_RANGE_L2_UPDATE_ADDR;
      end if;

    when SET_PTE_RANGE_L2_REQ_PT =>
      -- Request the existing mapping, to do stuff with it later on. (only for unmap)
      pt_reader_cmd_valid    <= '1';
      pt_reader_cmd_firstIdx <= slv(to_unsigned(0, pt_reader_cmd_firstIdx'length));
      pt_reader_cmd_lastIdx  <= slv(to_unsigned(PT_SIZE / BUS_DATA_BYTES, pt_reader_cmd_lastIdx'length));
      pt_reader_cmd_baseAddr <= slv(v.addr_pt);

      v.pt_reader_outstanding := '1';
      v.bus_pte_idx          := (others => '0');
      if pt_reader_cmd_ready = '1' then
        if v.pt_arg.dealloc = '1' then
          -- Deallocate frames in the mapping.
          v.state_stack(0)   := SET_PTE_RANGE_L2_DEALLOC_FRAME_C;
        else
          -- Do not deallocate frames, just unmap.
          v.state_stack(0)   := SET_PTE_RANGE_L2_UPDATE_ADDR;
        end if;
      end if;

    when SET_PTE_RANGE_SRC_L1_ADDR =>
      -- Get the L1 PTE
      my_bus_rreq.addr       <= slv(ADDR_BUS_ALIGN(VA_TO_PTE(PT_ADDR, v.addr_vm_src, 1)));
      my_bus_rreq.len        <= slv(to_unsigned(1, my_bus_rreq.len'length));
      my_bus_rreq.valid      <= '1';
      if my_bus_rreq.ready = '1' then
        v.state_stack(0) := SET_PTE_RANGE_SRC_L2_REQ;
      end if;

    when SET_PTE_RANGE_SRC_L2_REQ =>
      -- Request the existing mapping, to do stuff with it later on. (only for realloc)
      pt_reader_cmd_valid    <= my_bus_rdat.valid;
      my_bus_rdat.ready      <= pt_reader_cmd_ready;
      -- First argument to VA_TO_PTE doesn't matter here, since we only use the offset within the PT.
      pt_reader_cmd_firstIdx <= slv(resize(
            div_floor(
              VA_TO_PTE(PT_ADDR, v.addr_vm_src, 2),
              BUS_DATA_BYTES / PTE_SIZE),
            pt_reader_cmd_firstIdx'length));
      pt_reader_cmd_lastIdx  <= slv(to_unsigned(PT_SIZE / BUS_DATA_BYTES, pt_reader_cmd_lastIdx'length));
      pt_reader_cmd_baseAddr <= slv(align_beq(
            EXTRACT(
              unsigned(my_bus_rdat.data),
              BYTE_SIZE * int(ADDR_BUS_OFFSET(VA_TO_PTE(PT_ADDR, v.addr_vm_src, 1))),
              BYTE_SIZE * PTE_SIZE
            ),
            PT_SIZE_LOG2));

      v.pt_reader_outstanding := '1';
      if pt_reader_cmd_ready = '1' and my_bus_rdat.valid = '1' then
        v.state_stack(0)     := SET_PTE_RANGE_L2_UPDATE_ADDR;
      end if;

    when SET_PTE_RANGE_L2_DEALLOC_FRAME_C =>
      -- Mark a mapped frame as unused when deallocating.
      if  shift_right(v.addr,    VM_SIZE_L2_LOG2 + log2ceil(BUS_DATA_BYTES / PTE_SIZE))
        = shift_right(v.addr_vm, VM_SIZE_L2_LOG2 + log2ceil(BUS_DATA_BYTES / PTE_SIZE))
      then
        -- Current address is now in the mapping of interest.
        v.in_mapping           := '1';
      end if;

      -- TODO: handle mappings not starting at bus word boundary.
      if v.in_mapping = '0' then
        v.state_stack(0) := SET_PTE_RANGE_L2_UPDATE_ADDR;
      else
        -- In mapping, do processing (freeing of frames).
        dir_frames_cmd_action      <= MM_FRAMES_FREE;
        dir_frames_cmd_addr        <= slv(EXTRACT(
            u(pt_reader.data),
            int(v.bus_pte_idx) * PTE_WIDTH,
            BUS_ADDR_WIDTH ));
        if pt_reader.valid = '1' then
          if
            pt_reader.data(PTE_WIDTH * int(v.bus_pte_idx) + PTE_MAPPED) = '1' and
            pt_reader.data(PTE_WIDTH * int(v.bus_pte_idx) + PTE_PRESENT) = '1'
          then
            -- Page is mapped to a frame.
            dir_frames_cmd_valid   <= '1';
            if dir_frames_cmd_ready = '1' then
              -- Handshaked, wait for response in next state.
              v.state_stack(0) := SET_PTE_RANGE_L2_DEALLOC_FRAME_R;
              if pt_reader.data(PTE_WIDTH * int(v.bus_pte_idx) + PTE_BOUNDARY) = '1' then
                -- Reached mapping boundary.
                -- Skip to end to prevent processing frames belonging to the next mapping.
                v.bus_pte_idx  := to_unsigned(BUS_DATA_BYTES / PTE_SIZE - 1, v.bus_pte_idx'length);
              end if;
            end if;

          else
            -- Page is not mapped to a frame.
            if pt_reader.data(PTE_WIDTH * int(v.bus_pte_idx) + PTE_BOUNDARY) = '1' then
              -- Reached mapping boundary.
              -- Skip to end to prevent processing frames belonging to the next mapping.
              v.bus_pte_idx    := to_unsigned(BUS_DATA_BYTES / PTE_SIZE - 1, v.bus_pte_idx'length);
            end if;
            if v.bus_pte_idx = BUS_DATA_BYTES / PTE_SIZE - 1 then
              -- Investigated all PTEs in bus word.
              v.state_stack(0) := SET_PTE_RANGE_L2_UPDATE_ADDR;
            end if;
            v.bus_pte_idx      := v.bus_pte_idx + 1;
          end if;
        end if;
      end if;

    when SET_PTE_RANGE_L2_DEALLOC_FRAME_R =>
      dir_frames_resp_ready    <= '1';
      if dir_frames_resp_valid = '1' then
        if v.bus_pte_idx = BUS_DATA_BYTES / PTE_SIZE - 1 then
          -- Investigated all PTEs in bus word.
          v.state_stack(0)     := SET_PTE_RANGE_L2_UPDATE_ADDR;
        else
          v.state_stack(0)     := SET_PTE_RANGE_L2_DEALLOC_FRAME_C;
        end if;
        v.bus_pte_idx          := v.bus_pte_idx + 1;
      end if;

    when SET_PTE_RANGE_L2_UPDATE_ADDR =>
      -- L2 page table entry address
      my_bus_wreq.addr       <= slv(ADDR_BUS_ALIGN(VA_TO_PTE(v.addr_pt, v.addr, 2)));
      my_bus_wreq.len        <= slv(to_unsigned(1, my_bus_wreq.len'length));

      if  shift_right(v.addr,    VM_SIZE_L2_LOG2 + log2ceil(BUS_DATA_BYTES / PTE_SIZE))
        = shift_right(v.addr_vm, VM_SIZE_L2_LOG2 + log2ceil(BUS_DATA_BYTES / PTE_SIZE))
      then
        -- Current address is in the mapping of interest.
        v.in_mapping         := '1';
      end if;

      if v.pt_reader_outstanding = '1' then
        if v.pt_arg.unmap = '1' and v.in_mapping = '0' then
          -- Skip write if before the start address, or after the end address.
          handshake          := '1';
        else
          -- Wait until read is done to prevent deadlock
          my_bus_wreq.valid  <= pt_reader.valid;
          handshake          := my_bus_wreq.ready and pt_reader.valid;
        end if;
      else
        -- No pending read from PT reader.
        my_bus_wreq.valid    <= '1';
        handshake            := my_bus_wreq.ready;
      end if;

      if handshake = '1' then
        v.state_stack(0)     := SET_PTE_RANGE_L2_UPDATE_DAT;
      end if;

    when SET_PTE_RANGE_L2_UPDATE_DAT =>
      -- Update the L2 page table entries (whole bus word)
      if v.pt_arg.unmap = '1' and v.in_mapping = '0' then
        -- Not inside of mapping during deallocation.
        -- Consume requested data, do not write.
        pt_reader.ready       <= '1';
        my_bus_wdat.valid     <= '0';
        handshake             := pt_reader.valid;
      elsif v.pt_arg.unmap = '1' or v.pt_arg.copy = '1' then
        -- Take data from PT reader
        pt_reader.ready       <= my_bus_wdat.ready;
        my_bus_wdat.valid     <= pt_reader.valid;
        handshake             := pt_reader.valid and my_bus_wdat.ready;
      elsif v.pt_arg.alloc_first = '1' then
        -- Use allocated frame in mapping.
        dir_frames_resp_ready <= my_bus_wdat.ready;
        my_bus_wdat.valid     <= dir_frames_resp_valid;
        handshake             := dir_frames_resp_valid and my_bus_wdat.ready;
      else
        -- Create mapping without allocation.
        my_bus_wdat.valid     <= '1';
        handshake             := my_bus_wdat.ready;
      end if;
      my_bus_wdat.last        <= '1';

      -- Loop over the PTEs on the data bus.
      for i in 0 to BUS_DATA_BYTES/PTE_SIZE-1 loop

        -- Default to a zero'd entry when not copying.
        my_bus_wdat.data(PTE_WIDTH * (i+1) - 1 downto PTE_WIDTH * i) <= (others => '0');

        if v.pt_arg.copy = '1' then
          if v.in_mapping = '1' then
            -- Copy entry
            -- TODO support unaligned source.
            my_bus_wdat.data(PTE_WIDTH * (i+1) - 1 downto PTE_WIDTH * i) <= pt_reader.data(PTE_WIDTH * (i+1) - 1 downto PTE_WIDTH * i);
            -- Get region from existing mapping, to write to new entries.
            v.region        := u(pt_reader.data(PTE_WIDTH * i + PTE_SEGMENT + v.region'length - 1 downto PTE_WIDTH * i + PTE_SEGMENT));
            if pt_reader.data(PTE_WIDTH * i + PTE_BOUNDARY) = '1' then
              -- Last entry in source, stop copy after this entry.
              v.in_mapping  := '0';
            end if;
          end if;
        end if;

        if v.pt_arg.unmap = '1' then
          if v.in_mapping = '0' and
            pt_reader.data(PTE_WIDTH * i + PTE_MAPPED) = '1'
          then
            -- An entry is mapped outside of the deleted mapping. Do not delete PT.
            v.pt_empty    := '0';
          end if;
          if pt_reader.data(PTE_WIDTH * i + PTE_BOUNDARY) = '1' then
            -- Last entry of the mapping, number of pages now known.
            v.pages       := to_unsigned(i+1, v.pages'length);
            v.in_mapping  := '0';
          end if;
        end if;

        -- First entry
        if v.pt_arg.alloc_first = '1' and -- Allocate first entry.
          -- This offset is the first entry for the mapping.
          PAGE_BASE(v.addr) + shift_left(to_unsigned(i, v.addr_vm'length), VM_SIZE_L2_LOG2) = PAGE_BASE(v.addr_vm)
        then
          -- Map to the allocated frame.
          my_bus_wdat.data(PTE_WIDTH * (i+1) - 1 downto PTE_WIDTH * i) <= dir_frames_resp_addr;
          -- Mark the entry as present.
          my_bus_wdat.data(PTE_WIDTH * i + PTE_PRESENT) <= '1';
        end if;

        -- Last entry
        if r.pages - i - 1 = 0 then
          my_bus_wdat.data(PTE_WIDTH * i + PTE_BOUNDARY) <= '1';
        else
          my_bus_wdat.data(PTE_WIDTH * i + PTE_BOUNDARY) <= '0';
        end if;

        -- Mark as mapped / not mapped
        my_bus_wdat.data(PTE_WIDTH * i + PTE_MAPPED)  <= not v.pt_arg.unmap;

        -- Write region
        my_bus_wdat.data(PTE_WIDTH * i + PTE_SEGMENT + v.region'length - 1 downto PTE_WIDTH * i + PTE_SEGMENT) <= slv(v.region);
      end loop;

      -- current = v.addr
      -- start   = v.addr_vm
      -- target  = v.addr_vm + v.size
      -- todo    = pages

      -- Use strobe to write the correct entries.
      if 0 = ADDR_BUS_OFFSET(VA_TO_PTE(v.addr_pt, v.addr, 2)) then
        -- First PTE is aligned to start of bus word.
        -- Shift a vector of ones to the right to get the correct strobe.
        my_bus_wdat.strobe <= slv(
            shift_right(
              not to_unsigned(0, my_bus_wdat.strobe'length),
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

      if handshake = '1' then
        -- Do not try to use allocated frame on next iteration.
        v.pt_arg.alloc_first := '0';

        -- Next address is increased by the size addressable by the written entries.
        v.addr := PAGE_BASE(v.addr) +
            shift_left(
              to_unsigned(BUS_DATA_BYTES / PTE_SIZE, v.addr'length),
              VM_SIZE_L2_LOG2);
        if v.pt_arg.copy = '1' then
          -- Do not alter register when not needed by operation.
          v.addr_vm_src := PAGE_BASE(v.addr_vm_src) +
              shift_left(
                to_unsigned(BUS_DATA_BYTES / PTE_SIZE, v.addr_vm_src'length),
                VM_SIZE_L2_LOG2);
        end if;

        -- Update pages left to process.
        v.pages  := v.pages -
            -- Amount of PTEs in this bus word
            CLAMP(
              -- Amount of PTEs left
              v.pages,
              BUS_DATA_BYTES / PTE_SIZE);

        if pt_reader.valid = '1' and pt_reader.last = '1' then
          v.pt_reader_outstanding := '0';
        end if;

        if v.pt_arg.unmap = '0' and v.pages = 0 then
          -- Allocated enough space.
          if v.pt_empty = '1' then
            -- New PT, update L1 entry.
            v.state_stack(0) := SET_PTE_RANGE_L1_UPDATE_ADDR;
          else
            -- Allocation is done.
            v.state_stack(0) := SET_PTE_RANGE_FINISH;
          end if;

        -- Not done for allocation, maybe done for deallocation.
        elsif EXTRACT(v.addr, PAGE_SIZE_LOG2, PT_ENTRIES_LOG2) = 0 then
          -- At end of L2 PT, go to next table through L1.
          if v.pt_empty = '1' then
            -- New PT, or delete PT: update L1 entry.
            v.state_stack(0) := SET_PTE_RANGE_L1_UPDATE_ADDR;
            if v.pt_arg.unmap = '1' then
              -- Delete page table.
              v.state_stack  := push_state(v.state_stack, PT_DEL);
            end if;

          -- No new or deleted PT.
          elsif v.pt_arg.unmap = '1' then
            -- Done deallocating.
            -- TODO: check condition. Need to check v.pages ?
            v.state_stack(0)  := SET_PTE_RANGE_FINISH;
          else
            -- Not done allocating, continue to next L1 entry.
            v.state_stack(0) := SET_PTE_RANGE_L1_ADDR;
          end if;

        -- Not done in L2 table.
        elsif v.pt_arg.dealloc = '1' then
          -- Deallocate
          v.state_stack(0)   := SET_PTE_RANGE_L2_DEALLOC_FRAME_C;
        else
          -- Continue with next PTE.
          v.state_stack(0)   := SET_PTE_RANGE_L2_UPDATE_ADDR;
        end if;

      else
        -- No handshake, do not update in_mapping just yet.
        v.in_mapping := r.in_mapping;
      end if;

    when SET_PTE_RANGE_FINISH =>
      -- Sink all the PT reader data.
      pt_reader.ready        <= '1';
      if (pt_reader.valid = '1' and pt_reader.last = '1')
        or v.pt_reader_outstanding = '0'
      then
        v.state_stack          := pop_state(v.state_stack);
      end if;


    -- === START OF FRAME_INIT ROUTINE ===
    -- Clear the usage bitmap of the frame at `addr' and add it to the rolodex.
    -- `addr' is not preserved, but will continue to point into the same frame.
    -- Does not preserve contents of the frame.

    when PT_FRAME_INIT_ADDR =>
      -- Can write further than the bitmap,
      -- because the entire frame should be unused at this point.
      my_bus_wreq.valid <= '1';
      my_bus_wreq.addr  <= slv(v.addr);
      my_bus_wreq.len   <= slv(to_unsigned(1, my_bus_wreq.len'length));
      if my_bus_wreq.ready = '1' then
        v.state_stack(0) := PT_FRAME_INIT_DATA;
        if (PT_PER_FRAME > BUS_DATA_WIDTH) then
          -- Need another write on a higher address
          v.addr := unsigned(v.addr) + BUS_DATA_BYTES;
        end if;
      end if;

    when PT_FRAME_INIT_DATA =>
      my_bus_wdat.valid  <= '1';
      my_bus_wdat.data   <= (others => '0');
      my_bus_wdat.strobe <= (others => '1');
      my_bus_wdat.last   <= '1';
      if my_bus_wdat.ready = '1' then
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
      my_bus_rreq.addr  <= slv(PAGE_BASE(v.addr_pt) + div_floor(PT_BITMAP_IDX(v.addr_pt), BUS_DATA_WIDTH));
      my_bus_rreq.len   <= slv(to_unsigned(1, my_bus_rreq.len'length));
      my_bus_rreq.valid <= '1';
      if my_bus_rreq.ready = '1' then
        v.state_stack(0) := PT_DEL_MARK_BM_ADDR;
      end if;

    when PT_DEL_MARK_BM_ADDR =>
      -- Set address for marking bit in bitmap
      my_bus_wreq.valid <= my_bus_rdat.valid;
      my_bus_rdat.ready <= my_bus_wreq.ready;
      my_bus_wreq.addr  <= slv(PAGE_BASE(v.addr_pt) + div_floor(PT_BITMAP_IDX(v.addr_pt), BUS_DATA_WIDTH));
      my_bus_wreq.len   <= slv(to_unsigned(1, my_bus_wreq.len'length));
      -- Copy the byte that has to be written back.
      v.byte_buffer      := EXTRACT(
          u(my_bus_rdat.data),
          int(align_beq(PT_BITMAP_IDX(v.addr_pt), BYTE_SIZE) mod BUS_DATA_WIDTH),
          BYTE_SIZE);
      -- Mark PT as unused in bitmap's byte.
      v.byte_buffer(int(PT_BITMAP_IDX(v.addr_pt) mod BYTE_SIZE)) := '0';
      if my_bus_wreq.ready = '1' then
        -- TODO: make this work for bitmaps > BUS_DATA_WIDTH
        if BIT_COUNT(my_bus_rdat.data(work.Utils.min(PT_PER_FRAME, BUS_DATA_WIDTH) downto 0)) = 1 then
          -- This was the last page table in the frame, delete it.
          v.state_stack(0) := PT_DEL_ROLODEX;
        else
          v.state_stack(0) := PT_DEL_MARK_BM_DATA;
        end if;
      end if;

    when PT_DEL_ROLODEX =>
      rolodex_delete_entry   <= ADDR_TO_ROLODEX(v.addr_pt);
      rolodex_delete_valid   <= '1';
      if rolodex_delete_ready = '1' then
        v.state_stack(0)     := PT_DEL_FRAME;
      end if;

    when PT_DEL_FRAME =>
      dir_frames_cmd_valid   <= '1';
      dir_frames_cmd_action  <= MM_FRAMES_FREE;
      dir_frames_cmd_addr    <= slv(PAGE_BASE(v.addr_pt));
      if dir_frames_cmd_ready = '1' then
        v.state_stack(0)     := PT_DEL_FRAME_CHECK;
      end if;

    when PT_DEL_FRAME_CHECK =>
      dir_frames_resp_ready  <= '1';
      if dir_frames_resp_valid = '1' then
        v.state_stack(0)     := PT_DEL_MARK_BM_DATA;
      end if;

    when PT_DEL_MARK_BM_DATA =>
      my_bus_wdat.valid      <= '1';
      for i in 0 to BUS_DATA_BYTES-1 loop
        my_bus_wdat.data(BYTE_SIZE*(i+1)-1 downto BYTE_SIZE*i) <= slv(v.byte_buffer);
      end loop;
      my_bus_wdat.strobe     <= (others => '0');
      -- Get page table number referenced by addr and figure out which byte of the bitmap it is in.
      my_bus_wdat.strobe(int(
        div_floor(
          PT_BITMAP_IDX(v.addr_pt) mod BUS_DATA_WIDTH,
          BYTE_SIZE)
        ))                   <= '1';
      my_bus_wdat.last       <= '1';
      if my_bus_wdat.ready = '1' then
        v.state_stack        := pop_state(v.state_stack);
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
      -- Make sure any earlier bitmap edit has been written out.
      if rolodex_entry_valid = '1' and my_bus_wreq.dirty = '0' then
        v.state_stack(0) := PT_NEW_REQ_BM;
      end if;

    when PT_NEW_REQ_BM =>
      -- Find a free spot for a PT
      v.addr         := ROLODEX_TO_ADDR(rolodex_entry);
      my_bus_rreq.addr  <= slv(v.addr);
      my_bus_rreq.len   <= slv(to_unsigned(1, my_bus_rreq.len'length));
      -- TODO implement finding empty spots past BUS_DATA_WIDTH entries
      if rolodex_entry_valid = '1' then
        if rolodex_entry_marked = '1' then
          -- Tried all existing PT frames.
          v.state_stack(0) := PT_NEW_FRAME;
        else
          my_bus_rreq.valid <= '1';
          if my_bus_rreq.ready = '1' then
            v.state_stack(0) := PT_NEW_CHECK_BM;
          end if;
        end if;
      end if;

    when PT_NEW_FRAME =>
      dir_frames_cmd_valid   <= '1';
      dir_frames_cmd_action  <= MM_FRAMES_ALLOC;
      dir_frames_cmd_addr    <= slv(PAGE_BASE(PT_ADDR));
      if dir_frames_cmd_ready = '1' then
        v.state_stack(0) := PT_NEW_FRAME_CHECK;
      end if;

    when PT_NEW_FRAME_CHECK =>
      -- Execute the `frame initialize' routine to set bitmap.
      dir_frames_resp_ready  <= '1';
      if dir_frames_resp_valid = '1' then
        if dir_frames_resp_success = '1' then
          v.state_stack(0) := PT_NEW_REQ_BM;
          v.state_stack    := push_state(v.state_stack, PT_FRAME_INIT_ADDR);
          v.addr           := PAGE_BASE(u(dir_frames_resp_addr));
        else
          v.state_stack(0) := FAIL;
        end if;
      end if;

    when PT_NEW_CHECK_BM =>
      -- Load the adjacent bitmap bits before marking a bit.
      -- We need this, because the write strobe has byte granularity.
      my_bus_rdat.ready <= '1';
      if my_bus_rdat.valid = '1' then
        for i in 0 to work.Utils.min(PT_PER_FRAME, BUS_DATA_WIDTH) loop
          if i = work.Utils.min(PT_PER_FRAME, BUS_DATA_WIDTH) then
            -- All checked places are occupied in this frame
            -- Try next entry in rolodex
            rolodex_entry_ready <= '1';
            v.state_stack(0) := PT_NEW_REQ_BM;
            exit;
          end if;
          if my_bus_rdat.data(i) = '0' then
            -- Bit 0 refers to the first possible page table in this frame.
            v.state_stack(0) := PT_NEW_MARK_BM_ADDR;
            v.addr           := OVERLAY(
                                    shift_left(
                                        to_unsigned(i+PT_FIRST_NR, PAGE_SIZE_LOG2),
                                        PT_SIZE_LOG2),
                                    PAGE_BASE(v.addr));
            -- Save the byte that needs to be written
            v.byte_buffer    := EXTRACT(
                                    unsigned(my_bus_rdat.data),
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
      my_bus_wreq.valid <= '1';
      my_bus_wreq.addr  <= slv(PAGE_BASE(v.addr));
      my_bus_wreq.len   <= slv(to_unsigned(1, my_bus_wreq.len'length));
      -- TODO: enable bitmap location > BUS_DATA_WIDTH
      if my_bus_wreq.ready = '1' then
        v.state_stack(0) := PT_NEW_MARK_BM_DATA;
      end if;

    when PT_NEW_MARK_BM_DATA =>
      my_bus_wdat.valid  <= '1';
      for i in 0 to BUS_DATA_BYTES-1 loop
        my_bus_wdat.data(BYTE_SIZE*(i+1)-1 downto BYTE_SIZE*i) <= slv(v.byte_buffer);
      end loop;
      my_bus_wdat.strobe <= (others => '0');
      -- Get page table number referenced by addr and figure out which byte of the bitmap it is in.
      my_bus_wdat.strobe(int(
        div_floor(
          PT_BITMAP_IDX(v.addr),
          BYTE_SIZE)
        )) <= '1';
      my_bus_wdat.last <= '1';
      if my_bus_wdat.ready = '1' then
        v.state_stack(0) := PT_NEW_CLEAR_ADDR;
      end if;

    when PT_NEW_CLEAR_ADDR =>
      my_bus_wreq.valid <= '1';
      my_bus_wreq.addr  <= slv(v.addr);
      -- The number of beats in the burst
      v.beat         := to_unsigned(
                        work.Utils.min(
                          BUS_BURST_MAX_LEN,
                          int(div_ceil(
                            to_unsigned(PT_SIZE, log2ceil(PT_SIZE+1)) - PT_OFFSET(v.addr),
                            BUS_DATA_BYTES))
                        ),
                        v.beat'length);
      my_bus_wreq.len   <= slv(resize(v.beat, my_bus_wreq.len'length));
      if my_bus_wreq.ready = '1' then
        v.state_stack(0) := PT_NEW_CLEAR_DATA;
        v.addr           := v.addr + BYTES_IN_BEATS(v.beat);
      end if;

    when PT_NEW_CLEAR_DATA =>
      my_bus_wdat.valid  <= '1';
      my_bus_wdat.data   <= (others => '0');
      my_bus_wdat.strobe <= (others => '1');
      if v.beat = 1 then
        my_bus_wdat.last <= '1';
      else
        my_bus_wdat.last <= '0';
      end if;
      if my_bus_wdat.ready = '1' then
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

    -- === START OF FRAME ALLOCATION ROUTINE ===
    -- Allocates a frame for an already mapped virtual address, `addr_vm`.
    -- Response is given on MMU channel.
  mmu : process (r_mmu,
           mmu_frames_cmd_ready,
           mmu_frames_resp_addr, mmu_frames_resp_success, mmu_frames_resp_valid,
           mmu_bus_wreq, mmu_bus_wdat,
           mmu_bus_rreq, mmu_bus_rdat,
           mmu_req_valid, mmu_req_addr, mmu_resp_ready) is
    variable v : reg_mmu_type;
  begin
    v := r_mmu;

    mmu_frames_cmd_valid     <= '0';
    mmu_frames_cmd_region    <= (others => 'U');
    mmu_frames_cmd_addr      <= (others => 'U');
    mmu_frames_cmd_action    <= (others => 'U');
    mmu_frames_resp_ready    <= '0';

    mmu_bus_wreq.valid       <= '0';
    mmu_bus_wreq.addr        <= (others => 'U');
    mmu_bus_wreq.len         <= (others => 'U');
    mmu_bus_wreq.barrier     <= '1';

    mmu_bus_wdat.valid       <= '0';
    mmu_bus_wdat.data        <= (others => 'U');
    mmu_bus_wdat.strobe      <= (others => 'U');
    mmu_bus_wdat.last        <= 'U';

    mmu_bus_rreq.valid       <= '0';
    mmu_bus_rreq.addr        <= (others => 'U');
    mmu_bus_rreq.len         <= (others => 'U');

    mmu_bus_rdat.ready       <= '0';

    mmu_req_ready            <= '0';

    mmu_resp_valid           <= '0';
    mmu_resp_addr            <= (others => 'U');

    case v.state is

    when RESET_ST =>
      v.state                := IDLE;

    when IDLE =>
      mmu_req_ready <= '1';
      if mmu_req_valid = '1' then
        v.state              := MMU_GET_L1_ADDR;
        v.addr_vm            := u(mmu_req_addr);
      end if;

    when MMU_GET_L1_ADDR =>
      -- Get the L1 PTE
      mmu_bus_rreq.addr       <= slv(ADDR_BUS_ALIGN(VA_TO_PTE(PT_ADDR, v.addr_vm, 1)));
      mmu_bus_rreq.len        <= slv(to_unsigned(1, mmu_bus_rreq.len'length));
      -- Wait for any outstanding writes to be completed.
      if mmu_bus_wreq.dirty = '0' then
        mmu_bus_rreq.valid <= '1';
        if mmu_bus_rreq.ready = '1' then
          v.state            := MMU_GET_L1_DAT;
        end if;
      end if;

    when MMU_GET_L1_DAT =>
      mmu_bus_rdat.ready     <= '1';
      if mmu_bus_rdat.valid = '1' then
        -- Check PRESENT bit of PTE referred to by addr_vm.
        if mmu_bus_rdat.data(
             PTE_SIZE * int(ADDR_BUS_OFFSET(VA_TO_PTE(PT_ADDR, v.addr_vm, 1)))
             + PTE_PRESENT
           ) /= '1'
        then
          -- Given address isn't mapped.
          v.state            := FAIL;
        else
          -- Get address of L2 page table from the read data.
          v.addr_pt          := align_beq(
              EXTRACT(
                unsigned(mmu_bus_rdat.data),
                BYTE_SIZE * int(ADDR_BUS_OFFSET(VA_TO_PTE(PT_ADDR, v.addr_vm, 1))),
                BYTE_SIZE * PTE_SIZE
              ),
              PT_SIZE_LOG2);
          v.state            := MMU_GET_L2_ADDR;
        end if;
      end if;

    when MMU_GET_L2_ADDR =>
      -- Get the L1 PTE
      mmu_bus_rreq.addr      <= slv(ADDR_BUS_ALIGN(VA_TO_PTE(v.addr_pt, v.addr_vm, 2)));
      mmu_bus_rreq.len       <= slv(to_unsigned(1, mmu_bus_rreq.len'length));
      mmu_bus_rreq.valid     <= '1';
      if mmu_bus_rreq.ready = '1' then
        v.state              := MMU_GET_L2_DAT;
      end if;

    when MMU_GET_L2_DAT =>
      if mmu_bus_rdat.valid = '1' then

        if mmu_bus_rdat.data(
             PTE_SIZE * int(ADDR_BUS_OFFSET(VA_TO_PTE(v.addr_pt, v.addr_vm, 2)))
             + PTE_MAPPED
           ) /= '1'
        then
          -- Given address isn't mapped.
          mmu_bus_rdat.ready  <= '1';
          v.state            := FAIL;

        elsif mmu_bus_rdat.data(
             PTE_SIZE * int(ADDR_BUS_OFFSET(VA_TO_PTE(v.addr_pt, v.addr_vm, 2)))
             + PTE_PRESENT
           ) = '1'
        then
          -- Given address is already present, return the mapping.
          mmu_resp_valid     <= '1';
          mmu_resp_addr      <= slv(align_beq(
              EXTRACT(
                unsigned(mmu_bus_rdat.data),
                BYTE_SIZE * int(ADDR_BUS_OFFSET(VA_TO_PTE(v.addr_pt, v.addr_vm, 2))),
                BYTE_SIZE * PTE_SIZE
              ),
              PT_SIZE_LOG2));
          if mmu_resp_ready = '1' then
            mmu_bus_rdat.ready <= '1';
            v.state          := IDLE;
          end if;

        else
          -- Get segment of mapped address from the read data.
          mmu_frames_cmd_valid  <= '1';
          mmu_frames_cmd_action <= MM_FRAMES_FIND;
          if log2ceil(MEM_REGIONS) > 0 then
            mmu_frames_cmd_region <= slv(
                resize(
                  EXTRACT(
                    unsigned(mmu_bus_rdat.data),
                    BYTE_SIZE * int(ADDR_BUS_OFFSET(VA_TO_PTE(v.addr_pt, v.addr_vm, 2))) + PTE_SEGMENT,
                    log2ceil(MEM_REGIONS+1)
                  ) - 1,
                  log2ceil(MEM_REGIONS)));
          end if;
          -- Store all flags of the mapping (skip the address itself)
          v.addr             := resize(
              EXTRACT(
                unsigned(mmu_bus_rdat.data),
                BYTE_SIZE * int(ADDR_BUS_OFFSET(VA_TO_PTE(v.addr_pt, v.addr_vm, 2))),
                PAGE_SIZE_LOG2
              ),
              v.addr'length
            );
          if mmu_frames_cmd_ready = '1' then
            mmu_bus_rdat.ready <= '1';
            v.state          := MMU_RESP;
          end if;
        end if;
      end if;

    when MMU_RESP =>
      -- Respond with the frame address as soon as possible.
      mmu_resp_valid         <= mmu_frames_resp_valid;
      mmu_resp_addr          <= mmu_frames_resp_addr;
      if mmu_resp_ready = '1' then
        v.state              := MMU_SET_L2_ADDR;
      end if;

    when MMU_SET_L2_ADDR =>
      -- Update the PTE.
      mmu_bus_wreq.valid     <= '1';
      mmu_bus_wreq.addr      <= slv(ADDR_BUS_ALIGN(VA_TO_PTE(v.addr_pt, v.addr_vm, 2)));
      mmu_bus_wreq.len       <= slv(to_unsigned(1, mmu_bus_wreq.len'length));
      if mmu_bus_wreq.ready = '1' then
        v.state              := MMU_SET_L2_DAT;
      end if;

    when MMU_SET_L2_DAT =>
      mmu_bus_wdat.valid     <= mmu_frames_resp_valid;
      mmu_bus_wdat.last      <= '1';
      -- Duplicate the address over the data bus.
      for i in 0 to BUS_DATA_BYTES/PTE_SIZE-1 loop
        -- Copy the existing flags.
        mmu_bus_wdat.data(PTE_WIDTH * (i+1) - 1 downto PTE_WIDTH * i) <= slv(v.addr);
        -- Mark the entry as present.
        mmu_bus_wdat.data(PTE_WIDTH * i + PTE_PRESENT) <= '1';
        -- Map to the allocated frame.
        mmu_bus_wdat.data(PTE_WIDTH * (i+1) - 1 downto PTE_WIDTH * i + PAGE_SIZE_LOG2)
            <= slv(EXTRACT(u(mmu_frames_resp_addr), PAGE_SIZE_LOG2, PTE_WIDTH-PAGE_SIZE_LOG2));
      end loop;
      -- Use strobe to write the correct entry.
      mmu_bus_wdat.strobe        <= slv(OVERLAY(
          not to_unsigned(0, PTE_SIZE),
          to_unsigned(0, mmu_bus_wdat.strobe'length),
          int(ADDR_BUS_OFFSET(VA_TO_PTE(v.addr_pt, v.addr_vm, 2)))));
      if mmu_bus_wdat.ready = '1' then
        mmu_frames_resp_ready <= '1';
        v.state              := IDLE;
      end if;

    when others =>

    end case;

    d_mmu <= v;
  end process;


  -- === START OF COMPONENT MAPPINGS ===

  pt_frames : MMRolodex
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
      cmd_action                  => frames_cmd_action,
      cmd_valid                   => frames_cmd_valid,
      cmd_ready                   => frames_cmd_ready,

      resp_addr                   => frames_resp_addr,
      resp_success                => frames_resp_success,
      resp_valid                  => frames_resp_valid,
      resp_ready                  => frames_resp_ready
    );

  frames_arbiter : BusReadArbiter
    generic map (
      BUS_ADDR_WIDTH              => FCI(FCI'high),
      BUS_LEN_WIDTH               => 1,
      BUS_DATA_WIDTH              => FRI(FRI'high),
      NUM_SLAVE_PORTS             => 2,
      ARB_METHOD                  => "FIXED",
      MAX_OUTSTANDING             => 2,
      SLV_REQ_SLICES              => false,
      MST_REQ_SLICE               => false,
      MST_DAT_SLICE               => false,
      SLV_DAT_SLICES              => false
    )
    port map (
      bus_clk                     => clk,
      bus_reset                   => reset,

      mst_rreq_valid              => frames_cmd_valid,
      mst_rreq_ready              => frames_cmd_ready,
      mst_rreq_addr               => frames_cmd_ser,
      mst_rreq_len                => open,
      mst_rdat_valid              => frames_resp_valid,
      mst_rdat_ready              => frames_resp_ready,
      mst_rdat_data               => frames_resp_ser,
      mst_rdat_last               => '1',

      bs00_rreq_valid             => mmu_frames_cmd_valid,
      bs00_rreq_ready             => mmu_frames_cmd_ready,
      bs00_rreq_addr              => mmu_frames_cmd_ser,
      bs00_rreq_len               => "1",
      bs00_rdat_valid             => mmu_frames_resp_valid,
      bs00_rdat_ready             => mmu_frames_resp_ready,
      bs00_rdat_data              => mmu_frames_resp_ser,
      bs00_rdat_last              => open,

      bs01_rreq_valid             => dir_frames_cmd_valid,
      bs01_rreq_ready             => dir_frames_cmd_ready,
      bs01_rreq_addr              => dir_frames_cmd_ser,
      bs01_rreq_len               => "1",
      bs01_rdat_valid             => dir_frames_resp_valid,
      bs01_rdat_ready             => dir_frames_resp_ready,
      bs01_rdat_data              => dir_frames_resp_ser,
      bs01_rdat_last              => open
    );

  mmu_frames_cmd_ser(FCI(3)-1 downto FCI(2)) <= mmu_frames_cmd_action;
  mmu_frames_cmd_ser(FCI(2)-1 downto FCI(1)) <= mmu_frames_cmd_addr;
  mmu_frames_cmd_ser(FCI(1)-1 downto FCI(0)) <= mmu_frames_cmd_region;
  dir_frames_cmd_ser(FCI(3)-1 downto FCI(2)) <= dir_frames_cmd_action;
  dir_frames_cmd_ser(FCI(2)-1 downto FCI(1)) <= dir_frames_cmd_addr;
  dir_frames_cmd_ser(FCI(1)-1 downto FCI(0)) <= dir_frames_cmd_region;
  frames_cmd_action <= frames_cmd_ser(FCI(3)-1 downto FCI(2));
  frames_cmd_addr   <= frames_cmd_ser(FCI(2)-1 downto FCI(1));
  frames_cmd_region <= frames_cmd_ser(FCI(1)-1 downto FCI(0));
  frames_resp_ser(FRI(2)-1 downto FRI(1)) <= frames_resp_addr;
  frames_resp_ser(FRI(0))                 <= frames_resp_success;
  mmu_frames_resp_addr    <= mmu_frames_resp_ser(FRI(2)-1 downto FRI(1));
  mmu_frames_resp_success <= mmu_frames_resp_ser(FRI(0));
  dir_frames_resp_addr    <= dir_frames_resp_ser(FRI(2)-1 downto FRI(1));
  dir_frames_resp_success <= dir_frames_resp_ser(FRI(0));


  director_barrier : MMBarrier
    generic map (
      BUS_ADDR_WIDTH              => BUS_ADDR_WIDTH,
      BUS_LEN_WIDTH               => BUS_LEN_WIDTH,
      MAX_OUTSTANDING             => MAX_OUTSTANDING_TRANSACTIONS
    )
    port map (
      clk                         => clk,
      reset                       => reset,
      dirty                       => my_bus_wreq.dirty,

      -- Slave write request channel
      slv_wreq_valid              => my_bus_wreq.valid,
      slv_wreq_ready              => my_bus_wreq.ready,
      slv_wreq_addr               => my_bus_wreq.addr,
      slv_wreq_len                => my_bus_wreq.len,
      slv_wreq_barrier            => my_bus_wreq.barrier,
      -- Master write request channel
      mst_wreq_valid              => my_bus_wreq_b.valid,
      mst_wreq_ready              => my_bus_wreq_b.ready,
      mst_wreq_addr               => my_bus_wreq_b.addr,
      mst_wreq_len                => my_bus_wreq_b.len,

      -- Slave response channel
      slv_resp_valid              => open,
      slv_resp_ready              => open,
      slv_resp_ok                 => open,
      -- Master response channel
      mst_resp_valid              => my_bus_resp_b.valid,
      mst_resp_ready              => my_bus_resp_b.ready,
      mst_resp_ok                 => my_bus_resp_b.ok
    );

  mmu_barrier : MMBarrier
    generic map (
      BUS_ADDR_WIDTH              => BUS_ADDR_WIDTH,
      BUS_LEN_WIDTH               => BUS_LEN_WIDTH,
      MAX_OUTSTANDING             => 1
    )
    port map (
      clk                         => clk,
      reset                       => reset,
      dirty                       => mmu_bus_wreq.dirty,

      -- Slave write request channel
      slv_wreq_valid              => mmu_bus_wreq.valid,
      slv_wreq_ready              => mmu_bus_wreq.ready,
      slv_wreq_addr               => mmu_bus_wreq.addr,
      slv_wreq_len                => mmu_bus_wreq.len,
      slv_wreq_barrier            => mmu_bus_wreq.barrier,
      -- Master write request channel
      mst_wreq_valid              => mmu_bus_wreq_b.valid,
      mst_wreq_ready              => mmu_bus_wreq_b.ready,
      mst_wreq_addr               => mmu_bus_wreq_b.addr,
      mst_wreq_len                => mmu_bus_wreq_b.len,

      -- Slave response channel
      slv_resp_valid              => open,
      slv_resp_ready              => open,
      slv_resp_ok                 => open,
      -- Master response channel
      mst_resp_valid              => mmu_bus_resp_b.valid,
      mst_resp_ready              => mmu_bus_resp_b.ready,
      mst_resp_ok                 => mmu_bus_resp_b.ok
    );

  pt_reader_inst : BufferReader
    generic map (
      BUS_ADDR_WIDTH              => BUS_ADDR_WIDTH,
      BUS_LEN_WIDTH               => BUS_LEN_WIDTH,
      BUS_DATA_WIDTH              => BUS_DATA_WIDTH,
      -- Do not burst more than one page table, even if the bus supports it.
      BUS_BURST_STEP_LEN          => work.Utils.min(BUS_BURST_STEP_LEN, (PT_SIZE / BUS_DATA_BYTES)),
      BUS_BURST_MAX_LEN           => work.Utils.min(BUS_BURST_MAX_LEN, (PT_SIZE / BUS_DATA_BYTES)),

      -- Bus response and internal command stream FIFO depth. The maximum number
      -- of outstanding requests is approximately this number divided by the
      -- burst length. If set to 2, a register slice is inserted instead of a
      -- FIFO. If set to 0, the buffers are omitted.
      BUS_FIFO_DEPTH              => work.Utils.min(BUS_BURST_MAX_LEN*4, (PT_SIZE / BUS_DATA_BYTES)),
      -- Element FIFO size in number of elements.
      ELEMENT_FIFO_SIZE           => 0,

      -- Since the last index is exclusive, add an extra bit.
      INDEX_WIDTH                 => PT_ENTRIES_LOG2 - log2ceil(BUS_DATA_WIDTH / PTE_WIDTH) + 1,
      ELEMENT_WIDTH               => BUS_DATA_WIDTH, --PTE_WIDTH,
      --ELEMENT_COUNT_MAX           => BUS_DATA_WIDTH / PTE_WIDTH,
      --ELEMENT_COUNT_WIDTH         => log2ceil(BUS_DATA_WIDTH / PTE_WIDTH),

      CMD_IN_SLICE                => false,
      BUS_REQ_SLICE               => false,
      CMD_OUT_SLICE               => false,
      UNLOCK_SLICE                => false,
      SHR2GB_SLICE                => false,
      GB2FIFO_SLICE               => false,
      FIFO2POST_SLICE             => false,
      OUT_SLICE                   => false
    )
    port map (
      bus_clk                     => clk,
      bus_reset                   => reset,
      acc_clk                     => clk,
      acc_reset                   => reset,

      cmdIn_valid                 => pt_reader_cmd_valid,
      cmdIn_ready                 => pt_reader_cmd_ready,
      cmdIn_firstIdx              => pt_reader_cmd_firstIdx,
      cmdIn_lastIdx               => pt_reader_cmd_lastIdx,
      cmdIn_baseAddr              => pt_reader_cmd_baseAddr,

      bus_rreq_valid              => pt_bus_rreq.valid,
      bus_rreq_ready              => pt_bus_rreq.ready,
      bus_rreq_addr               => pt_bus_rreq.addr,
      bus_rreq_len                => pt_bus_rreq.len,

      bus_rdat_valid              => pt_bus_rdat.valid,
      bus_rdat_ready              => pt_bus_rdat.ready,
      bus_rdat_data               => pt_bus_rdat.data,
      bus_rdat_last               => pt_bus_rdat.last,

      out_valid                   => pt_reader.valid,
      out_ready                   => pt_reader.ready,
      out_data                    => pt_reader.data,
      --out_count                   => pt_reader_count,
      out_last                    => pt_reader.last
    );

  bus_w_arbiter : BusWriteArbiter
    generic map (
      BUS_ADDR_WIDTH              => BUS_ADDR_WIDTH,
      BUS_LEN_WIDTH               => BUS_LEN_WIDTH,
      BUS_DATA_WIDTH              => BUS_DATA_WIDTH,
      BUS_STROBE_WIDTH            => BUS_STROBE_WIDTH,
      NUM_SLAVE_PORTS             => 2,
      ARB_METHOD                  => "FIXED",
      MAX_OUTSTANDING             => MAX_OUTSTANDING_TRANSACTIONS,
      SLV_REQ_SLICES              => false,
      MST_REQ_SLICE               => false,
      MST_DAT_SLICE               => false,
      SLV_DAT_SLICES              => false,
      MST_RSP_SLICE               => false,
      SLV_RSP_SLICES              => false
    )
    port map (
      bus_clk                   => clk,
      bus_reset                 => reset,

      mst_wreq_valid            => bus_wreq_valid,
      mst_wreq_ready            => bus_wreq_ready,
      mst_wreq_addr             => bus_wreq_addr,
      mst_wreq_len              => bus_wreq_len,
      mst_wdat_valid            => bus_wdat_valid,
      mst_wdat_ready            => bus_wdat_ready,
      mst_wdat_data             => bus_wdat_data,
      mst_wdat_strobe           => bus_wdat_strobe,
      mst_wdat_last             => bus_wdat_last,
      mst_resp_valid            => bus_resp_valid,
      mst_resp_ready            => bus_resp_ready,
      mst_resp_ok               => bus_resp_ok,

      bs00_wreq_valid           => mmu_bus_wreq_b.valid,
      bs00_wreq_ready           => mmu_bus_wreq_b.ready,
      bs00_wreq_addr            => mmu_bus_wreq_b.addr,
      bs00_wreq_len             => mmu_bus_wreq_b.len,
      bs00_wdat_valid           => mmu_bus_wdat.valid,
      bs00_wdat_ready           => mmu_bus_wdat.ready,
      bs00_wdat_data            => mmu_bus_wdat.data,
      bs00_wdat_strobe          => mmu_bus_wdat.strobe,
      bs00_wdat_last            => mmu_bus_wdat.last,
      bs00_resp_valid           => mmu_bus_resp_b.valid,
      bs00_resp_ready           => mmu_bus_resp_b.ready,
      bs00_resp_ok              => mmu_bus_resp_b.ok,

      bs01_wreq_valid           => my_bus_wreq_b.valid,
      bs01_wreq_ready           => my_bus_wreq_b.ready,
      bs01_wreq_addr            => my_bus_wreq_b.addr,
      bs01_wreq_len             => my_bus_wreq_b.len,
      bs01_wdat_valid           => my_bus_wdat.valid,
      bs01_wdat_ready           => my_bus_wdat.ready,
      bs01_wdat_data            => my_bus_wdat.data,
      bs01_wdat_strobe          => my_bus_wdat.strobe,
      bs01_wdat_last            => my_bus_wdat.last,
      bs01_resp_valid           => my_bus_resp_b.valid,
      bs01_resp_ready           => my_bus_resp_b.ready,
      bs01_resp_ok              => my_bus_resp_b.ok
    );

  bus_r_arbiter : BusReadArbiter
    generic map (
      BUS_ADDR_WIDTH              => BUS_ADDR_WIDTH,
      BUS_LEN_WIDTH               => BUS_LEN_WIDTH,
      BUS_DATA_WIDTH              => BUS_DATA_WIDTH,
      NUM_SLAVE_PORTS             => 3,
      ARB_METHOD                  => "FIXED",
      MAX_OUTSTANDING             => 2,
      SLV_REQ_SLICES              => false,
      MST_REQ_SLICE               => BUS_RREQ_SLICE,
      MST_DAT_SLICE               => BUS_RDAT_SLICE,
      SLV_DAT_SLICES              => false
    )
    port map (
      bus_clk                     => clk,
      bus_reset                   => reset,

      mst_rreq_valid              => bus_rreq_valid,
      mst_rreq_ready              => bus_rreq_ready,
      mst_rreq_addr               => bus_rreq_addr,
      mst_rreq_len                => bus_rreq_len,
      mst_rdat_valid              => bus_rdat_valid,
      mst_rdat_ready              => bus_rdat_ready,
      mst_rdat_data               => bus_rdat_data,
      mst_rdat_last               => bus_rdat_last,

      bs00_rreq_valid             => mmu_bus_rreq.valid,
      bs00_rreq_ready             => mmu_bus_rreq.ready,
      bs00_rreq_addr              => mmu_bus_rreq.addr,
      bs00_rreq_len               => mmu_bus_rreq.len,
      bs00_rdat_valid             => mmu_bus_rdat.valid,
      bs00_rdat_ready             => mmu_bus_rdat.ready,
      bs00_rdat_data              => mmu_bus_rdat.data,
      bs00_rdat_last              => mmu_bus_rdat.last,

      bs01_rreq_valid             => my_bus_rreq.valid,
      bs01_rreq_ready             => my_bus_rreq.ready,
      bs01_rreq_addr              => my_bus_rreq.addr,
      bs01_rreq_len               => my_bus_rreq.len,
      bs01_rdat_valid             => my_bus_rdat.valid,
      bs01_rdat_ready             => my_bus_rdat.ready,
      bs01_rdat_data              => my_bus_rdat.data,
      bs01_rdat_last              => my_bus_rdat.last,

      bs02_rreq_valid             => pt_bus_rreq.valid,
      bs02_rreq_ready             => pt_bus_rreq.ready,
      bs02_rreq_addr              => pt_bus_rreq.addr,
      bs02_rreq_len               => pt_bus_rreq.len,
      bs02_rdat_valid             => pt_bus_rdat.valid,
      bs02_rdat_ready             => pt_bus_rdat.ready,
      bs02_rdat_data              => pt_bus_rdat.data,
      bs02_rdat_last              => pt_bus_rdat.last
    );

end architecture;


