-- Copyright 2018 Delft University of Technology
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
use ieee.std_logic_misc.all;
use ieee.numeric_std.all;

library work;
use work.UtilInt_pkg.all;
use work.Interconnect_pkg.all;
use work.Wrapper_pkg.all;
use work.MM_pkg.all;

entity fletcher_wrapper is
  generic(
    BUS_ADDR_WIDTH                             : natural;
    BUS_DATA_WIDTH                             : natural;
    BUS_STROBE_WIDTH                           : natural;
    BUS_LEN_WIDTH                              : natural;
    BUS_BURST_STEP_LEN                         : natural;
    BUS_BURST_MAX_LEN                          : natural;
    ---------------------------------------------------------------------------
    INDEX_WIDTH                                : natural;
    ---------------------------------------------------------------------------
    NUM_ARROW_BUFFERS                          : natural;
    NUM_REGS                                   : natural;
    NUM_USER_REGS                              : natural;
    REG_WIDTH                                  : natural;
    ---------------------------------------------------------------------------
    TAG_WIDTH                                  : natural;
    ---------------------------------------------------------------------------
    PAGE_SIZE_LOG2                             : natural := 22;
    VM_BASE                                    : unsigned;
    MEM_REGIONS                                : natural := 1;
    MEM_SIZES                                  : nat_array := (0 => 1024);
    MEM_MAP_BASE                               : unsigned;
    MEM_MAP_SIZE_LOG2                          : natural := 37;
    PT_ENTRIES_LOG2                            : natural := 13;
    PTE_BITS                                   : natural
  );
  port(
    kcd_reset                                  : in std_logic;
    bcd_clk                                    : in std_logic;
    bcd_reset                                  : in std_logic;
    kcd_clk                                    : in std_logic;
    ---------------------------------------------------------------------------
    mst_rreq_valid                             : out std_logic;
    mst_rreq_ready                             : in std_logic;
    mst_rreq_addr                              : out std_logic_vector(BUS_ADDR_WIDTH-1 downto 0);
    mst_rreq_len                               : out std_logic_vector(BUS_LEN_WIDTH-1 downto 0);
    ---------------------------------------------------------------------------
    mst_rdat_valid                             : in std_logic;
    mst_rdat_ready                             : out std_logic;
    mst_rdat_data                              : in std_logic_vector(BUS_DATA_WIDTH-1 downto 0);
    mst_rdat_last                              : in std_logic;
    ---------------------------------------------------------------------------
    mst_wreq_valid                             : out std_logic;
    mst_wreq_len                               : out std_logic_vector(BUS_LEN_WIDTH-1 downto 0);
    mst_wreq_addr                              : out std_logic_vector(BUS_ADDR_WIDTH-1 downto 0);
    mst_wreq_ready                             : in std_logic;
    ---------------------------------------------------------------------------
    mst_wdat_valid                             : out std_logic;
    mst_wdat_ready                             : in std_logic;
    mst_wdat_data                              : out std_logic_vector(BUS_DATA_WIDTH-1 downto 0);
    mst_wdat_strobe                            : out std_logic_vector(BUS_STROBE_WIDTH-1 downto 0);
    mst_wdat_last                              : out std_logic;
    ---------------------------------------------------------------------------
    mst_resp_valid                             : in  std_logic;
    mst_resp_ready                             : out std_logic;
    mst_resp_ok                                : in  std_logic;
    ---------------------------------------------------------------------------
    regs_in                                    : in std_logic_vector(NUM_REGS*REG_WIDTH-1 downto 0);
    regs_out                                   : out std_logic_vector(NUM_REGS*REG_WIDTH-1 downto 0);
    regs_out_en                                : out std_logic_vector(NUM_REGS-1 downto 0);
    ---------------------------------------------------------------------------
    -- Host translate request channel
    htr_req_valid                              : in  std_logic := '0';
    htr_req_ready                              : out std_logic;
    htr_req_addr                               : in  std_logic_vector(BUS_ADDR_WIDTH-1 downto 0) := (others => '0');
    -- Host translate response channel
    htr_resp_valid                             : out std_logic;
    htr_resp_ready                             : in  std_logic := '1';
    htr_resp_virt                              : out std_logic_vector(BUS_ADDR_WIDTH-1 downto 0);
    htr_resp_phys                              : out std_logic_vector(BUS_ADDR_WIDTH-1 downto 0);
    htr_resp_mask                              : out std_logic_vector(BUS_ADDR_WIDTH-1 downto 0)
  );
end fletcher_wrapper;

architecture Implementation of fletcher_wrapper is
  component ReactDelayCounter is
    generic (
      COUNT_WIDTH                 : natural := 32
    );
    port (
      clk                         : in  std_logic;
      reset                       : in  std_logic;

      req_valid                   : in  std_logic;
      req_ready                   : in  std_logic;

      resp_valid                  : in  std_logic;
      resp_ready                  : in  std_logic;

      delay                       : out std_logic_vector(COUNT_WIDTH-1 downto 0)
    );
  end component;

  constant PT_ADDR_INTERM              : unsigned(BUS_ADDR_WIDTH-1 downto 0) := MEM_MAP_BASE;
  constant PT_ADDR                     : unsigned(BUS_ADDR_WIDTH-1 downto 0) := PT_ADDR_INTERM + 2**PT_ENTRIES_LOG2 * ( (PTE_BITS+BYTE_SIZE-1) / BYTE_SIZE);

  constant MM_BENCH_REGS               : natural := 12;
  constant MM_REG_OFFSET_BENCH_RS      : natural := 26;
  constant MM_REG_OFFSET_BENCH_RR      : natural := MM_REG_OFFSET_BENCH_RS + MM_BENCH_REGS;
  constant MM_REG_OFFSET_BENCH_WS      : natural := MM_REG_OFFSET_BENCH_RR + MM_BENCH_REGS;
  constant MM_REG_OFFSET_BENCH_WR      : natural := MM_REG_OFFSET_BENCH_WS + MM_BENCH_REGS;
  constant MM_REG_CMD_DELAY            : natural := MM_REG_OFFSET_BENCH_WR + MM_BENCH_REGS;
  constant MM_REG_DEBUG                : natural := MM_REG_CMD_DELAY + 1;

  type bus_req_t is record
    valid             : std_logic;
    ready             : std_logic;
    addr              : std_logic_vector(BUS_ADDR_WIDTH-1 downto 0);
    len               : std_logic_vector(BUS_LEN_WIDTH-1 downto 0);
  end record bus_req_t;

  type translate_t is record
    req               : bus_req_t;
    resp_valid        : std_logic;
    resp_ready        : std_logic;
    resp_data         : std_logic_vector(BUS_ADDR_WIDTH*3-1 downto 0);
    resp_virt         : std_logic_vector(BUS_ADDR_WIDTH-1 downto 0);
    resp_phys         : std_logic_vector(BUS_ADDR_WIDTH-1 downto 0);
    resp_mask         : std_logic_vector(BUS_ADDR_WIDTH-1 downto 0);
  end record translate_t;

  type bus_r_t is record
    virt              : bus_req_t;
    phys              : bus_req_t;
    dat_valid         : std_logic;
    dat_ready         : std_logic;
    dat_data          : std_logic_vector(BUS_DATA_WIDTH-1 downto 0);
    dat_last          : std_logic;
  end record bus_r_t;

  type bus_w_t is record
    virt              : bus_req_t;
    phys              : bus_req_t;
    dat_valid         : std_logic;
    dat_ready         : std_logic;
    dat_data          : std_logic_vector(BUS_DATA_WIDTH-1 downto 0);
    dat_strobe        : std_logic_vector(BUS_STROBE_WIDTH-1 downto 0);
    dat_last          : std_logic;
    resp_valid        : std_logic;
    resp_ready        : std_logic;
    resp_ok           : std_logic;
    resp_resp         : std_logic_vector(1 downto 0);
  end record bus_w_t;

  -- MMDirector commands and response between MMHostInterface and MMDirector.
  signal cmd_region   : std_logic_vector(log2ceil(MEM_REGIONS+1)-1 downto 0);
  signal cmd_addr     : std_logic_vector(BUS_ADDR_WIDTH-1 downto 0);
  signal cmd_size     : std_logic_vector(BUS_ADDR_WIDTH-1 downto 0);
  signal cmd_free     : std_logic;
  signal cmd_alloc    : std_logic;
  signal cmd_realloc  : std_logic;
  signal cmd_valid    : std_logic;
  signal cmd_ready    : std_logic;
  signal resp_addr    : std_logic_vector(BUS_ADDR_WIDTH-1 downto 0);
  signal resp_success : std_logic;
  signal resp_valid   : std_logic;
  signal resp_ready   : std_logic;

  -- Request and response between MMU and MMDirector
  signal tr_mmu       : translate_t;

  signal translate    : translate_t;

  signal htr_resp_data : std_logic_vector(BUS_ADDR_WIDTH*3-1 downto 0);

  signal dir_r        : bus_r_t;
  signal dir_w        : bus_w_t;
  signal mmu_r        : bus_r_t;

  signal bench_rs     : bus_r_t;
  signal tr_bench_rs  : translate_t;
  signal bench_rr     : bus_r_t;
  signal tr_bench_rr  : translate_t;
  signal bench_ws     : bus_w_t;
  signal tr_bench_ws  : translate_t;
  signal bench_wr     : bus_w_t;
  signal tr_bench_wr  : translate_t;

begin

  regs_out_en(MM_REG_OFFSET_BENCH_RS + MM_BENCH_REGS - 1 downto MM_REG_OFFSET_BENCH_RS) <= "011000000010";
  bench_rs_inst : BusReadBenchmarker
    generic map (
      BUS_ADDR_WIDTH              => BUS_ADDR_WIDTH,
      BUS_DATA_WIDTH              => BUS_DATA_WIDTH,
      BUS_LEN_WIDTH               => BUS_LEN_WIDTH,
      BUS_MAX_BURST_LENGTH        => BUS_BURST_MAX_LEN,
      PATTERN                     => "SEQUENTIAL"
    )
    port map (
      bcd_clk                     => bcd_clk,
      bcd_reset                   => bcd_reset,

      bus_rreq_valid              => bench_rs.virt.valid,
      bus_rreq_ready              => bench_rs.virt.ready,
      bus_rreq_addr               => bench_rs.virt.addr,
      bus_rreq_len                => bench_rs.virt.len,
      bus_rdat_valid              => bench_rs.dat_valid,
      bus_rdat_ready              => bench_rs.dat_ready,
      bus_rdat_data               => bench_rs.dat_data,
      bus_rdat_last               => bench_rs.dat_last,
      
      -- Control / status registers
      reg_control                 => regs_in (
          (MM_REG_OFFSET_BENCH_RS+1)*REG_WIDTH-1 downto (MM_REG_OFFSET_BENCH_RS+0)*REG_WIDTH),
      reg_status                  => regs_out (
          (MM_REG_OFFSET_BENCH_RS+2)*REG_WIDTH-1 downto (MM_REG_OFFSET_BENCH_RS+1)*REG_WIDTH),

      -- Configuration registers
      
      -- Burst length
      reg_burst_length            => regs_in (
          (MM_REG_OFFSET_BENCH_RS+3)*REG_WIDTH-1 downto (MM_REG_OFFSET_BENCH_RS+2)*REG_WIDTH),
      
      -- Maximum number of bursts
      reg_max_bursts              => regs_in (
          (MM_REG_OFFSET_BENCH_RS+4)*REG_WIDTH-1 downto (MM_REG_OFFSET_BENCH_RS+3)*REG_WIDTH),
      
      -- Base addresse
      reg_base_addr_lo            => regs_in (
          (MM_REG_OFFSET_BENCH_RS+5)*REG_WIDTH-1 downto (MM_REG_OFFSET_BENCH_RS+4)*REG_WIDTH),
      reg_base_addr_hi            => regs_in (
          (MM_REG_OFFSET_BENCH_RS+6)*REG_WIDTH-1 downto (MM_REG_OFFSET_BENCH_RS+5)*REG_WIDTH),
      
      -- Address mask
      reg_addr_mask_lo            => regs_in (
          (MM_REG_OFFSET_BENCH_RS+7)*REG_WIDTH-1 downto (MM_REG_OFFSET_BENCH_RS+6)*REG_WIDTH),
      reg_addr_mask_hi            => regs_in (
          (MM_REG_OFFSET_BENCH_RS+8)*REG_WIDTH-1 downto (MM_REG_OFFSET_BENCH_RS+7)*REG_WIDTH),
      
      -- Number of cycles to absorb a word, set 0 to always accept immediately
      reg_cycles_per_word         => regs_in (
          (MM_REG_OFFSET_BENCH_RS+9)*REG_WIDTH-1 downto (MM_REG_OFFSET_BENCH_RS+8)*REG_WIDTH),

      -- Result registers
      reg_cycles                  => regs_out (
          (MM_REG_OFFSET_BENCH_RS+10)*REG_WIDTH-1 downto (MM_REG_OFFSET_BENCH_RS+9)*REG_WIDTH),
      reg_checksum                => regs_out (
          (MM_REG_OFFSET_BENCH_RS+11)*REG_WIDTH-1 downto (MM_REG_OFFSET_BENCH_RS+10)*REG_WIDTH)
    );

  bench_rs_translator : MMTranslator
  generic map (
    BUS_ADDR_WIDTH              => BUS_ADDR_WIDTH,
    BUS_LEN_WIDTH               => BUS_LEN_WIDTH,
    VM_BASE                     => VM_BASE,
    PT_ENTRIES_LOG2             => PT_ENTRIES_LOG2,
    PAGE_SIZE_LOG2              => PAGE_SIZE_LOG2,
    MAX_OUTSTANDING             => 1,
    CACHE_SIZE                  => 1,
    SLV_SLICES                  => 2,
    MST_SLICES                  => 2
  )
  port map (
    clk                         => bcd_clk,
    reset                       => bcd_reset,

    -- Slave request channel
    slv_req_valid               => bench_rs.virt.valid,
    slv_req_ready               => bench_rs.virt.ready,
    slv_req_addr                => bench_rs.virt.addr,
    slv_req_len                 => bench_rs.virt.len,
    -- Master request channel
    mst_req_valid               => bench_rs.phys.valid,
    mst_req_ready               => bench_rs.phys.ready,
    mst_req_addr                => bench_rs.phys.addr,
    mst_req_len                 => bench_rs.phys.len,

    -- Translate request channel
    req_valid                   => tr_bench_rs.req.valid,
    req_ready                   => tr_bench_rs.req.ready,
    req_addr                    => tr_bench_rs.req.addr,
    -- Translate response channel
    resp_valid                  => tr_bench_rs.resp_valid,
    resp_ready                  => tr_bench_rs.resp_ready,
    resp_virt                   => tr_bench_rs.resp_virt,
    resp_phys                   => tr_bench_rs.resp_phys,
    resp_mask                   => tr_bench_rs.resp_mask
  );

  regs_out_en(MM_REG_OFFSET_BENCH_RR + MM_BENCH_REGS - 1 downto MM_REG_OFFSET_BENCH_RR) <= "011000000010";
  bench_rr_inst : BusReadBenchmarker
    generic map (
      BUS_ADDR_WIDTH              => BUS_ADDR_WIDTH,
      BUS_DATA_WIDTH              => BUS_DATA_WIDTH,
      BUS_LEN_WIDTH               => BUS_LEN_WIDTH,
      BUS_MAX_BURST_LENGTH        => BUS_BURST_MAX_LEN,
      PATTERN                     => "RANDOM"
    )
    port map (
      bcd_clk                     => bcd_clk,
      bcd_reset                   => bcd_reset,

      bus_rreq_valid              => bench_rr.virt.valid,
      bus_rreq_ready              => bench_rr.virt.ready,
      bus_rreq_addr               => bench_rr.virt.addr,
      bus_rreq_len                => bench_rr.virt.len,
      bus_rdat_valid              => bench_rr.dat_valid,
      bus_rdat_ready              => bench_rr.dat_ready,
      bus_rdat_data               => bench_rr.dat_data,
      bus_rdat_last               => bench_rr.dat_last,
      
      -- Control / status registers
      reg_control                 => regs_in (
          (MM_REG_OFFSET_BENCH_RR+1)*REG_WIDTH-1 downto (MM_REG_OFFSET_BENCH_RR+0)*REG_WIDTH),
      reg_status                  => regs_out (
          (MM_REG_OFFSET_BENCH_RR+2)*REG_WIDTH-1 downto (MM_REG_OFFSET_BENCH_RR+1)*REG_WIDTH),

      -- Configuration registers
      
      -- Burst length
      reg_burst_length            => regs_in (
          (MM_REG_OFFSET_BENCH_RR+3)*REG_WIDTH-1 downto (MM_REG_OFFSET_BENCH_RR+2)*REG_WIDTH),
      
      -- Maximum number of bursts
      reg_max_bursts              => regs_in (
          (MM_REG_OFFSET_BENCH_RR+4)*REG_WIDTH-1 downto (MM_REG_OFFSET_BENCH_RR+3)*REG_WIDTH),
      
      -- Base addresse
      reg_base_addr_lo            => regs_in (
          (MM_REG_OFFSET_BENCH_RR+5)*REG_WIDTH-1 downto (MM_REG_OFFSET_BENCH_RR+4)*REG_WIDTH),
      reg_base_addr_hi            => regs_in (
          (MM_REG_OFFSET_BENCH_RR+6)*REG_WIDTH-1 downto (MM_REG_OFFSET_BENCH_RR+5)*REG_WIDTH),
      
      -- Address mask
      reg_addr_mask_lo            => regs_in (
          (MM_REG_OFFSET_BENCH_RR+7)*REG_WIDTH-1 downto (MM_REG_OFFSET_BENCH_RR+6)*REG_WIDTH),
      reg_addr_mask_hi            => regs_in (
          (MM_REG_OFFSET_BENCH_RR+8)*REG_WIDTH-1 downto (MM_REG_OFFSET_BENCH_RR+7)*REG_WIDTH),
      
      -- Number of cycles to absorb a word, set 0 to always accept immediately
      reg_cycles_per_word         => regs_in (
          (MM_REG_OFFSET_BENCH_RR+9)*REG_WIDTH-1 downto (MM_REG_OFFSET_BENCH_RR+8)*REG_WIDTH),

      -- Result registers
      reg_cycles                  => regs_out (
          (MM_REG_OFFSET_BENCH_RR+10)*REG_WIDTH-1 downto (MM_REG_OFFSET_BENCH_RR+9)*REG_WIDTH),
      reg_checksum                => regs_out (
          (MM_REG_OFFSET_BENCH_RR+11)*REG_WIDTH-1 downto (MM_REG_OFFSET_BENCH_RR+10)*REG_WIDTH)
    );

  bench_rr_translator : MMTranslator
  generic map (
    BUS_ADDR_WIDTH              => BUS_ADDR_WIDTH,
    BUS_LEN_WIDTH               => BUS_LEN_WIDTH,
    VM_BASE                     => VM_BASE,
    PT_ENTRIES_LOG2             => PT_ENTRIES_LOG2,
    PAGE_SIZE_LOG2              => PAGE_SIZE_LOG2,
    MAX_OUTSTANDING             => 1,
    CACHE_SIZE                  => 1,
    SLV_SLICES                  => 2,
    MST_SLICES                  => 2
  )
  port map (
    clk                         => bcd_clk,
    reset                       => bcd_reset,

    -- Slave request channel
    slv_req_valid               => bench_rr.virt.valid,
    slv_req_ready               => bench_rr.virt.ready,
    slv_req_addr                => bench_rr.virt.addr,
    slv_req_len                 => bench_rr.virt.len,
    -- Master request channel
    mst_req_valid               => bench_rr.phys.valid,
    mst_req_ready               => bench_rr.phys.ready,
    mst_req_addr                => bench_rr.phys.addr,
    mst_req_len                 => bench_rr.phys.len,

    -- Translate request channel
    req_valid                   => tr_bench_rr.req.valid,
    req_ready                   => tr_bench_rr.req.ready,
    req_addr                    => tr_bench_rr.req.addr,
    -- Translate response channel
    resp_valid                  => tr_bench_rr.resp_valid,
    resp_ready                  => tr_bench_rr.resp_ready,
    resp_virt                   => tr_bench_rr.resp_virt,
    resp_phys                   => tr_bench_rr.resp_phys,
    resp_mask                   => tr_bench_rr.resp_mask
  );

  regs_out_en(MM_REG_OFFSET_BENCH_WS + MM_BENCH_REGS - 1 downto MM_REG_OFFSET_BENCH_WS) <= "011000000010";
  bench_ws_inst : BusWriteBenchmarker
    generic map (
      BUS_ADDR_WIDTH              => BUS_ADDR_WIDTH,
      BUS_DATA_WIDTH              => BUS_DATA_WIDTH,
      BUS_LEN_WIDTH               => BUS_LEN_WIDTH,
      BUS_MAX_BURST_LENGTH        => BUS_BURST_MAX_LEN,
      PATTERN                     => "SEQUENTIAL"
    )
    port map (
      bcd_clk                     => bcd_clk,
      bcd_reset                   => bcd_reset,

      bus_wreq_valid              => bench_ws.virt.valid,
      bus_wreq_ready              => bench_ws.virt.ready,
      bus_wreq_addr               => bench_ws.virt.addr,
      bus_wreq_len                => bench_ws.virt.len,
      bus_wdat_valid              => bench_ws.dat_valid,
      bus_wdat_ready              => bench_ws.dat_ready,
      bus_wdat_data               => bench_ws.dat_data,
      bus_wdat_last               => bench_ws.dat_last,
      
      -- Control / status registers
      reg_control                 => regs_in (
          (MM_REG_OFFSET_BENCH_WS+1)*REG_WIDTH-1 downto (MM_REG_OFFSET_BENCH_WS+0)*REG_WIDTH),
      reg_status                  => regs_out (
          (MM_REG_OFFSET_BENCH_WS+2)*REG_WIDTH-1 downto (MM_REG_OFFSET_BENCH_WS+1)*REG_WIDTH),

      -- Configuration registers
      
      -- Burst length
      reg_burst_length            => regs_in (
          (MM_REG_OFFSET_BENCH_WS+3)*REG_WIDTH-1 downto (MM_REG_OFFSET_BENCH_WS+2)*REG_WIDTH),
      
      -- Maximum number of bursts
      reg_max_bursts              => regs_in (
          (MM_REG_OFFSET_BENCH_WS+4)*REG_WIDTH-1 downto (MM_REG_OFFSET_BENCH_WS+3)*REG_WIDTH),
      
      -- Base addresse
      reg_base_addr_lo            => regs_in (
          (MM_REG_OFFSET_BENCH_WS+5)*REG_WIDTH-1 downto (MM_REG_OFFSET_BENCH_WS+4)*REG_WIDTH),
      reg_base_addr_hi            => regs_in (
          (MM_REG_OFFSET_BENCH_WS+6)*REG_WIDTH-1 downto (MM_REG_OFFSET_BENCH_WS+5)*REG_WIDTH),
      
      -- Address mask
      reg_addr_mask_lo            => regs_in (
          (MM_REG_OFFSET_BENCH_WS+7)*REG_WIDTH-1 downto (MM_REG_OFFSET_BENCH_WS+6)*REG_WIDTH),
      reg_addr_mask_hi            => regs_in (
          (MM_REG_OFFSET_BENCH_WS+8)*REG_WIDTH-1 downto (MM_REG_OFFSET_BENCH_WS+7)*REG_WIDTH),
      
      -- Number of cycles to absorb a word, set 0 to always accept immediately
      reg_cycles_per_word         => regs_in (
          (MM_REG_OFFSET_BENCH_WS+9)*REG_WIDTH-1 downto (MM_REG_OFFSET_BENCH_WS+8)*REG_WIDTH),

      -- Result registers
      reg_cycles                  => regs_out (
          (MM_REG_OFFSET_BENCH_WS+10)*REG_WIDTH-1 downto (MM_REG_OFFSET_BENCH_WS+9)*REG_WIDTH),
      reg_checksum                => regs_out (
          (MM_REG_OFFSET_BENCH_WS+11)*REG_WIDTH-1 downto (MM_REG_OFFSET_BENCH_WS+10)*REG_WIDTH)
    );

  bench_ws_translator : MMTranslator
  generic map (
    BUS_ADDR_WIDTH              => BUS_ADDR_WIDTH,
    BUS_LEN_WIDTH               => BUS_LEN_WIDTH,
    VM_BASE                     => VM_BASE,
    PT_ENTRIES_LOG2             => PT_ENTRIES_LOG2,
    PAGE_SIZE_LOG2              => PAGE_SIZE_LOG2,
    MAX_OUTSTANDING             => 1,
    CACHE_SIZE                  => 1,
    SLV_SLICES                  => 2,
    MST_SLICES                  => 2
  )
  port map (
    clk                         => bcd_clk,
    reset                       => bcd_reset,

    -- Slave request channel
    slv_req_valid               => bench_ws.virt.valid,
    slv_req_ready               => bench_ws.virt.ready,
    slv_req_addr                => bench_ws.virt.addr,
    slv_req_len                 => bench_ws.virt.len,
    -- Master request channel
    mst_req_valid               => bench_ws.phys.valid,
    mst_req_ready               => bench_ws.phys.ready,
    mst_req_addr                => bench_ws.phys.addr,
    mst_req_len                 => bench_ws.phys.len,

    -- Translate request channel
    req_valid                   => tr_bench_ws.req.valid,
    req_ready                   => tr_bench_ws.req.ready,
    req_addr                    => tr_bench_ws.req.addr,
    -- Translate response channel
    resp_valid                  => tr_bench_ws.resp_valid,
    resp_ready                  => tr_bench_ws.resp_ready,
    resp_virt                   => tr_bench_ws.resp_virt,
    resp_phys                   => tr_bench_ws.resp_phys,
    resp_mask                   => tr_bench_ws.resp_mask
  );

  regs_out_en(MM_REG_OFFSET_BENCH_WR + MM_BENCH_REGS - 1 downto MM_REG_OFFSET_BENCH_WR) <= "011000000010";
  bench_wr_inst : BusWriteBenchmarker
    generic map (
      BUS_ADDR_WIDTH              => BUS_ADDR_WIDTH,
      BUS_DATA_WIDTH              => BUS_DATA_WIDTH,
      BUS_LEN_WIDTH               => BUS_LEN_WIDTH,
      BUS_MAX_BURST_LENGTH        => BUS_BURST_MAX_LEN,
      PATTERN                     => "RANDOM"
    )
    port map (
      bcd_clk                     => bcd_clk,
      bcd_reset                   => bcd_reset,

      bus_wreq_valid              => bench_wr.virt.valid,
      bus_wreq_ready              => bench_wr.virt.ready,
      bus_wreq_addr               => bench_wr.virt.addr,
      bus_wreq_len                => bench_wr.virt.len,
      bus_wdat_valid              => bench_wr.dat_valid,
      bus_wdat_ready              => bench_wr.dat_ready,
      bus_wdat_data               => bench_wr.dat_data,
      bus_wdat_last               => bench_wr.dat_last,
      
      -- Control / status registers
      reg_control                 => regs_in (
          (MM_REG_OFFSET_BENCH_WR+1)*REG_WIDTH-1 downto (MM_REG_OFFSET_BENCH_WR+0)*REG_WIDTH),
      reg_status                  => regs_out (
          (MM_REG_OFFSET_BENCH_WR+2)*REG_WIDTH-1 downto (MM_REG_OFFSET_BENCH_WR+1)*REG_WIDTH),

      -- Configuration registers
      
      -- Burst length
      reg_burst_length            => regs_in (
          (MM_REG_OFFSET_BENCH_WR+3)*REG_WIDTH-1 downto (MM_REG_OFFSET_BENCH_WR+2)*REG_WIDTH),
      
      -- Maximum number of bursts
      reg_max_bursts              => regs_in (
          (MM_REG_OFFSET_BENCH_WR+4)*REG_WIDTH-1 downto (MM_REG_OFFSET_BENCH_WR+3)*REG_WIDTH),
      
      -- Base addresse
      reg_base_addr_lo            => regs_in (
          (MM_REG_OFFSET_BENCH_WR+5)*REG_WIDTH-1 downto (MM_REG_OFFSET_BENCH_WR+4)*REG_WIDTH),
      reg_base_addr_hi            => regs_in (
          (MM_REG_OFFSET_BENCH_WR+6)*REG_WIDTH-1 downto (MM_REG_OFFSET_BENCH_WR+5)*REG_WIDTH),
      
      -- Address mask
      reg_addr_mask_lo            => regs_in (
          (MM_REG_OFFSET_BENCH_WR+7)*REG_WIDTH-1 downto (MM_REG_OFFSET_BENCH_WR+6)*REG_WIDTH),
      reg_addr_mask_hi            => regs_in (
          (MM_REG_OFFSET_BENCH_WR+8)*REG_WIDTH-1 downto (MM_REG_OFFSET_BENCH_WR+7)*REG_WIDTH),
      
      -- Number of cycles to absorb a word, set 0 to always accept immediately
      reg_cycles_per_word         => regs_in (
          (MM_REG_OFFSET_BENCH_WR+9)*REG_WIDTH-1 downto (MM_REG_OFFSET_BENCH_WR+8)*REG_WIDTH),

      -- Result registers
      reg_cycles                  => regs_out (
          (MM_REG_OFFSET_BENCH_WR+10)*REG_WIDTH-1 downto (MM_REG_OFFSET_BENCH_WR+9)*REG_WIDTH),
      reg_checksum                => regs_out (
          (MM_REG_OFFSET_BENCH_WR+11)*REG_WIDTH-1 downto (MM_REG_OFFSET_BENCH_WR+10)*REG_WIDTH)
    );

  bench_wr_translator : MMTranslator
  generic map (
    BUS_ADDR_WIDTH              => BUS_ADDR_WIDTH,
    BUS_LEN_WIDTH               => BUS_LEN_WIDTH,
    VM_BASE                     => VM_BASE,
    PT_ENTRIES_LOG2             => PT_ENTRIES_LOG2,
    PAGE_SIZE_LOG2              => PAGE_SIZE_LOG2,
    MAX_OUTSTANDING             => 1,
    CACHE_SIZE                  => 1,
    SLV_SLICES                  => 2,
    MST_SLICES                  => 2
  )
  port map (
    clk                         => bcd_clk,
    reset                       => bcd_reset,

    -- Slave request channel
    slv_req_valid               => bench_wr.virt.valid,
    slv_req_ready               => bench_wr.virt.ready,
    slv_req_addr                => bench_wr.virt.addr,
    slv_req_len                 => bench_wr.virt.len,
    -- Master request channel
    mst_req_valid               => bench_wr.phys.valid,
    mst_req_ready               => bench_wr.phys.ready,
    mst_req_addr                => bench_wr.phys.addr,
    mst_req_len                 => bench_wr.phys.len,

    -- Translate request channel
    req_valid                   => tr_bench_wr.req.valid,
    req_ready                   => tr_bench_wr.req.ready,
    req_addr                    => tr_bench_wr.req.addr,
    -- Translate response channel
    resp_valid                  => tr_bench_wr.resp_valid,
    resp_ready                  => tr_bench_wr.resp_ready,
    resp_virt                   => tr_bench_wr.resp_virt,
    resp_phys                   => tr_bench_wr.resp_phys,
    resp_mask                   => tr_bench_wr.resp_mask
  );

  mm_dir_inst : MMDirector
    generic map (
      PAGE_SIZE_LOG2              => PAGE_SIZE_LOG2,
      MEM_REGIONS                 => MEM_REGIONS,
      MEM_SIZES                   => MEM_SIZES,
      MEM_MAP_BASE                => MEM_MAP_BASE,
      MEM_MAP_SIZE_LOG2           => MEM_MAP_SIZE_LOG2,
      VM_BASE                     => VM_BASE,
      PT_ADDR                     => PT_ADDR,
      PT_ENTRIES_LOG2             => PT_ENTRIES_LOG2,
      PTE_BITS                    => PTE_BITS,
      BUS_ADDR_WIDTH              => BUS_ADDR_WIDTH,
      BUS_LEN_WIDTH               => BUS_LEN_WIDTH,
      BUS_DATA_WIDTH              => BUS_DATA_WIDTH,
      BUS_STROBE_WIDTH            => BUS_STROBE_WIDTH,
      BUS_BURST_STEP_LEN          => BUS_BURST_STEP_LEN,
      BUS_BURST_MAX_LEN           => BUS_BURST_MAX_LEN
    )
    port map (
      clk                         => bcd_clk,
      reset                       => bcd_reset,
      cmd_region                  => cmd_region,
      cmd_addr                    => cmd_addr,
      cmd_size                    => cmd_size,
      cmd_free                    => cmd_free,
      cmd_alloc                   => cmd_alloc,
      cmd_realloc                 => cmd_realloc,
      cmd_valid                   => cmd_valid,
      cmd_ready                   => cmd_ready,

      resp_addr                   => resp_addr,
      resp_success                => resp_success,
      resp_valid                  => resp_valid,
      resp_ready                  => resp_ready,

      mmu_req_valid               => tr_mmu.req.valid,
      mmu_req_ready               => tr_mmu.req.ready,
      mmu_req_addr                => tr_mmu.req.addr,

      mmu_resp_valid              => tr_mmu.resp_valid,
      mmu_resp_ready              => tr_mmu.resp_ready,
      mmu_resp_addr               => tr_mmu.resp_phys,

      bus_wreq_valid              => dir_w.phys.valid,
      bus_wreq_ready              => dir_w.phys.ready,
      bus_wreq_addr               => dir_w.phys.addr,
      bus_wreq_len                => dir_w.phys.len,
      bus_wdat_valid              => dir_w.dat_valid,
      bus_wdat_ready              => dir_w.dat_ready,
      bus_wdat_data               => dir_w.dat_data,
      bus_wdat_strobe             => dir_w.dat_strobe,
      bus_wdat_last               => dir_w.dat_last,

      bus_rreq_valid              => dir_r.phys.valid,
      bus_rreq_ready              => dir_r.phys.ready,
      bus_rreq_addr               => dir_r.phys.addr,
      bus_rreq_len                => dir_r.phys.len,
      bus_rdat_valid              => dir_r.dat_valid,
      bus_rdat_ready              => dir_r.dat_ready,
      bus_rdat_data               => dir_r.dat_data,
      bus_rdat_last               => dir_r.dat_last,
      
      bus_resp_valid              => dir_w.resp_valid,
      bus_resp_ready              => dir_w.resp_ready,
      bus_resp_ok                 => dir_w.resp_ok,
      debug_state                 => regs_out((MM_REG_DEBUG+1)*REG_WIDTH-1 downto MM_REG_DEBUG*REG_WIDTH)
    );
  regs_out_en(MM_REG_DEBUG) <= '1';

  mm_hif_delay_cntr_inst : ReactDelayCounter
    generic map (
      COUNT_WIDTH                 => 32
    )
    port map (
      clk                         => bcd_clk,
      reset                       => bcd_reset,
      req_valid                   => cmd_valid,
      req_ready                   => cmd_ready,
      resp_valid                  => resp_valid,
      resp_ready                  => resp_ready,
      delay                       => regs_out((MM_REG_CMD_DELAY+1)*REG_WIDTH-1 downto MM_REG_CMD_DELAY*REG_WIDTH)
    );
  regs_out_en(MM_REG_CMD_DELAY)   <= '1';

  mm_hif_inst : MMHostInterface
    generic map (
      MEM_REGIONS                 => MEM_REGIONS
    )
    port map (
      clk                         => bcd_clk,
      reset                       => bcd_reset,
      cmd_region                  => cmd_region,
      cmd_addr                    => cmd_addr,
      cmd_size                    => cmd_size,
      cmd_free                    => cmd_free,
      cmd_alloc                   => cmd_alloc,
      cmd_realloc                 => cmd_realloc,
      cmd_valid                   => cmd_valid,
      cmd_ready                   => cmd_ready,

      resp_addr                   => resp_addr,
      resp_success                => resp_success,
      resp_valid                  => resp_valid,
      resp_ready                  => resp_ready,

      regs_in                     => regs_in ((MM_H2D_REG_OFFSET+9)*REG_WIDTH-1 downto MM_H2D_REG_OFFSET*REG_WIDTH),
      regs_out                    => regs_out((MM_H2D_REG_OFFSET+9)*REG_WIDTH-1 downto MM_H2D_REG_OFFSET*REG_WIDTH),
      regs_out_en                 => regs_out_en(MM_H2D_REG_OFFSET+9-1 downto MM_H2D_REG_OFFSET)
    );

  mmu_inst : MMWalker
    generic map (
      PAGE_SIZE_LOG2              => PAGE_SIZE_LOG2,
      PT_ADDR                     => PT_ADDR,
      PT_ENTRIES_LOG2             => PT_ENTRIES_LOG2,
      PTE_BITS                    => PTE_BITS,
--      MAX_OUTSTANDING_BUS         => 1,
      MAX_OUTSTANDING_BUS         => 64,
      ---------------------------------------------------------------------------
      -- Bus metrics and configuration
      ---------------------------------------------------------------------------
      BUS_ADDR_WIDTH              => BUS_ADDR_WIDTH,
      BUS_LEN_WIDTH               => BUS_LEN_WIDTH,
      BUS_DATA_WIDTH              => BUS_DATA_WIDTH,
      BUS_STROBE_WIDTH            => BUS_STROBE_WIDTH,
      BUS_BURST_STEP_LEN          => BUS_BURST_STEP_LEN,
      BUS_BURST_MAX_LEN           => BUS_BURST_MAX_LEN
    )
    port map (
      clk                         => bcd_clk,
      reset                       => bcd_reset,

      -- Read address channel
      bus_rreq_addr               => mmu_r.phys.addr,
      bus_rreq_len                => mmu_r.phys.len,
      bus_rreq_valid              => mmu_r.phys.valid,
      bus_rreq_ready              => mmu_r.phys.ready,

      -- Read data channel
      bus_rdat_data               => mmu_r.dat_data,
      bus_rdat_last               => mmu_r.dat_last,
      bus_rdat_valid              => mmu_r.dat_valid,
      bus_rdat_ready              => mmu_r.dat_ready,

      -- Translate request channel
      req_valid                   => translate.req.valid,
      req_ready                   => translate.req.ready,
      req_addr                    => translate.req.addr,
      -- Translate response channel
      resp_valid                  => translate.resp_valid,
      resp_ready                  => translate.resp_ready,
      resp_virt                   => translate.resp_virt,
      resp_phys                   => translate.resp_phys,
      resp_mask                   => translate.resp_mask,

      dir_req_valid               => tr_mmu.req.valid,
      dir_req_ready               => tr_mmu.req.ready,
      dir_req_addr                => tr_mmu.req.addr,

      dir_resp_valid              => tr_mmu.resp_valid,
      dir_resp_ready              => tr_mmu.resp_ready,
      dir_resp_addr               => tr_mmu.resp_phys
    );

  tr_req_arb_inst : BusReadArbiter
  generic map (
    BUS_ADDR_WIDTH              => BUS_ADDR_WIDTH,
    BUS_LEN_WIDTH               => 1,
    BUS_DATA_WIDTH              => BUS_ADDR_WIDTH * 3,
    NUM_SLAVE_PORTS             => 5,
    ARB_METHOD                  => "ROUND-ROBIN",
    MAX_OUTSTANDING             => 1,
    SLV_REQ_SLICES              => true,
    MST_REQ_SLICE               => true,
    MST_DAT_SLICE               => true,
    SLV_DAT_SLICES              => true
  )
  port map (
    bcd_clk                     => bcd_clk,
    bcd_reset                   => bcd_reset,

    mst_rreq_valid              => translate.req.valid,
    mst_rreq_ready              => translate.req.ready,
    mst_rreq_addr               => translate.req.addr,
    mst_rdat_valid              => translate.resp_valid,
    mst_rdat_ready              => translate.resp_ready,
    mst_rdat_data               => translate.resp_data,
    mst_rdat_last               => '1',

    bs00_rreq_valid             => htr_req_valid,
    bs00_rreq_ready             => htr_req_ready,
    bs00_rreq_addr              => htr_req_addr,
    bs00_rreq_len               => "1",
    bs00_rdat_valid             => htr_resp_valid,
    bs00_rdat_ready             => htr_resp_ready,
    bs00_rdat_data              => htr_resp_data,

    bs01_rreq_valid             => tr_bench_rs.req.valid,
    bs01_rreq_ready             => tr_bench_rs.req.ready,
    bs01_rreq_addr              => tr_bench_rs.req.addr,
    bs01_rreq_len               => "1",
    bs01_rdat_valid             => tr_bench_rs.resp_valid,
    bs01_rdat_ready             => tr_bench_rs.resp_ready,
    bs01_rdat_data              => tr_bench_rs.resp_data,

    bs02_rreq_valid             => tr_bench_rr.req.valid,
    bs02_rreq_ready             => tr_bench_rr.req.ready,
    bs02_rreq_addr              => tr_bench_rr.req.addr,
    bs02_rreq_len               => "1",
    bs02_rdat_valid             => tr_bench_rr.resp_valid,
    bs02_rdat_ready             => tr_bench_rr.resp_ready,
    bs02_rdat_data              => tr_bench_rr.resp_data,

    bs03_rreq_valid             => tr_bench_ws.req.valid,
    bs03_rreq_ready             => tr_bench_ws.req.ready,
    bs03_rreq_addr              => tr_bench_ws.req.addr,
    bs03_rreq_len               => "1",
    bs03_rdat_valid             => tr_bench_ws.resp_valid,
    bs03_rdat_ready             => tr_bench_ws.resp_ready,
    bs03_rdat_data              => tr_bench_ws.resp_data,

    bs04_rreq_valid             => tr_bench_wr.req.valid,
    bs04_rreq_ready             => tr_bench_wr.req.ready,
    bs04_rreq_addr              => tr_bench_wr.req.addr,
    bs04_rreq_len               => "1",
    bs04_rdat_valid             => tr_bench_wr.resp_valid,
    bs04_rdat_ready             => tr_bench_wr.resp_ready,
    bs04_rdat_data              => tr_bench_wr.resp_data
  );

  translate.resp_data   <= translate.resp_virt & translate.resp_phys & translate.resp_mask;

  htr_resp_virt         <= EXTRACT(htr_resp_data, BUS_ADDR_WIDTH*2, BUS_ADDR_WIDTH);
  htr_resp_phys         <= EXTRACT(htr_resp_data, BUS_ADDR_WIDTH*1, BUS_ADDR_WIDTH);
  htr_resp_mask         <= EXTRACT(htr_resp_data, BUS_ADDR_WIDTH*0, BUS_ADDR_WIDTH);

  tr_bench_rs.resp_virt <= EXTRACT(tr_bench_rs.resp_data, BUS_ADDR_WIDTH*2, BUS_ADDR_WIDTH);
  tr_bench_rs.resp_phys <= EXTRACT(tr_bench_rs.resp_data, BUS_ADDR_WIDTH*1, BUS_ADDR_WIDTH);
  tr_bench_rs.resp_mask <= EXTRACT(tr_bench_rs.resp_data, BUS_ADDR_WIDTH*0, BUS_ADDR_WIDTH);

  tr_bench_rr.resp_virt <= EXTRACT(tr_bench_rr.resp_data, BUS_ADDR_WIDTH*2, BUS_ADDR_WIDTH);
  tr_bench_rr.resp_phys <= EXTRACT(tr_bench_rr.resp_data, BUS_ADDR_WIDTH*1, BUS_ADDR_WIDTH);
  tr_bench_rr.resp_mask <= EXTRACT(tr_bench_rr.resp_data, BUS_ADDR_WIDTH*0, BUS_ADDR_WIDTH);

  tr_bench_ws.resp_virt <= EXTRACT(tr_bench_ws.resp_data, BUS_ADDR_WIDTH*2, BUS_ADDR_WIDTH);
  tr_bench_ws.resp_phys <= EXTRACT(tr_bench_ws.resp_data, BUS_ADDR_WIDTH*1, BUS_ADDR_WIDTH);
  tr_bench_ws.resp_mask <= EXTRACT(tr_bench_ws.resp_data, BUS_ADDR_WIDTH*0, BUS_ADDR_WIDTH);

  tr_bench_wr.resp_virt <= EXTRACT(tr_bench_wr.resp_data, BUS_ADDR_WIDTH*2, BUS_ADDR_WIDTH);
  tr_bench_wr.resp_phys <= EXTRACT(tr_bench_wr.resp_data, BUS_ADDR_WIDTH*1, BUS_ADDR_WIDTH);
  tr_bench_wr.resp_mask <= EXTRACT(tr_bench_wr.resp_data, BUS_ADDR_WIDTH*0, BUS_ADDR_WIDTH);


  bus_read_arb_inst : BusReadArbiter
    generic map (
      BUS_ADDR_WIDTH            => BUS_ADDR_WIDTH,
      BUS_LEN_WIDTH             => BUS_LEN_WIDTH,
      BUS_DATA_WIDTH            => BUS_DATA_WIDTH,
      NUM_SLAVE_PORTS           => 4,
      ARB_METHOD                => "FIXED",
      MAX_OUTSTANDING           => 32,
      SLV_REQ_SLICES            => true,
      MST_REQ_SLICE             => true,
      MST_DAT_SLICE             => true,
      SLV_DAT_SLICES            => true
    )
    port map (
      bcd_clk                   => bcd_clk,
      bcd_reset                 => bcd_reset,

      mst_rreq_valid            => mst_rreq_valid,
      mst_rreq_ready            => mst_rreq_ready,
      mst_rreq_addr             => mst_rreq_addr,
      mst_rreq_len              => mst_rreq_len,
      mst_rdat_valid            => mst_rdat_valid,
      mst_rdat_ready            => mst_rdat_ready,
      mst_rdat_data             => mst_rdat_data,
      mst_rdat_last             => mst_rdat_last,

      bs00_rreq_valid           => mmu_r.phys.valid,
      bs00_rreq_ready           => mmu_r.phys.ready,
      bs00_rreq_addr            => mmu_r.phys.addr,
      bs00_rreq_len             => mmu_r.phys.len,
      bs00_rdat_valid           => mmu_r.dat_valid,
      bs00_rdat_ready           => mmu_r.dat_ready,
      bs00_rdat_data            => mmu_r.dat_data,
      bs00_rdat_last            => mmu_r.dat_last,

      bs01_rreq_valid           => dir_r.phys.valid,
      bs01_rreq_ready           => dir_r.phys.ready,
      bs01_rreq_addr            => dir_r.phys.addr,
      bs01_rreq_len             => dir_r.phys.len,
      bs01_rdat_valid           => dir_r.dat_valid,
      bs01_rdat_ready           => dir_r.dat_ready,
      bs01_rdat_data            => dir_r.dat_data,
      bs01_rdat_last            => dir_r.dat_last,

      bs02_rreq_valid           => bench_rs.phys.valid,
      bs02_rreq_ready           => bench_rs.phys.ready,
      bs02_rreq_addr            => bench_rs.phys.addr,
      bs02_rreq_len             => bench_rs.phys.len,
      bs02_rdat_valid           => bench_rs.dat_valid,
      bs02_rdat_ready           => bench_rs.dat_ready,
      bs02_rdat_data            => bench_rs.dat_data,
      bs02_rdat_last            => bench_rs.dat_last,

      bs03_rreq_valid           => bench_rr.phys.valid,
      bs03_rreq_ready           => bench_rr.phys.ready,
      bs03_rreq_addr            => bench_rr.phys.addr,
      bs03_rreq_len             => bench_rr.phys.len,
      bs03_rdat_valid           => bench_rr.dat_valid,
      bs03_rdat_ready           => bench_rr.dat_ready,
      bs03_rdat_data            => bench_rr.dat_data,
      bs03_rdat_last            => bench_rr.dat_last
    );

  bus_write_arb_inst : BusWriteArbiter
    generic map (
      BUS_ADDR_WIDTH            => BUS_ADDR_WIDTH,
      BUS_LEN_WIDTH             => BUS_LEN_WIDTH,
      BUS_DATA_WIDTH            => BUS_DATA_WIDTH,
      BUS_STROBE_WIDTH          => BUS_STROBE_WIDTH,
      NUM_SLAVE_PORTS           => 1,
      ARB_METHOD                => "FIXED",
      MAX_DATA_LAG              => 4,
      MAX_OUTSTANDING           => 32,
      SLV_REQ_SLICES            => true,
      MST_REQ_SLICE             => true,
      MST_DAT_SLICE             => true,
      SLV_DAT_SLICES            => true,
      MST_RSP_SLICE             => true,
      SLV_RSP_SLICES            => true
    )
    port map (
      bcd_clk                   => bcd_clk,
      bcd_reset                 => bcd_reset,

      mst_wreq_valid            => mst_wreq_valid,
      mst_wreq_ready            => mst_wreq_ready,
      mst_wreq_addr             => mst_wreq_addr,
      mst_wreq_len              => mst_wreq_len,
      mst_wdat_valid            => mst_wdat_valid,
      mst_wdat_ready            => mst_wdat_ready,
      mst_wdat_data             => mst_wdat_data,
      mst_wdat_strobe           => mst_wdat_strobe,
      mst_wdat_last             => mst_wdat_last,
      mst_resp_valid            => mst_resp_valid,
      mst_resp_ready            => mst_resp_ready,
      mst_resp_ok               => mst_resp_ok,

      bs00_wreq_valid           => dir_w.phys.valid,
      bs00_wreq_ready           => dir_w.phys.ready,
      bs00_wreq_addr            => dir_w.phys.addr,
      bs00_wreq_len             => dir_w.phys.len,
      bs00_wdat_valid           => dir_w.dat_valid,
      bs00_wdat_ready           => dir_w.dat_ready,
      bs00_wdat_data            => dir_w.dat_data,
      bs00_wdat_strobe          => dir_w.dat_strobe,
      bs00_wdat_last            => dir_w.dat_last,
      bs00_resp_valid           => dir_w.resp_valid,
      bs00_resp_ready           => dir_w.resp_ready,
      bs00_resp_ok              => dir_w.resp_ok,

      bs01_wreq_valid           => bench_ws.phys.valid,
      bs01_wreq_ready           => bench_ws.phys.ready,
      bs01_wreq_addr            => bench_ws.phys.addr,
      bs01_wreq_len             => bench_ws.phys.len,
      bs01_wdat_valid           => bench_ws.dat_valid,
      bs01_wdat_ready           => bench_ws.dat_ready,
      bs01_wdat_data            => bench_ws.dat_data,
      bs01_wdat_strobe          => bench_ws.dat_strobe,
      bs01_wdat_last            => bench_ws.dat_last,

      bs02_wreq_valid           => bench_wr.phys.valid,
      bs02_wreq_ready           => bench_wr.phys.ready,
      bs02_wreq_addr            => bench_wr.phys.addr,
      bs02_wreq_len             => bench_wr.phys.len,
      bs02_wdat_valid           => bench_wr.dat_valid,
      bs02_wdat_ready           => bench_wr.dat_ready,
      bs02_wdat_data            => bench_wr.dat_data,
      bs02_wdat_strobe          => bench_wr.dat_strobe,
      bs02_wdat_last            => bench_wr.dat_last
    );

end architecture;

