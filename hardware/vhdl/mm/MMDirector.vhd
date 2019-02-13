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
  constant PT_SIZE_LOG2         : natural := PT_ENTRIES_LOG2 + log2ceil( (PTE_BITS+BYTE_SIZE-1) / BYTE_SIZE);
  constant PT_SIZE              : natural := 2**PT_SIZE_LOG2;
  -- Offset of the first usable PT into the frame (first space is taken by bitmap)
  constant PT_FIRST_NR          : natural := 1;
  constant PT_PER_FRAME         : natural := 2**(PAGE_SIZE_LOG2 - PT_ENTRIES_LOG2 - log2ceil( (PTE_BITS+BYTE_SIZE-1) / BYTE_SIZE)) - PT_FIRST_NR;
  constant PTE_SIZE             : natural := 2**log2ceil( (PTE_BITS+BYTE_SIZE-1) / BYTE_SIZE);

  constant PTE_MAPPED           : natural := 0;
  constant PTE_PRESENT          : natural := 1;

  constant VM_SIZE_L2_LOG2      : natural := PAGE_SIZE_LOG2;
  constant VM_SIZE_L1_LOG2      : natural := VM_SIZE_L2_LOG2 + PT_ENTRIES_LOG2;
  constant VM_SIZE_L0_LOG2      : natural := VM_SIZE_L1_LOG2 + PT_ENTRIES_LOG2;

  function OVERLAY (over  : unsigned;
                    under : unsigned)
    return unsigned is
    variable ret : unsigned(under'length-1 downto 0);
  begin
    ret := under;
    ret(over'length-1 downto 0) := over;
    return ret;
  end OVERLAY;

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

  function PTE_ADDR (pt_base : unsigned(BUS_ADDR_WIDTH-1 downto 0);
                     vm_addr : unsigned(BUS_ADDR_WIDTH-1 downto 0);
                     pt_level: natural)
    return unsigned is
    variable index : unsigned(PT_ENTRIES_LOG2-1 downto 0);
    variable ret : unsigned(BUS_ADDR_WIDTH-1 downto 0) := (others => '0');
  begin
    if pt_level = 1 then
      index := vm_addr(PAGE_SIZE_LOG2 + PT_ENTRIES_LOG2 * 2 - 1 downto PAGE_SIZE_LOG2 + PT_ENTRIES_LOG2);
    elsif pt_level = 2 then
      index := vm_addr(PAGE_SIZE_LOG2 + PT_ENTRIES_LOG2 downto PAGE_SIZE_LOG2);
    else
      index := (others => 'X');
    end if;
    return OVERLAY(
      shift_left(
        resize(index, index'length + log2ceil(PTE_SIZE)),
        log2ceil(PTE_SIZE)),
      pt_base);
  end PTE_ADDR;

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
  signal addr_vm, addr_vm_next  : unsigned(BUS_ADDR_WIDTH-1 downto 0);
  signal addr_pt, addr_pt_next  : unsigned(BUS_ADDR_WIDTH-1 downto 0);
  signal size, size_next        : unsigned(BUS_ADDR_WIDTH-1 downto 0);
  signal region, region_next    : unsigned(log2ceil(MEM_REGIONS)-1 downto 0);
  signal arg, arg_next          : unsigned(BYTE_SIZE-1 downto 0);
  signal beat, beat_next        : unsigned(log2ceil(BUS_BURST_MAX_LEN)-1 downto 0);

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
  constant STATE_STACK_DEPTH : natural := 3;
  type state_stack_type is array (STATE_STACK_DEPTH-1 downto 0) of state_type;
  signal state_stack, state_stack_next : state_stack_type;

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

begin
  assert PAGE_SIZE_LOG2 >= PT_ENTRIES_LOG2 + log2ceil( (PTE_BITS+BYTE_SIZE-1) / BYTE_SIZE)
    report "page table does not fit in a single page"
    severity failure;

  assert PT_PER_FRAME /= 1
    report "page table size equal to page size is not implemented (requires omission of bitmap)"
    severity failure;

  assert PT_PER_FRAME <= PT_SIZE * BYTE_SIZE
    report "page table bitmap extends into frame's first page table"
    severity failure;

  assert PT_SIZE / BUS_DATA_BYTES = (PT_SIZE + BUS_DATA_BYTES - 1) / BUS_DATA_BYTES
    report "page table size is not a multiple of the bus width"
    severity failure;

  assert BUS_DATA_BYTES / PTE_SIZE = (BUS_DATA_BYTES + PTE_SIZE - 1) / PTE_SIZE
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
        state_stack    <= (others => FAIL);
        state_stack(0) <= RESET_ST;
        addr    <= (others => '0');
        addr_vm <= (others => '0');
        addr_pt <= (others => '0');
        arg     <= (others => '0');
        size    <= (others => '0');
        beat    <= (others => '0');
      else
        state_stack <= state_stack_next;
        addr    <= addr_next;
        addr_vm <= addr_vm_next;
        addr_pt <= addr_pt_next;
        arg     <= arg_next;
        size    <= size_next;
        beat    <= beat_next;
      end if;
    end if;
  end process;

  process (state_stack, addr, addr_vm, addr_pt, arg, size, beat,
           cmd_region, cmd_addr, cmd_free, cmd_alloc, cmd_realloc, cmd_valid,
           resp_ready,
           frames_cmd_ready, frames_resp_addr, frames_resp_success, frames_resp_valid,
           bus_wreq_ready, bus_wdat_ready,
           bus_rreq_ready, bus_rdat_data, bus_rdat_last, bus_rdat_valid)
    variable counter : unsigned(BUS_ADDR_WIDTH-1 downto 0) := (others => '0');
  begin
    state_stack_next <= state_stack;
    addr_next        <= addr;
    addr_vm_next     <= addr_vm;
    addr_pt_next     <= addr_pt;
    arg_next         <= arg;
    size_next        <= size;
    beat_next        <= beat;

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

    case state_stack(0) is

    when RESET_ST =>
      state_stack_next(0) <= CLEAR_FRAMES;

    when CLEAR_FRAMES =>
      -- Clear the frames utilization bitmap.
      frames_cmd_valid <= '1';
      frames_cmd_clear <= '1';
      if frames_cmd_ready = '1' then
        state_stack_next(0) <= CLEAR_FRAMES_CHECK;
      end if;

    when CLEAR_FRAMES_CHECK =>
      -- Check the clear command response.
      frames_resp_ready <= '1';
      if frames_resp_valid = '1' then
        if frames_resp_success = '1' then
          state_stack_next(0) <= RESERVE_PT;
        else
          state_stack_next(0) <= FAIL;
        end if;
      end if;

    when RESERVE_PT =>
      -- Reserve the designated frame for the root page table.
      frames_cmd_valid <= '1';
      frames_cmd_alloc <= '1';
      frames_cmd_addr  <= slv(PAGE_BASE(PT_ADDR));
      if frames_cmd_ready = '1' then
        state_stack_next(0) <= RESERVE_PT_CHECK;
      end if;

    when RESERVE_PT_CHECK =>
      -- Check the address of the reserved frame.
      -- Execute the `frame initialize' routine to set bitmap, continue to PT0_INIT.
      frames_resp_ready <= '1';
      if frames_resp_valid = '1' then
        if (frames_resp_success = '1') and (u(frames_resp_addr) = PAGE_BASE(PT_ADDR)) then
          state_stack_next(0) <= PT_FRAME_INIT_ADDR;
          state_stack_next(1) <= PT0_INIT;
          addr_next           <= PAGE_BASE(PT_ADDR);
        else
          state_stack_next(0) <= FAIL;
        end if;
      end if;

    when PT0_INIT =>
      -- Initialize the root page table by executing the `new page table' routine.
      state_stack_next(0) <= PT_NEW;
      state_stack_next(1) <= IDLE;
      addr_next           <= PT_ADDR;

    when IDLE =>
      if cmd_valid = '1' then

        if cmd_alloc = '1' then
          if unsigned(cmd_region) = 0 then
            -- TODO: host allocation
            state_stack_next(0) <= FAIL;
          else
            state_stack_next <= push_state(state_stack, VMALLOC);
          end if;

        elsif cmd_free = '1' then
          -- TODO
          state_stack_next(0) <= FAIL;

        elsif cmd_realloc = '1' then
          -- TODO
          state_stack_next(0) <= FAIL;
        end if;
      end if;

    -- === START OF VMALLOC ROUTINE ===
    -- Find big enough free chunk in virtual address space.
    -- Allocate single frame for start of allocation in the given region.
    -- `addr_vm' will contain virtual address of allocation.

    when VMALLOC =>
      -- Request the L0 page table to find a high-level gap.
      -- TODO: find gaps in lower level page tables.
      addr_next <= PT_ADDR;
      size_next <= (others => '0');
      state_stack_next(0) <= VMALLOC_CHECK_PT0;

    when VMALLOC_CHECK_PT0 =>
      bus_rreq_valid <= '1';
      bus_rreq_addr  <= slv(addr);
      bus_rreq_len   <= slv(to_unsigned(1, bus_wreq_len'length));
      if bus_rreq_ready = '1' then
        state_stack_next(0) <= VMALLOC_CHECK_PT0_DATA;
      end if;

    when VMALLOC_CHECK_PT0_DATA =>
      -- Check the returned PTEs for allocation gaps.
      bus_rdat_ready <= '1';
      if bus_rdat_valid = '1' then
        -- For each PTE in the beat
        counter := size;
        for i in 0 to BUS_DATA_BYTES / PTE_SIZE - 1 loop
          if bus_rdat_data(PTE_SIZE*i + PTE_MAPPED) = '0' then
            if counter = 0 then
              -- Start of gap
              addr_vm_next <= shift_left(PT_OFFSET(addr), VM_SIZE_L1_LOG2);
            end if;
            -- Increase size of gap
            counter := counter + 1;
          else -- PTE_MAPPED
            -- Make gap invalid
            counter := (others => '0');
          end if;
          exit when counter >= shift_right_round_up(unsigned(cmd_size), VM_SIZE_L1_LOG2);
        end loop;
        size_next <= counter;

        if counter >= shift_right_round_up(unsigned(cmd_size), VM_SIZE_L1_LOG2) then
          -- Gap is big enough, continue to allocate a frame
          state_stack_next(0) <= VMALLOC_RESERVE_FRAME;
        else
          -- Check more L0 entries
          state_stack_next(0) <= VMALLOC_CHECK_PT0;
          addr_next           <= addr + BUS_DATA_BYTES;
        end if;
      end if;

    when VMALLOC_RESERVE_FRAME =>
      -- Find a frame in the given region, result will be available later.
      frames_cmd_valid  <= '1';
      frames_cmd_find   <= '1';
      frames_cmd_region <= slv(unsigned(cmd_region) - 1);
      if frames_cmd_ready = '1' then
        -- addr_vm  : virtual base address to start at
        -- cmd_size : length to set
        state_stack_next    <= push_state(state_stack, SET_PTE_RANGE);
        state_stack_next(1) <= VMALLOC_FINISH;
        size_next <= unsigned(cmd_size);
        -- Take first page mapping from frame allocator
        arg_next  <= to_unsigned(1, arg'length);
        addr_next <= (others => '0');
      end if;

    when VMALLOC_FINISH =>
      resp_valid   <= '1';
      resp_success <= '1';
      resp_addr    <= slv(addr_vm);
      if resp_ready = '1' then
        state_stack_next <= pop_state(state_stack);
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
      bus_rreq_valid <= '1';
      bus_rreq_addr  <= slv(ADDR_BUS_ALIGN(PTE_ADDR(PT_ADDR, addr, 1)));
      bus_rreq_len   <= slv(to_unsigned(1, bus_wreq_len'length));
      if bus_rreq_ready = '1' then
        state_stack_next(0) <= SET_PTE_RANGE_L1_CHECK;
      end if;

    when SET_PTE_RANGE_L1_CHECK =>
      bus_rdat_ready <= '1';
      if bus_rdat_valid = '1' then
        -- Check PRESENT bit of PTE referred to by addr.
        if bus_rdat_data(
             PTE_SIZE * int(ADDR_BUS_OFFSET(PTE_ADDR(PT_ADDR, addr, 1)))
             + PTE_PRESENT
           ) = '1'
        then
          -- Page table already exists.
          addr_pt_next <= align_beq(
              u(bus_rdat_data(
                BYTE_SIZE * (PTE_SIZE * int(ADDR_BUS_OFFSET(PTE_ADDR(PT_ADDR, addr, 1))) + PTE_SIZE)
                downto
                BYTE_SIZE * PTE_SIZE * int(ADDR_BUS_OFFSET(PTE_ADDR(PT_ADDR, addr, 1)))
              )),
              PT_SIZE_LOG2
            );
          state_stack_next(0) <= SET_PTE_RANGE_L2_UPDATE_ADDR;
        else
          -- Need to allocate a page table.
          state_stack_next    <= push_state(state_stack, PT_NEW);
          state_stack_next(1) <= SET_PTE_RANGE_L1_UPDATE_ADDR;
        end if;
      end if;

    when SET_PTE_RANGE_L1_UPDATE_ADDR =>
      -- A new PT was allocated, update the corresponding L1 entry.
      bus_wreq_valid <= '1';
      bus_wreq_addr  <= slv(ADDR_BUS_ALIGN(PTE_ADDR(PT_ADDR, addr, 1)));
      bus_wreq_len   <= slv(to_unsigned(1, bus_wreq_len'length));
      if bus_wreq_ready = '1' then
        state_stack_next(0) <= SET_PTE_RANGE_L1_UPDATE_DAT;
      end if;

    when SET_PTE_RANGE_L1_UPDATE_DAT =>
      -- Update the PTE
      bus_wdat_valid  <= '1';
      bus_wdat_last   <= '1';
      -- Duplicate the address over the data bus
      for i in 0 to BUS_DATA_BYTES/PTE_SIZE-1 loop
        bus_wdat_data(PTE_SIZE * (i+1) - 1 downto PTE_SIZE * i) <= slv(addr_pt);
        -- Mark the entry as mapped and present
        bus_wdat_data(PTE_SIZE * i + PTE_MAPPED)  <= '1';
        bus_wdat_data(PTE_SIZE * i + PTE_PRESENT) <= '1';
      end loop;
      -- Use strobe to write the correct entry
      bus_wdat_strobe <= (others => '0');
      bus_wdat_strobe(
          PTE_SIZE * int(ADDR_BUS_OFFSET(PTE_ADDR(PT_ADDR, addr, 1))) + PTE_SIZE
          downto
          PTE_SIZE * int(ADDR_BUS_OFFSET(PTE_ADDR(PT_ADDR, addr, 1)))
        ) <= (others => '1');
      if bus_wdat_ready = '1' then
        state_stack_next(0) <= SET_PTE_RANGE_L2_UPDATE_ADDR;
      end if;

    when SET_PTE_RANGE_L2_UPDATE_ADDR =>
      bus_wreq_valid <= '1';
      bus_wreq_addr  <= slv(ADDR_BUS_ALIGN(PTE_ADDR(PT_ADDR, addr, 2)));
      bus_wreq_len   <= slv(to_unsigned(1, bus_wreq_len'length));
      if bus_wreq_ready = '1' then
        state_stack_next(0) <= SET_PTE_RANGE_L2_UPDATE_DAT;
      end if;

    when SET_PTE_RANGE_L2_UPDATE_DAT =>
      frames_resp_ready <= '1';
      if frames_resp_valid = '1' then
        bus_wdat_valid  <= '1';
      end if;
      bus_wdat_last   <= '1';
      -- Duplicate the address over the data bus.
      for i in 0 to BUS_DATA_BYTES/PTE_SIZE-1 loop
        if arg(0) = '1' then
          -- Map to the allocated frame.
          bus_wdat_data(PTE_SIZE * (i+1) - 1 downto PTE_SIZE * i) <= frames_resp_addr;
          -- Mark the entry as mapped and present.
          bus_wdat_data(PTE_SIZE * i + PTE_MAPPED)  <= '1';
          bus_wdat_data(PTE_SIZE * i + PTE_PRESENT) <= '1';
        else
          -- Mark as mapped, but do not allocate frames.
          bus_wdat_data(PTE_SIZE * (i+1) - 1 downto PTE_SIZE * i) <= (others => '0');
          bus_wdat_data(PTE_SIZE * i + PTE_MAPPED)  <= '1';
        end if;
      end loop;
      -- Do not try to use allocated frame on next iteration.
      arg_next(0) <= '0';
      -- Use strobe to write the correct entry.
      bus_wdat_strobe <= (others => '0');
      bus_wdat_strobe(
          PTE_SIZE * int(ADDR_BUS_OFFSET(PTE_ADDR(PT_ADDR, addr, 2))) + PTE_SIZE
          downto
          PTE_SIZE * int(ADDR_BUS_OFFSET(PTE_ADDR(PT_ADDR, addr, 2)))
        ) <= (others => '1');
      if bus_wdat_ready = '1' then
      --TODO update address, check allocated size; return to L1 on boundary.
        state_stack_next(0) <= SET_PTE_RANGE_L2_UPDATE_ADDR;
      end if;

    -- === START OF FRAME_INIT ROUTINE ===
    -- Clear the usage bitmap of the frame at `addr'.
    -- `addr' is not preserved, but will continue to point into the same frame.
    -- Does not preserve contents of the frame.

    when PT_FRAME_INIT_ADDR =>
      -- Can write further than the bitmap,
      -- because the entire frame should be unused at this point.
      bus_wreq_valid <= '1';
      bus_wreq_addr  <= slv(addr);
      bus_wreq_len   <= slv(to_unsigned(1, bus_wreq_len'length));
      if bus_wreq_ready = '1' then
        state_stack_next(0) <= PT_FRAME_INIT_DATA;
        if (PT_PER_FRAME > BUS_DATA_WIDTH) then
          -- Need another write on a higher address
          addr_next  <= unsigned(addr) + BUS_DATA_BYTES;
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
          state_stack_next <= pop_state(state_stack);
        else
          -- Need another write
          state_stack_next(0) <= PT_FRAME_INIT_ADDR;
        end if;
      end if;

    -- === START OF PT_NEW ROUTINE ===
    -- Find a free spot for a page table on frame `addr',
    -- mark it as used, and initialize the page table.
    -- `addr_pt' will contain the base address of the new page table.
    -- `addr` remains unchanged.

    when PT_NEW =>
      -- Find a free spot for a PT
      bus_rreq_valid <= '1';
      bus_rreq_addr  <= slv(PAGE_BASE(addr));
      bus_rreq_len   <= slv(to_unsigned(1, bus_rreq_len'length));
      -- Use addr_pt to store addr
      addr_pt_next   <= addr;
      -- TODO implement finding empty spots past BUS_DATA_WIDTH entries
      if bus_rreq_ready = '1' then
        state_stack_next(0) <= PT_NEW_CHECK_BM;
      end if;

    when PT_NEW_CHECK_BM =>
      -- Load the adjacent bitmap bits before marking a bit.
      -- We need this, because the write strobe has byte granularity.
      bus_rdat_ready <= '1';
      if bus_rdat_valid = '1' then
        for i in 0 to work.Utils.min(PT_PER_FRAME, BUS_DATA_WIDTH) loop
          if i = work.Utils.min(PT_PER_FRAME, BUS_DATA_WIDTH) then
            addr_next           <= PAGE_BASE(addr);
            state_stack_next(0) <= FAIL; -- TODO: try more bits or other frame
            exit;
          end if;
          if bus_rdat_data(i) = '0' then
            -- Bit 0 refers to the first possible page table in this frame,
            -- which exists on the first aligned location after the bitmap.
            state_stack_next(0) <= PT_NEW_MARK_BM_ADDR;
            addr_next           <= OVERLAY(
                                     shift_left(to_unsigned(i+1, PAGE_SIZE_LOG2), PT_SIZE_LOG2),
                                     PAGE_BASE(addr));
            -- Save the byte that needs to be written
            arg_next            <= resize(unsigned(bus_rdat_data((i/BYTE_SIZE)*BYTE_SIZE+BYTE_SIZE-1 downto (i/BYTE_SIZE)*BYTE_SIZE)), arg_next'length);
            arg_next(i mod BYTE_SIZE) <= '1';
            exit;
          end if;
        end loop;
      end if;

    when PT_NEW_MARK_BM_ADDR =>
      -- Set address for marking bit in bitmap
      bus_wreq_valid <= '1';
      bus_wreq_addr  <= slv(PAGE_BASE(addr));
      bus_wreq_len   <= slv(to_unsigned(1, bus_wreq_len'length));
      -- TODO: enable bitmap location > BUS_DATA_WIDTH
      if bus_wreq_ready = '1' then
        state_stack_next(0) <= PT_NEW_MARK_BM_DATA;
      end if;

    when PT_NEW_MARK_BM_DATA =>
      bus_wdat_valid  <= '1';
      for i in 0 to BUS_DATA_BYTES-1 loop
        bus_wdat_data(BYTE_SIZE*(i+1)-1 downto BYTE_SIZE*i) <= slv(arg(BYTE_SIZE-1 downto 0));
      end loop;
      bus_wdat_strobe <= (others => '0');
      -- Get page table number referenced by addr and figure out which byte of the bitmap it is in.
      bus_wdat_strobe(int(
        div_floor(
          shift_right_cut(PAGE_OFFSET(addr), PT_SIZE_LOG2) - PT_FIRST_NR,
          BYTE_SIZE)
        )) <= '1';
      bus_wdat_last <= '1';
      if bus_wdat_ready = '1' then
        state_stack_next(0) <= PT_NEW_CLEAR_ADDR;
      end if;

    when PT_NEW_CLEAR_ADDR =>
      bus_wreq_valid <= '1';
      bus_wreq_addr  <= slv(addr);
      -- The number of beats in the burst
      beat_next      <= to_unsigned(
                          work.Utils.min(
                            BUS_BURST_MAX_LEN,
                            int(div_ceil(
                              to_unsigned(PT_SIZE, log2ceil(PT_SIZE)) - PT_OFFSET(addr),
                              BUS_DATA_BYTES))
                          ),
                          beat'length);
      bus_wreq_len   <= slv(resize(beat_next, bus_wreq_len'length));
      if bus_wreq_ready = '1' then
        state_stack_next(0) <= PT_NEW_CLEAR_DATA;
        addr_next           <= addr + beat_next * BUS_DATA_BYTES;
      end if;

    when PT_NEW_CLEAR_DATA =>
      bus_wdat_valid  <= '1';
      bus_wdat_data   <= (others => '0');
      bus_wdat_strobe <= (others => '1');
      bus_wdat_last <= '1';
      if bus_wdat_ready = '1' then
        -- One beat processed
        beat_next <= beat - 1;
        if beat = 1 then
          -- This is the last beat
          if PT_OFFSET(addr) = 0 then
            -- Set return and restore addr
            addr_pt_next <= addr - PT_SIZE;
            addr_next    <= addr_pt;
            state_stack_next <= pop_state(state_stack);
          else
            state_stack_next(0) <= PT_NEW_CLEAR_ADDR;
          end if;
        end if;
      end if;

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


