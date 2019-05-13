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
use work.Interconnect.all;
use work.Wrapper.all;
use work.Utils.all;
use work.MM.all;

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
    acc_reset                                  : in std_logic;
    bus_clk                                    : in std_logic;
    bus_reset                                  : in std_logic;
    acc_clk                                    : in std_logic;
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
  constant PT_ADDR_INTERM              : unsigned(BUS_ADDR_WIDTH-1 downto 0) := MEM_MAP_BASE;
  constant PT_ADDR                     : unsigned(BUS_ADDR_WIDTH-1 downto 0) := PT_ADDR_INTERM + 2**PT_ENTRIES_LOG2 * ( (PTE_BITS+BYTE_SIZE-1) / BYTE_SIZE);

  constant MM_BENCH_REGS               : natural := 12;
  constant MM_REG_OFFSET_BENCH_RS      : natural := 26;
  constant MM_REG_OFFSET_BENCH_RR      : natural := MM_REG_OFFSET_BENCH_RS + MM_BENCH_REGS;


  type bus_r_t is record
    req_valid         : std_logic;
    req_ready         : std_logic;
    req_addr          : std_logic_vector(BUS_ADDR_WIDTH-1 downto 0);
    req_len           : std_logic_vector(BUS_LEN_WIDTH-1 downto 0);
    req_size          : std_logic_vector(2 downto 0);
    dat_valid         : std_logic;
    dat_ready         : std_logic;
    dat_data          : std_logic_vector(BUS_DATA_WIDTH-1 downto 0);
    dat_last          : std_logic;
  end record bus_r_t;

  type bus_w_t is record
    req_valid         : std_logic;
    req_ready         : std_logic;
    req_addr          : std_logic_vector(BUS_ADDR_WIDTH-1 downto 0);
    req_len           : std_logic_vector(BUS_LEN_WIDTH-1 downto 0);
    req_size          : std_logic_vector(2 downto 0);
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

  -- Translate request channel
  signal tr_req_valid              : std_logic;
  signal tr_req_ready              : std_logic;
  signal tr_req_addr               : std_logic_vector(BUS_ADDR_WIDTH-1 downto 0);
  -- Translate response channel
  signal tr_rsp_valid              : std_logic;
  signal tr_rsp_ready              : std_logic;
  signal tr_rsp_virt               : std_logic_vector(BUS_ADDR_WIDTH-1 downto 0);
  signal tr_rsp_phys               : std_logic_vector(BUS_ADDR_WIDTH-1 downto 0);
  signal tr_rsp_mask               : std_logic_vector(BUS_ADDR_WIDTH-1 downto 0);

  signal mmu_req_valid          : std_logic;
  signal mmu_req_ready          : std_logic;
  signal mmu_req_addr           : std_logic_vector(BUS_ADDR_WIDTH-1 downto 0);

  signal mmu_resp_valid         : std_logic;
  signal mmu_resp_ready         : std_logic;
  signal mmu_resp_addr          : std_logic_vector(BUS_ADDR_WIDTH-1 downto 0);

  signal dir_r                  : bus_r_t;
  signal dir_w                  : bus_w_t;
  signal mmu_r                  : bus_r_t;
  signal bench_sr               : bus_r_t;

begin

  regs_out_en(MM_REG_OFFSET_BENCH_RS + MM_BENCH_REGS - 1 downto MM_REG_OFFSET_BENCH_RS) <= "011000000010";
  bench_rs : BusReadBenchmarker
    generic map (
      BUS_ADDR_WIDTH              => BUS_ADDR_WIDTH,
      BUS_DATA_WIDTH              => BUS_DATA_WIDTH,
      BUS_LEN_WIDTH               => BUS_LEN_WIDTH,
      BUS_MAX_BURST_LENGTH        => BUS_BURST_MAX_LEN,
      PATTERN                     => "SEQUENTIAL"
    )
    port map (
      bus_clk                     => bus_clk,
      bus_reset                   => bus_reset,

      bus_rreq_valid              => bench_sr.req_valid,
      bus_rreq_ready              => bench_sr.req_ready,
      bus_rreq_addr               => bench_sr.req_addr,
      bus_rreq_len                => bench_sr.req_len,
      bus_rdat_valid              => bench_sr.dat_valid,
      bus_rdat_ready              => bench_sr.dat_ready,
      bus_rdat_data               => bench_sr.dat_data,
      bus_rdat_last               => bench_sr.dat_last,
      
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

  regs_out_en(MM_REG_OFFSET_BENCH_RR + MM_BENCH_REGS - 1 downto MM_REG_OFFSET_BENCH_RR) <= "011000000010";
  bench_rs : BusReadBenchmarker
    generic map (
      BUS_ADDR_WIDTH              => BUS_ADDR_WIDTH,
      BUS_DATA_WIDTH              => BUS_DATA_WIDTH,
      BUS_LEN_WIDTH               => BUS_LEN_WIDTH,
      BUS_MAX_BURST_LENGTH        => BUS_BURST_MAX_LEN,
      PATTERN                     => "RANDOM"
    )
    port map (
      bus_clk                     => bus_clk,
      bus_reset                   => bus_reset,

      bus_rreq_valid              => bench_sr.req_valid,
      bus_rreq_ready              => bench_sr.req_ready,
      bus_rreq_addr               => bench_sr.req_addr,
      bus_rreq_len                => bench_sr.req_len,
      bus_rdat_valid              => bench_sr.dat_valid,
      bus_rdat_ready              => bench_sr.dat_ready,
      bus_rdat_data               => bench_sr.dat_data,
      bus_rdat_last               => bench_sr.dat_last,
      
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
      PTE_BITS                    => PTE_BITS
    )
    port map (
      clk                         => bus_clk,
      reset                       => bus_reset,
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

      mmu_req_valid               => mmu_req_valid,
      mmu_req_ready               => mmu_req_ready,
      mmu_req_addr                => mmu_req_addr,

      mmu_resp_valid              => mmu_resp_valid,
      mmu_resp_ready              => mmu_resp_ready,
      mmu_resp_addr               => mmu_resp_addr,

      bus_wreq_valid              => dir_w.req_valid,
      bus_wreq_ready              => dir_w.req_ready,
      bus_wreq_addr               => dir_w.req_addr,
      bus_wreq_len                => dir_w.req_len,
      bus_wdat_valid              => dir_w.dat_valid,
      bus_wdat_ready              => dir_w.dat_ready,
      bus_wdat_data               => dir_w.dat_data,
      bus_wdat_strobe             => dir_w.dat_strobe,
      bus_wdat_last               => dir_w.dat_last,

      bus_rreq_valid              => dir_r.req_valid,
      bus_rreq_ready              => dir_r.req_ready,
      bus_rreq_addr               => dir_r.req_addr,
      bus_rreq_len                => dir_r.req_len,
      bus_rdat_valid              => dir_r.dat_valid,
      bus_rdat_ready              => dir_r.dat_ready,
      bus_rdat_data               => dir_r.dat_data,
      bus_rdat_last               => dir_r.dat_last,
      
      bus_resp_valid              => dir_w.resp_valid,
      bus_resp_ready              => dir_w.resp_ready,
      bus_resp_ok                 => dir_w.resp_ok
    );

  mm_hif_inst : MMHostInterface
    generic map (
      MEM_REGIONS                 => MEM_REGIONS
    )
    port map (
      clk                         => bus_clk,
      reset                       => bus_reset,
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
      clk                         => bus_clk,
      reset                       => bus_reset,

      -- Read address channel
      bus_rreq_addr               => mmu_r.req_addr,
      bus_rreq_len                => mmu_r.req_len,
      bus_rreq_valid              => mmu_r.req_valid,
      bus_rreq_ready              => mmu_r.req_ready,

      -- Read data channel
      bus_rdat_data               => mmu_r.dat_data,
      bus_rdat_last               => mmu_r.dat_last,
      bus_rdat_valid              => mmu_r.dat_valid,
      bus_rdat_ready              => mmu_r.dat_ready,

      -- Translate request channel
      req_valid                   => htr_req_valid,
      req_ready                   => htr_req_ready,
      req_addr                    => htr_req_addr,
      -- Translate response channel
      resp_valid                  => htr_resp_valid,
      resp_ready                  => htr_resp_ready,
      resp_virt                   => htr_resp_virt,
      resp_phys                   => htr_resp_phys,
      resp_mask                   => htr_resp_mask,

      dir_req_valid               => mmu_req_valid,
      dir_req_ready               => mmu_req_ready,
      dir_req_addr                => mmu_req_addr,

      dir_resp_valid              => mmu_resp_valid,
      dir_resp_ready              => mmu_resp_ready,
      dir_resp_addr               => mmu_resp_addr
    );

  bus_read_arb_inst : BusReadArbiter
    generic map (
      BUS_ADDR_WIDTH            => BUS_ADDR_WIDTH,
      BUS_LEN_WIDTH             => BUS_LEN_WIDTH,
      BUS_DATA_WIDTH            => BUS_DATA_WIDTH,
      NUM_SLAVE_PORTS           => 3,
      ARB_METHOD                => "FIXED",
      MAX_OUTSTANDING           => 8,
      SLV_REQ_SLICES            => false,
      MST_REQ_SLICE             => false,
      MST_DAT_SLICE             => false,
      SLV_DAT_SLICES            => false
    )
    port map (
      bus_clk                   => bus_clk,
      bus_reset                 => bus_reset,

      mst_rreq_valid            => mst_rreq_valid,
      mst_rreq_ready            => mst_rreq_ready,
      mst_rreq_addr             => mst_rreq_addr,
      mst_rreq_len              => mst_rreq_len,
      mst_rdat_valid            => mst_rdat_valid,
      mst_rdat_ready            => mst_rdat_ready,
      mst_rdat_data             => mst_rdat_data,
      mst_rdat_last             => mst_rdat_last,

      bs00_rreq_valid           => mmu_r.req_valid,
      bs00_rreq_ready           => mmu_r.req_ready,
      bs00_rreq_addr            => mmu_r.req_addr,
      bs00_rreq_len             => mmu_r.req_len,
      bs00_rdat_valid           => mmu_r.dat_valid,
      bs00_rdat_ready           => mmu_r.dat_ready,
      bs00_rdat_data            => mmu_r.dat_data,
      bs00_rdat_last            => mmu_r.dat_last,

      bs01_rreq_valid           => dir_r.req_valid,
      bs01_rreq_ready           => dir_r.req_ready,
      bs01_rreq_addr            => dir_r.req_addr,
      bs01_rreq_len             => dir_r.req_len,
      bs01_rdat_valid           => dir_r.dat_valid,
      bs01_rdat_ready           => dir_r.dat_ready,
      bs01_rdat_data            => dir_r.dat_data,
      bs01_rdat_last            => dir_r.dat_last,

      bs02_rreq_valid           => bench_sr.req_valid,
      bs02_rreq_ready           => bench_sr.req_ready,
      bs02_rreq_addr            => bench_sr.req_addr,
      bs02_rreq_len             => bench_sr.req_len,
      bs02_rdat_valid           => bench_sr.dat_valid,
      bs02_rdat_ready           => bench_sr.dat_ready,
      bs02_rdat_data            => bench_sr.dat_data,
      bs02_rdat_last            => bench_sr.dat_last
    );

  bus_write_arb_inst : BusWriteArbiter
    generic map (
      BUS_ADDR_WIDTH            => BUS_ADDR_WIDTH,
      BUS_LEN_WIDTH             => BUS_LEN_WIDTH,
      BUS_DATA_WIDTH            => BUS_DATA_WIDTH,
      BUS_STROBE_WIDTH          => BUS_STROBE_WIDTH,
      NUM_SLAVE_PORTS           => 1,
      ARB_METHOD                => "FIXED",
      MAX_DATA_LAG              => 2,
      MAX_OUTSTANDING           => 8,
      SLV_REQ_SLICES            => false,
      MST_REQ_SLICE             => false,
      MST_DAT_SLICE             => false,
      SLV_DAT_SLICES            => false,
      MST_RSP_SLICE             => false,
      SLV_RSP_SLICES            => false
    )
    port map (
      bus_clk                   => bus_clk,
      bus_reset                 => bus_reset,

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

      bs00_wreq_valid           => dir_w.req_valid,
      bs00_wreq_ready           => dir_w.req_ready,
      bs00_wreq_addr            => dir_w.req_addr,
      bs00_wreq_len             => dir_w.req_len,
      bs00_wdat_valid           => dir_w.dat_valid,
      bs00_wdat_ready           => dir_w.dat_ready,
      bs00_wdat_data            => dir_w.dat_data,
      bs00_wdat_strobe          => dir_w.dat_strobe,
      bs00_wdat_last            => dir_w.dat_last,
      bs00_resp_valid           => dir_w.resp_valid,
      bs00_resp_ready           => dir_w.resp_ready,
      bs00_resp_ok              => dir_w.resp_ok
    );

end architecture;

