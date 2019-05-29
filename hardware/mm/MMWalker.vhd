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
use work.Interconnect.all;
use work.Streams.all;
use work.MM.all;

entity MMWalker is
  generic (
    PAGE_SIZE_LOG2              : natural;
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
    BUS_BURST_MAX_LEN           : natural := 16;

    MAX_OUTSTANDING_BUS         : positive := 1;
    MAX_OUTSTANDING_DIR         : positive := 1
  );
  port (
    clk                         : in  std_logic;
    reset                       : in  std_logic;

    -- Read address channel
    bus_rreq_addr               : out std_logic_vector(BUS_ADDR_WIDTH-1 downto 0);
    bus_rreq_len                : out std_logic_vector(BUS_LEN_WIDTH-1 downto 0);
    bus_rreq_valid              : out std_logic;
    bus_rreq_ready              : in  std_logic;

    -- Read data channel
    bus_rdat_data               : in  std_logic_vector(BUS_DATA_WIDTH-1 downto 0);
    bus_rdat_last               : in  std_logic;
    bus_rdat_valid              : in  std_logic;
    bus_rdat_ready              : out std_logic;

    -- Translate request channel
    req_valid                   : in  std_logic;
    req_ready                   : out std_logic;
    req_addr                    : in  std_logic_vector(BUS_ADDR_WIDTH-1 downto 0);
    -- Translate response channel
    resp_valid                  : out std_logic;
    resp_ready                  : in  std_logic;
    resp_virt                   : out std_logic_vector(BUS_ADDR_WIDTH-1 downto 0);
    resp_phys                   : out std_logic_vector(BUS_ADDR_WIDTH-1 downto 0);
    resp_mask                   : out std_logic_vector(BUS_ADDR_WIDTH-1 downto 0);

    dir_req_valid               : out std_logic;
    dir_req_ready               : in  std_logic := '0';
    dir_req_addr                : out std_logic_vector(BUS_ADDR_WIDTH-1 downto 0);
    
    dir_resp_valid              : in  std_logic := '0';
    dir_resp_ready              : out std_logic;
    dir_resp_addr               : in  std_logic_vector(BUS_ADDR_WIDTH-1 downto 0) := (others => '0')
  );
end MMWalker;


architecture Behavioral of MMWalker is
  constant BUS_DATA_BYTES       : natural := BUS_DATA_WIDTH / BYTE_SIZE;
  constant PT_SIZE_LOG2         : natural := PT_ENTRIES_LOG2 + log2ceil(DIV_CEIL(PTE_BITS, BYTE_SIZE));
  constant PTE_SIZE             : natural := 2**log2ceil(DIV_CEIL(PTE_BITS, BYTE_SIZE));
  constant PTE_WIDTH            : natural := PTE_SIZE * BYTE_SIZE;

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

  type bus_r_type is record
    req_valid  : std_logic;
    req_ready  : std_logic;
    req_addr   : std_logic_vector(BUS_ADDR_WIDTH-1 downto 0);
    req_len    : std_logic_vector(BUS_LEN_WIDTH-1 downto 0);
    dat_valid  : std_logic;
    dat_ready  : std_logic;
    dat_data   : std_logic_vector(BUS_DATA_WIDTH-1 downto 0);
    dat_last   : std_logic;
  end record;

  type request_type is record
    valid      : std_logic;
    ready      : std_logic;
    virt       : std_logic_vector(BUS_ADDR_WIDTH-1 downto 0);
    phys       : std_logic_vector(BUS_ADDR_WIDTH-1 downto 0);
    use_dir    : std_logic;
    concat     : std_logic_vector(BUS_ADDR_WIDTH*2 downto 0);
  end record;

  signal queue_l1_in     : request_type;
  signal queue_l1_out    : request_type;
  signal queue_l2_in     : request_type;
  signal queue_l2_out    : request_type;
  signal queue_dir_in    : request_type;
  signal queue_dir_out   : request_type;

  signal bus_l1          : bus_r_type;
  signal bus_l2          : bus_r_type;
begin

  process (bus_l1, bus_l2, req_addr)
  begin
    -- Step 1: Request L1 page table entry.
    bus_l1.req_len           <= slv(to_unsigned(1, BUS_LEN_WIDTH));
    bus_l1.req_addr          <= slv(ADDR_BUS_ALIGN(VA_TO_PTE(PT_ADDR, u(req_addr), 1)));
    queue_l1_in.virt         <= req_addr;
  end process;

  process (queue_l1_out, bus_l1) is
    variable addr_pt : unsigned(BUS_ADDR_WIDTH-1 downto 0);
  begin
    -- Step 2: Request L2 page table entry based on L1 entry.
    queue_l2_in.virt         <= queue_l1_out.virt;

    -- Check on valid is not necessary, but avoids some simulator warnings about metavalues.
    if queue_l1_out.valid = '1' then
    -- Select the right PTE from the data bus
    -- and use the resulting address to request the L2 entry.
      addr_pt := align_beq(
          EXTRACT(
            unsigned(bus_l1.dat_data),
            BYTE_SIZE * int(ADDR_BUS_OFFSET(VA_TO_PTE(PT_ADDR, u(queue_l1_out.virt), 1))),
            BYTE_SIZE * PTE_SIZE
          ),
          PT_SIZE_LOG2
        );
      bus_l2.req_addr        <= slv(
                               ADDR_BUS_ALIGN(
                                 VA_TO_PTE(
                                   addr_pt,
                                   u(queue_l1_out.virt),
                                   2)));
    else
      bus_l2.req_addr        <= (others => 'U');
    end if;

    bus_l2.req_len           <= slv(to_unsigned(1, BUS_LEN_WIDTH));
  end process;

  process (queue_l2_out, bus_l2)
  begin
    -- Step 3: Resolve address or pass on to MMDirector.
    queue_dir_in.virt        <= queue_l2_out.virt;
    dir_req_addr             <= queue_l2_out.virt;

    -- Check on valid is not necessary, but avoids some simulator warnings about metavalues.
    if queue_l2_out.valid = '1' then
    -- Use PT_ADDR instead of the real `addr_pt'. This is allowable, 
    -- because the address offset into the data bus will be the same for these.
      queue_dir_in.phys      <= slv(align_beq(
          EXTRACT(
            unsigned(bus_l2.dat_data),
            BYTE_SIZE * int(ADDR_BUS_OFFSET(VA_TO_PTE(PT_ADDR, u(queue_l2_out.virt), 2))),
            BYTE_SIZE * PTE_SIZE
          ),
          PAGE_SIZE_LOG2
        ));
      if slv(EXTRACT(
            unsigned(bus_l2.dat_data),
            BYTE_SIZE * int(ADDR_BUS_OFFSET(VA_TO_PTE(PT_ADDR, u(queue_l2_out.virt), 2))) + PTE_PRESENT,
            1
          )) = "1"
        and slv(EXTRACT(
            unsigned(bus_l2.dat_data),
            BYTE_SIZE * int(ADDR_BUS_OFFSET(VA_TO_PTE(PT_ADDR, u(queue_l2_out.virt), 2))) + PTE_MAPPED,
            1
          )) = "1"
      then
        -- Page is mapped and present. Physical address is now known.
        queue_dir_in.use_dir <= '0';
      else
        -- Page is not mapped or not present, let MMDirector figure this one out.
        queue_dir_in.use_dir <= '1';
      end if;
    else
      queue_dir_in.phys      <= (others => 'U');
      queue_dir_in.use_dir   <= 'U';
    end if;
  end process;

  process (queue_dir_out, dir_resp_addr)
  begin
    -- Step 4: Optionally wait for MMDirector response.
    resp_virt                <= queue_dir_out.virt;
    if queue_dir_out.use_dir = '1' then
      resp_phys              <= dir_resp_addr;
    else
      resp_phys              <= queue_dir_out.phys;
    end if;
    -- Create mask for single page
    resp_mask                <= slv(shift_left(
                                  u(std_logic_vector(to_signed(-1, BUS_ADDR_WIDTH))),
                                  PAGE_SIZE_LOG2));

  end process;

  sync_l1_inst : StreamSync
    generic map (
      NUM_INPUTS                  => 1,
      NUM_OUTPUTS                 => 2
    )
    port map (
      clk                         => clk,
      reset                       => reset,
      in_valid(0)                 => req_valid,
      in_ready(0)                 => req_ready,
      out_valid(0)                => queue_l1_in.valid,
      out_valid(1)                => bus_l1.req_valid,
      out_ready(0)                => queue_l1_in.ready,
      out_ready(1)                => bus_l1.req_ready
    );

  queue_l1_inst : StreamBuffer
    generic map (
      MIN_DEPTH                   => MAX_OUTSTANDING_BUS,
      DATA_WIDTH                  => BUS_ADDR_WIDTH
    )
    port map (
      clk                         => clk,
      reset                       => reset,
      in_valid                    => queue_l1_in.valid,
      in_ready                    => queue_l1_in.ready,
      in_data                     => queue_l1_in.virt,
      out_valid                   => queue_l1_out.valid,
      out_ready                   => queue_l1_out.ready,
      out_data                    => queue_l1_out.virt
    );

  sync_l2_inst : StreamSync
    generic map (
      NUM_INPUTS                  => 2,
      NUM_OUTPUTS                 => 2
    )
    port map (
      clk                         => clk,
      reset                       => reset,
      in_valid(0)                 => queue_l1_out.valid,
      in_valid(1)                 => bus_l1.dat_valid,
      in_ready(0)                 => queue_l1_out.ready,
      in_ready(1)                 => bus_l1.dat_ready,
      out_valid(0)                => queue_l2_in.valid,
      out_valid(1)                => bus_l2.req_valid,
      out_ready(0)                => queue_l2_in.ready,
      out_ready(1)                => bus_l2.req_ready
    );

  queue_l2_inst : StreamBuffer
    generic map (
      MIN_DEPTH                   => MAX_OUTSTANDING_BUS,
      DATA_WIDTH                  => BUS_ADDR_WIDTH
    )
    port map (
      clk                         => clk,
      reset                       => reset,
      in_valid                    => queue_l2_in.valid,
      in_ready                    => queue_l2_in.ready,
      in_data                     => queue_l2_in.virt,
      out_valid                   => queue_l2_out.valid,
      out_ready                   => queue_l2_out.ready,
      out_data                    => queue_l2_out.virt
    );

  sync_dir_inst : StreamSync
    generic map (
      NUM_INPUTS                  => 2,
      NUM_OUTPUTS                 => 2
    )
    port map (
      clk                         => clk,
      reset                       => reset,
      in_valid(0)                 => queue_l2_out.valid,
      in_valid(1)                 => bus_l2.dat_valid,
      in_ready(0)                 => queue_l2_out.ready,
      in_ready(1)                 => bus_l2.dat_ready,
      out_valid(0)                => queue_dir_in.valid,
      out_valid(1)                => dir_req_valid,
      out_ready(0)                => queue_dir_in.ready,
      out_ready(1)                => dir_req_ready,
      out_enable(0)               => '1',
      out_enable(1)               => queue_dir_in.use_dir
    );

  queue_dir_inst : StreamBuffer
    generic map (
      MIN_DEPTH                   => MAX_OUTSTANDING_DIR,
      DATA_WIDTH                  => BUS_ADDR_WIDTH * 2 + 1
    )
    port map (
      clk                         => clk,
      reset                       => reset,
      in_valid                    => queue_dir_in.valid,
      in_ready                    => queue_dir_in.ready,
      in_data                     => queue_dir_in.concat,
      out_valid                   => queue_dir_out.valid,
      out_ready                   => queue_dir_out.ready,
      out_data                    => queue_dir_out.concat
    );
  queue_dir_in.concat(BUS_ADDR_WIDTH-1 downto 0)                <= queue_dir_in.virt;
  queue_dir_in.concat(BUS_ADDR_WIDTH*2-1 downto BUS_ADDR_WIDTH) <= queue_dir_in.phys;
  queue_dir_in.concat(BUS_ADDR_WIDTH*2)                         <= queue_dir_in.use_dir;
  queue_dir_out.virt    <= queue_dir_out.concat(BUS_ADDR_WIDTH-1 downto 0);
  queue_dir_out.phys    <= queue_dir_out.concat(BUS_ADDR_WIDTH*2-1 downto BUS_ADDR_WIDTH);
  queue_dir_out.use_dir <= queue_dir_out.concat(BUS_ADDR_WIDTH*2);

  sync_out_inst : StreamSync
    generic map (
      NUM_INPUTS                  => 2,
      NUM_OUTPUTS                 => 1
    )
    port map (
      clk                         => clk,
      reset                       => reset,
      in_valid(0)                 => queue_dir_out.valid,
      in_valid(1)                 => dir_resp_valid,
      in_ready(0)                 => queue_dir_out.ready,
      in_ready(1)                 => dir_resp_ready,
      in_use(0)                   => '1',
      in_use(1)                   => queue_dir_out.use_dir,
      out_valid(0)                => resp_valid,
      out_ready(0)                => resp_ready
    );

   bus_arb_inst : BusReadArbiter
    generic map (
      BUS_ADDR_WIDTH              => BUS_ADDR_WIDTH,
      BUS_LEN_WIDTH               => BUS_LEN_WIDTH,
      BUS_DATA_WIDTH              => BUS_DATA_WIDTH,
      NUM_SLAVE_PORTS             => 2,
      ARB_METHOD                  => "FIXED",
      MAX_OUTSTANDING             => MAX_OUTSTANDING_BUS,
      SLV_REQ_SLICES              => false,
      MST_REQ_SLICE               => false,
      MST_DAT_SLICE               => false,
      SLV_DAT_SLICES              => true  --TODO: insert slice before queue_l2 instead
    )
    port map (
      bcd_clk                     => clk,
      bcd_reset                   => reset,

      mst_rreq_valid              => bus_rreq_valid,
      mst_rreq_ready              => bus_rreq_ready,
      mst_rreq_addr               => bus_rreq_addr,
      mst_rreq_len                => bus_rreq_len,
      mst_rdat_valid              => bus_rdat_valid,
      mst_rdat_ready              => bus_rdat_ready,
      mst_rdat_data               => bus_rdat_data,
      mst_rdat_last               => bus_rdat_last,

      bs00_rreq_valid             => bus_l2.req_valid,
      bs00_rreq_ready             => bus_l2.req_ready,
      bs00_rreq_addr              => bus_l2.req_addr,
      bs00_rreq_len               => bus_l2.req_len,
      bs00_rdat_valid             => bus_l2.dat_valid,
      bs00_rdat_ready             => bus_l2.dat_ready,
      bs00_rdat_data              => bus_l2.dat_data,
      bs00_rdat_last              => bus_l2.dat_last,

      bs01_rreq_valid             => bus_l1.req_valid,
      bs01_rreq_ready             => bus_l1.req_ready,
      bs01_rreq_addr              => bus_l1.req_addr,
      bs01_rreq_len               => bus_l1.req_len,
      bs01_rdat_valid             => bus_l1.dat_valid,
      bs01_rdat_ready             => bus_l1.dat_ready,
      bs01_rdat_data              => bus_l1.dat_data,
      bs01_rdat_last              => bus_l1.dat_last
    );

end architecture;

