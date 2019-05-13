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
use ieee.std_logic_misc.all;

library work;
use work.Utils.all;
use work.MM.all;
use work.Interconnect.all;

-- AXI4 compatible top level for Fletcher generated accelerators.
entity f1_top is
  generic (
    -- Host bus properties
    BUS_ADDR_WIDTH              : natural := 64;
    BUS_DATA_WIDTH              : natural := 512;
    BUS_STROBE_WIDTH            : natural := 64;
    BUS_LEN_WIDTH               : natural := 8;
    BUS_BURST_MAX_LEN           : natural := 64;
    BUS_BURST_STEP_LEN          : natural := 1;

    -- MMIO bus properties
    SLV_BUS_ADDR_WIDTH          : natural := 32;
    SLV_BUS_DATA_WIDTH          : natural := 32;
    REG_WIDTH                   : natural := 32;

    -- Virtual memory properties
    PAGE_SIZE_LOG2              : natural := 22;
    VM_BASE                     : unsigned(ADDR_WIDTH_LIMIT-1 downto 0) := X"4000_0000_0000_0000";
    MEM_REGIONS                 : natural := 1;
    MEM_SIZES                   : nat_array := (0 => 16*1024*1024/(2**22/1024)); -- (2**PAGE_SIZE_LOG2/1024)
    MEM_MAP_BASE                : unsigned(ADDR_WIDTH_LIMIT-1 downto 0) := (others => '0');
    MEM_MAP_SIZE_LOG2           : natural := 37;
    PT_ENTRIES_LOG2             : natural := 13;
    PTE_BITS                    : natural := 64; -- BUS_ADDR_WIDTH

    -- Accelerator properties
    INDEX_WIDTH                 : natural := 32;
    TAG_WIDTH                   : natural := 1;
    NUM_ARROW_BUFFERS           : natural := 0;
    NUM_USER_REGS               : natural := 0;
    NUM_REGS                    : natural := 26 + 12 * 2
  );
  port (
    acc_clk                     : in  std_logic;
    acc_reset                   : in  std_logic;
    bus_clk                     : in  std_logic;
    bus_reset_n                 : in  std_logic;

    ---------------------------------------------------------------------------
    -- AXI4 master as Device Memory Interface for Fletcher
    ---------------------------------------------------------------------------
    -- Read address channel
    m_axi_araddr                : out std_logic_vector(BUS_ADDR_WIDTH-1 downto 0);
    m_axi_arlen                 : out std_logic_vector(7 downto 0);
    m_axi_arvalid               : out std_logic;
    m_axi_arready               : in  std_logic;
    m_axi_arsize                : out std_logic_vector(2 downto 0);

    -- Read data channel
    m_axi_rdata                 : in  std_logic_vector(BUS_DATA_WIDTH-1 downto 0);
    m_axi_rresp                 : in  std_logic_vector(1 downto 0);
    m_axi_rlast                 : in  std_logic;
    m_axi_rvalid                : in  std_logic;
    m_axi_rready                : out std_logic;

    -- Write address channel
    m_axi_awvalid               : out std_logic;
    m_axi_awready               : in  std_logic;
    m_axi_awaddr                : out std_logic_vector(BUS_ADDR_WIDTH-1 downto 0);
    m_axi_awlen                 : out std_logic_vector(7 downto 0);
    m_axi_awsize                : out std_logic_vector(2 downto 0);

    -- Write data channel
    m_axi_wvalid                : out std_logic;
    m_axi_wready                : in  std_logic;
    m_axi_wdata                 : out std_logic_vector(BUS_DATA_WIDTH-1 downto 0);
    m_axi_wlast                 : out std_logic;
    m_axi_wstrb                 : out std_logic_vector(BUS_DATA_WIDTH/8-1 downto 0);

    -- Write response channel
    m_axi_bvalid                : in  std_logic;
    m_axi_bready                : out std_logic;
    m_axi_bresp                 : in  std_logic_vector(1 downto 0);

    ---------------------------------------------------------------------------
    -- AXI4 master as Device Memory Interface for Host
    ---------------------------------------------------------------------------
    -- Read address channel
    ml_axi_araddr               : out std_logic_vector(BUS_ADDR_WIDTH-1 downto 0);
    ml_axi_arid                 : out std_logic_vector(15 downto 0);
    ml_axi_arlen                : out std_logic_vector(7 downto 0);
    ml_axi_arvalid              : out std_logic;
    ml_axi_arready              : in  std_logic;
    ml_axi_arsize               : out std_logic_vector(2 downto 0);

    -- Read data channel
    ml_axi_rdata                : in  std_logic_vector(BUS_DATA_WIDTH-1 downto 0);
    ml_axi_rid                  : in  std_logic_vector(15 downto 0);
    ml_axi_rresp                : in  std_logic_vector(1 downto 0);
    ml_axi_rlast                : in  std_logic;
    ml_axi_rvalid               : in  std_logic;
    ml_axi_rready               : out std_logic;

    -- Write address channel
    ml_axi_awvalid              : out std_logic;
    ml_axi_awready              : in  std_logic;
    ml_axi_awid                 : out std_logic_vector(15 downto 0);
    ml_axi_awaddr               : out std_logic_vector(BUS_ADDR_WIDTH-1 downto 0);
    ml_axi_awlen                : out std_logic_vector(7 downto 0);
    ml_axi_awsize               : out std_logic_vector(2 downto 0);

    -- Write data channel
    ml_axi_wvalid               : out std_logic;
    ml_axi_wready               : in  std_logic;
    ml_axi_wdata                : out std_logic_vector(BUS_DATA_WIDTH-1 downto 0);
    ml_axi_wlast                : out std_logic;
    ml_axi_wstrb                : out std_logic_vector(BUS_DATA_WIDTH/8-1 downto 0);

    -- Write response channel
    ml_axi_bvalid               : in  std_logic;
    ml_axi_bready               : out std_logic;
    ml_axi_bid                  : in  std_logic_vector(15 downto 0);
    ml_axi_bresp                : in  std_logic_vector(1 downto 0);

    ---------------------------------------------------------------------------
    -- AXI4 slave as Host Memory Interface
    ---------------------------------------------------------------------------
    -- Read address channel
    s_axi_araddr                : in  std_logic_vector(BUS_ADDR_WIDTH-1 downto 0);
    s_axi_arid                  : in  std_logic_vector(15 downto 0);
    s_axi_arlen                 : in  std_logic_vector(7 downto 0);
    s_axi_arvalid               : in  std_logic;
    s_axi_arready               : out std_logic;
    s_axi_arsize                : in  std_logic_vector(2 downto 0);

    -- Read data channel
    s_axi_rdata                 : out std_logic_vector(BUS_DATA_WIDTH-1 downto 0);
    s_axi_rid                   : out std_logic_vector(15 downto 0);
    s_axi_rresp                 : out std_logic_vector(1 downto 0);
    s_axi_rlast                 : out std_logic;
    s_axi_rvalid                : out std_logic;
    s_axi_rready                : in  std_logic;

    -- Write address channel
    s_axi_awvalid               : in  std_logic;
    s_axi_awready               : out std_logic;
    s_axi_awid                  : in  std_logic_vector(15 downto 0);
    s_axi_awaddr                : in  std_logic_vector(BUS_ADDR_WIDTH-1 downto 0);
    s_axi_awlen                 : in  std_logic_vector(7 downto 0);
    s_axi_awsize                : in  std_logic_vector(2 downto 0);

    -- Write data channel
    s_axi_wvalid                : in  std_logic;
    s_axi_wready                : out std_logic;
    s_axi_wdata                 : in  std_logic_vector(BUS_DATA_WIDTH-1 downto 0);
    s_axi_wlast                 : in  std_logic;
    s_axi_wstrb                 : in  std_logic_vector(BUS_DATA_WIDTH/8-1 downto 0);

    -- Write response channel
    s_axi_bvalid                : out std_logic;
    s_axi_bready                : in  std_logic;
    s_axi_bid                   : out std_logic_vector(15 downto 0);
    s_axi_bresp                 : out std_logic_vector(1 downto 0);

    ---------------------------------------------------------------------------
    -- AXI4-lite Slave as MMIO interface
    ---------------------------------------------------------------------------
    -- Write adress channel
    mmio_axi_awvalid               : in std_logic;
    mmio_axi_awready               : out std_logic;
    mmio_axi_awaddr                : in std_logic_vector(SLV_BUS_ADDR_WIDTH-1 downto 0);

    -- Write data channel
    mmio_axi_wvalid                : in std_logic;
    mmio_axi_wready                : out std_logic;
    mmio_axi_wdata                 : in std_logic_vector(SLV_BUS_DATA_WIDTH-1 downto 0);
    mmio_axi_wstrb                 : in std_logic_vector((SLV_BUS_DATA_WIDTH/8)-1 downto 0);

    -- Write response channel
    mmio_axi_bvalid                : out std_logic;
    mmio_axi_bready                : in std_logic;
    mmio_axi_bresp                 : out std_logic_vector(1 downto 0);

    -- Read address channel
    mmio_axi_arvalid               : in std_logic;
    mmio_axi_arready               : out std_logic;
    mmio_axi_araddr                : in std_logic_vector(SLV_BUS_ADDR_WIDTH-1 downto 0);

    -- Read data channel
    mmio_axi_rvalid                : out std_logic;
    mmio_axi_rready                : in std_logic;
    mmio_axi_rdata                 : out std_logic_vector(SLV_BUS_DATA_WIDTH-1 downto 0);
    mmio_axi_rresp                 : out std_logic_vector(1 downto 0)
  );
end f1_top;

architecture Behavorial of f1_top is

  component axi_top is
    generic (
      -- Host bus properties
      BUS_ADDR_WIDTH              : natural := 64;
      BUS_DATA_WIDTH              : natural := 512;
      BUS_STROBE_WIDTH            : natural := 64;
      BUS_LEN_WIDTH               : natural := 8;
      BUS_BURST_MAX_LEN           : natural := 64;
      BUS_BURST_STEP_LEN          : natural := 1;

      -- MMIO bus properties
      SLV_BUS_ADDR_WIDTH          : natural := 32;
      SLV_BUS_DATA_WIDTH          : natural := 32;
      REG_WIDTH                   : natural := 32;

      -- Arrow properties
      INDEX_WIDTH                 : natural := 32;

      -- Virtual memory properties
      PAGE_SIZE_LOG2              : natural := 22;
      VM_BASE                     : unsigned(ADDR_WIDTH_LIMIT-1 downto 0) := X"4000_0000_0000_0000";
      MEM_REGIONS                 : natural := 1;
      MEM_SIZES                   : nat_array;
      MEM_MAP_BASE                : unsigned(ADDR_WIDTH_LIMIT-1 downto 0) := (others => '0');
      MEM_MAP_SIZE_LOG2           : natural := 37;
      PT_ENTRIES_LOG2             : natural := 13;
      PTE_BITS                    : natural := 64; -- BUS_ADDR_WIDTH

      -- Accelerator properties
      TAG_WIDTH                   : natural := 1;
      NUM_ARROW_BUFFERS           : natural := 0;
      NUM_USER_REGS               : natural := 0;
      NUM_REGS                    : natural := 10
    );
    port (
      acc_clk                     : in  std_logic;
      acc_reset                   : in  std_logic;
      bus_clk                     : in  std_logic;
      bus_reset_n                 : in  std_logic;

      ---------------------------------------------------------------------------
      -- AXI4 master as Host Memory Interface
      ---------------------------------------------------------------------------
      -- Read address channel
      m_axi_araddr                : out std_logic_vector(BUS_ADDR_WIDTH-1 downto 0);
      m_axi_arlen                 : out std_logic_vector(7 downto 0);
      m_axi_arvalid               : out std_logic;
      m_axi_arready               : in  std_logic;
      m_axi_arsize                : out std_logic_vector(2 downto 0);

      -- Read data channel
      m_axi_rdata                 : in  std_logic_vector(BUS_DATA_WIDTH-1 downto 0);
      m_axi_rresp                 : in  std_logic_vector(1 downto 0);
      m_axi_rlast                 : in  std_logic;
      m_axi_rvalid                : in  std_logic;
      m_axi_rready                : out std_logic;

      -- Write address channel
      m_axi_awvalid               : out std_logic;
      m_axi_awready               : in  std_logic;
      m_axi_awaddr                : out std_logic_vector(BUS_ADDR_WIDTH-1 downto 0);
      m_axi_awlen                 : out std_logic_vector(7 downto 0);
      m_axi_awsize                : out std_logic_vector(2 downto 0);

      -- Write data channel
      m_axi_wvalid                : out std_logic;
      m_axi_wready                : in  std_logic;
      m_axi_wdata                 : out std_logic_vector(BUS_DATA_WIDTH-1 downto 0);
      m_axi_wlast                 : out std_logic;
      m_axi_wstrb                 : out std_logic_vector(BUS_DATA_WIDTH/8-1 downto 0);

      -- Write response channel
      m_axi_bvalid                : in  std_logic;
      m_axi_bready                : out std_logic;
      m_axi_bresp                 : in  std_logic_vector(1 downto 0);

      ---------------------------------------------------------------------------
      -- AXI4-lite Slave as MMIO interface
      ---------------------------------------------------------------------------
      -- Write adress channel
      s_axi_awvalid               : in std_logic;
      s_axi_awready               : out std_logic;
      s_axi_awaddr                : in std_logic_vector(SLV_BUS_ADDR_WIDTH-1 downto 0);

      -- Write data channel
      s_axi_wvalid                : in std_logic;
      s_axi_wready                : out std_logic;
      s_axi_wdata                 : in std_logic_vector(SLV_BUS_DATA_WIDTH-1 downto 0);
      s_axi_wstrb                 : in std_logic_vector((SLV_BUS_DATA_WIDTH/8)-1 downto 0);

      -- Write response channel
      s_axi_bvalid                : out std_logic;
      s_axi_bready                : in std_logic;
      s_axi_bresp                 : out std_logic_vector(1 downto 0);

      -- Read address channel
      s_axi_arvalid               : in std_logic;
      s_axi_arready               : out std_logic;
      s_axi_araddr                : in std_logic_vector(SLV_BUS_ADDR_WIDTH-1 downto 0);

      -- Read data channel
      s_axi_rvalid                : out std_logic;
      s_axi_rready                : in std_logic;
      s_axi_rdata                 : out std_logic_vector(SLV_BUS_DATA_WIDTH-1 downto 0);
      s_axi_rresp                 : out std_logic_vector(1 downto 0);
      -- Translate request channel
      htr_req_valid               : in  std_logic := '0';
      htr_req_ready               : out std_logic;
      htr_req_addr                : in  std_logic_vector(BUS_ADDR_WIDTH-1 downto 0) := (others => '0');
      -- Translate response channel
      htr_resp_valid              : out std_logic;
      htr_resp_ready              : in  std_logic := '1';
      htr_resp_virt               : out std_logic_vector(BUS_ADDR_WIDTH-1 downto 0);
      htr_resp_phys               : out std_logic_vector(BUS_ADDR_WIDTH-1 downto 0);
      htr_resp_mask               : out std_logic_vector(BUS_ADDR_WIDTH-1 downto 0)
    );
  end component;

  signal bus_reset               : std_logic;

  -- Translate request channel
  signal tr_q_valid              : std_logic;
  signal tr_q_ready              : std_logic;
  signal tr_q_addr               : std_logic_vector(BUS_ADDR_WIDTH-1 downto 0);
  -- Translate response channel
  signal tr_a_valid              : std_logic;
  signal tr_a_ready              : std_logic;
  signal tr_a_virt               : std_logic_vector(BUS_ADDR_WIDTH-1 downto 0);
  signal tr_a_phys               : std_logic_vector(BUS_ADDR_WIDTH-1 downto 0);
  signal tr_a_mask               : std_logic_vector(BUS_ADDR_WIDTH-1 downto 0);
  signal tr_a_data               : std_logic_vector(BUS_ADDR_WIDTH*3-1 downto 0);

  -- Translate request channel (read)
  signal tr_rq_valid             : std_logic;
  signal tr_rq_ready             : std_logic;
  signal tr_rq_addr              : std_logic_vector(BUS_ADDR_WIDTH-1 downto 0);
  -- Translate response channel (read)
  signal tr_ra_valid             : std_logic;
  signal tr_ra_ready             : std_logic;
  signal tr_ra_virt              : std_logic_vector(BUS_ADDR_WIDTH-1 downto 0);
  signal tr_ra_phys              : std_logic_vector(BUS_ADDR_WIDTH-1 downto 0);
  signal tr_ra_mask              : std_logic_vector(BUS_ADDR_WIDTH-1 downto 0);
  signal tr_ra_data              : std_logic_vector(BUS_ADDR_WIDTH*3-1 downto 0);

  -- Translate request channel (write)
  signal tr_wq_valid             : std_logic;
  signal tr_wq_ready             : std_logic;
  signal tr_wq_addr              : std_logic_vector(BUS_ADDR_WIDTH-1 downto 0);
  -- Translate response channel (write)
  signal tr_wa_valid             : std_logic;
  signal tr_wa_ready             : std_logic;
  signal tr_wa_virt              : std_logic_vector(BUS_ADDR_WIDTH-1 downto 0);
  signal tr_wa_phys              : std_logic_vector(BUS_ADDR_WIDTH-1 downto 0);
  signal tr_wa_mask              : std_logic_vector(BUS_ADDR_WIDTH-1 downto 0);
  signal tr_wa_data              : std_logic_vector(BUS_ADDR_WIDTH*3-1 downto 0);

  signal s_axi_aruser            : std_logic_vector(s_axi_arid'length + s_axi_arsize'length - 1 downto 0);
  signal ml_axi_aruser           : std_logic_vector(s_axi_arid'length + s_axi_arsize'length - 1 downto 0);
  signal s_axi_awuser            : std_logic_vector(s_axi_awid'length + s_axi_awsize'length - 1 downto 0);
  signal ml_axi_awuser           : std_logic_vector(s_axi_awid'length + s_axi_awsize'length - 1 downto 0);
begin

  -- Active high reset
  bus_reset <= '1' when bus_reset_n = '0' else '0';

  axi_top_inst : axi_top
  generic map (
    -- Host bus properties
    BUS_ADDR_WIDTH              => BUS_ADDR_WIDTH,
    BUS_DATA_WIDTH              => BUS_DATA_WIDTH,
    BUS_STROBE_WIDTH            => BUS_STROBE_WIDTH,
    BUS_LEN_WIDTH               => BUS_LEN_WIDTH,
    BUS_BURST_MAX_LEN           => BUS_BURST_MAX_LEN,
    BUS_BURST_STEP_LEN          => BUS_BURST_STEP_LEN,

    -- MMIO bus properties
    SLV_BUS_ADDR_WIDTH          => SLV_BUS_ADDR_WIDTH,
    SLV_BUS_DATA_WIDTH          => SLV_BUS_DATA_WIDTH,
    REG_WIDTH                   => REG_WIDTH,

    -- Arrow properties
    INDEX_WIDTH                 => INDEX_WIDTH,

    -- Virtual memory properties
    PAGE_SIZE_LOG2              => PAGE_SIZE_LOG2,
    VM_BASE                     => VM_BASE,
    MEM_REGIONS                 => MEM_REGIONS,
    MEM_SIZES                   => MEM_SIZES,
    MEM_MAP_BASE                => MEM_MAP_BASE,
    MEM_MAP_SIZE_LOG2           => MEM_MAP_SIZE_LOG2,
    PT_ENTRIES_LOG2             => PT_ENTRIES_LOG2,
    PTE_BITS                    => PTE_BITS,

    -- Accelerator properties
    TAG_WIDTH                   => TAG_WIDTH,
    NUM_ARROW_BUFFERS           => NUM_ARROW_BUFFERS,
    NUM_USER_REGS               => NUM_USER_REGS,
    NUM_REGS                    => NUM_REGS
  )
  port map (
    acc_clk                     => acc_clk,
    acc_reset                   => acc_reset,
    bus_clk                     => bus_clk,
    bus_reset_n                 => bus_reset_n,

    ---------------------------------------------------------------------------
    -- AXI4 master as Host Memory Interface
    ---------------------------------------------------------------------------
    -- Read address channel
    m_axi_araddr                => m_axi_araddr,
    m_axi_arlen                 => m_axi_arlen,
    m_axi_arvalid               => m_axi_arvalid,
    m_axi_arready               => m_axi_arready,
    m_axi_arsize                => m_axi_arsize,

    -- Read data channel
    m_axi_rdata                 => m_axi_rdata,
    m_axi_rresp                 => m_axi_rresp,
    m_axi_rlast                 => m_axi_rlast,
    m_axi_rvalid                => m_axi_rvalid,
    m_axi_rready                => m_axi_rready,

    -- Write address channel
    m_axi_awvalid               => m_axi_awvalid,
    m_axi_awready               => m_axi_awready,
    m_axi_awaddr                => m_axi_awaddr,
    m_axi_awlen                 => m_axi_awlen,
    m_axi_awsize                => m_axi_awsize,

    -- Write data channel
    m_axi_wvalid                => m_axi_wvalid,
    m_axi_wready                => m_axi_wready,
    m_axi_wdata                 => m_axi_wdata,
    m_axi_wlast                 => m_axi_wlast,
    m_axi_wstrb                 => m_axi_wstrb,

    -- Write response channel
    m_axi_bvalid                => m_axi_bvalid,
    m_axi_bready                => m_axi_bready,
    m_axi_bresp                 => m_axi_bresp,

    ---------------------------------------------------------------------------
    -- AXI4-lite Slave as MMIO interface
    ---------------------------------------------------------------------------
    -- Write adress channel
    s_axi_awvalid               => mmio_axi_awvalid,
    s_axi_awready               => mmio_axi_awready,
    s_axi_awaddr                => mmio_axi_awaddr,

    -- Write data channel
    s_axi_wvalid                => mmio_axi_wvalid,
    s_axi_wready                => mmio_axi_wready,
    s_axi_wdata                 => mmio_axi_wdata,
    s_axi_wstrb                 => mmio_axi_wstrb,

    -- Write response channel
    s_axi_bvalid                => mmio_axi_bvalid,
    s_axi_bready                => mmio_axi_bready,
    s_axi_bresp                 => mmio_axi_bresp,

    -- Read address channel
    s_axi_arvalid               => mmio_axi_arvalid,
    s_axi_arready               => mmio_axi_arready,
    s_axi_araddr                => mmio_axi_araddr,

    -- Read data channel
    s_axi_rvalid                => mmio_axi_rvalid,
    s_axi_rready                => mmio_axi_rready,
    s_axi_rdata                 => mmio_axi_rdata,
    s_axi_rresp                 => mmio_axi_rresp,

    -- Translate request channel
    htr_req_valid               => tr_q_valid,
    htr_req_ready               => tr_q_ready,
    htr_req_addr                => tr_q_addr,
    -- Translate response channel
    htr_resp_valid              => tr_a_valid,
    htr_resp_ready              => tr_a_ready,
    htr_resp_virt               => tr_a_virt,
    htr_resp_phys               => tr_a_phys,
    htr_resp_mask               => tr_a_mask
  );

  -----------------------------------------------------------------------------
  -- Device memory AXI slave for host
  -----------------------------------------------------------------------------
  -- Read data channel
  s_axi_rid                     <= ml_axi_rid;
  s_axi_rdata                   <= ml_axi_rdata;
  s_axi_rresp                   <= ml_axi_rresp;
  s_axi_rlast                   <= ml_axi_rlast;
  s_axi_rvalid                  <= ml_axi_rvalid;
  ml_axi_rready                 <= s_axi_rready;

  -- Write data channel
  ml_axi_wvalid                 <= s_axi_wvalid;
  s_axi_wready                  <= ml_axi_wready;
  ml_axi_wdata                  <= s_axi_wdata;
  ml_axi_wlast                  <= s_axi_wlast;
  ml_axi_wstrb                  <= s_axi_wstrb;

  -- Write response channel
  s_axi_bvalid                  <= ml_axi_bvalid;
  ml_axi_bready                 <= s_axi_bready;
  s_axi_bid                     <= ml_axi_bid;
  s_axi_bresp                   <= ml_axi_bresp;

  read_translator : MMTranslator
  generic map (
    BUS_ADDR_WIDTH              => BUS_ADDR_WIDTH,
    BUS_LEN_WIDTH               => BUS_LEN_WIDTH,
    USER_WIDTH                  => s_axi_aruser'length,
    VM_BASE                     => VM_BASE,
    PT_ENTRIES_LOG2             => PT_ENTRIES_LOG2,
    PAGE_SIZE_LOG2              => PAGE_SIZE_LOG2,
    SLV_SLICES                  => 4, -- Extra slices to accomodate SLR crossing
    MST_SLICES                  => 4
  )
  port map (
    clk                         => bus_clk,
    reset                       => bus_reset,

    -- Slave request channel
    slv_req_valid               => s_axi_arvalid,
    slv_req_ready               => s_axi_arready,
    slv_req_addr                => s_axi_araddr,
    slv_req_len                 => s_axi_arlen,
    slv_req_user                => s_axi_aruser,
    -- Master request channel
    mst_req_valid               => ml_axi_arvalid,
    mst_req_ready               => ml_axi_arready,
    mst_req_addr                => ml_axi_araddr,
    mst_req_len                 => ml_axi_arlen,
    mst_req_user                => ml_axi_aruser,

    -- Translate request channel
    req_valid                   => tr_rq_valid,
    req_ready                   => tr_rq_ready,
    req_addr                    => tr_rq_addr,
    -- Translate response channel
    resp_valid                  => tr_ra_valid,
    resp_ready                  => tr_ra_ready,
    resp_virt                   => tr_ra_virt,
    resp_phys                   => tr_ra_phys,
    resp_mask                   => tr_ra_mask
  );
  s_axi_aruser  <= s_axi_arid & s_axi_arsize;
  ml_axi_arsize <= ml_axi_aruser(s_axi_arsize'high downto 0);
  ml_axi_arid   <= ml_axi_aruser(s_axi_aruser'high downto s_axi_arsize'high + 1);

  write_translator : MMTranslator
  generic map (
    BUS_ADDR_WIDTH              => BUS_ADDR_WIDTH,
    BUS_LEN_WIDTH               => BUS_LEN_WIDTH,
    USER_WIDTH                  => s_axi_awuser'length,
    VM_BASE                     => VM_BASE,
    PT_ENTRIES_LOG2             => PT_ENTRIES_LOG2,
    PAGE_SIZE_LOG2              => PAGE_SIZE_LOG2,
    SLV_SLICES                  => 4, -- Extra slices to accomodate SLR crossing
    MST_SLICES                  => 4
  )
  port map (
    clk                         => bus_clk,
    reset                       => bus_reset,

    -- Slave request channel
    slv_req_valid               => s_axi_awvalid,
    slv_req_ready               => s_axi_awready,
    slv_req_addr                => s_axi_awaddr,
    slv_req_len                 => s_axi_awlen,
    slv_req_user                => s_axi_awuser,
    -- Master request channel
    mst_req_valid               => ml_axi_awvalid,
    mst_req_ready               => ml_axi_awready,
    mst_req_addr                => ml_axi_awaddr,
    mst_req_len                 => ml_axi_awlen,
    mst_req_user                => ml_axi_awuser,

    -- Translate request channel
    req_valid                   => tr_wq_valid,
    req_ready                   => tr_wq_ready,
    req_addr                    => tr_wq_addr,
    -- Translate response channel
    resp_valid                  => tr_wa_valid,
    resp_ready                  => tr_wa_ready,
    resp_virt                   => tr_wa_virt,
    resp_phys                   => tr_wa_phys,
    resp_mask                   => tr_wa_mask
  );
  s_axi_awuser  <= s_axi_awid & s_axi_awsize;
  ml_axi_awsize <= ml_axi_awuser(s_axi_awsize'high downto 0);
  ml_axi_awid   <= ml_axi_awuser(s_axi_awuser'high downto s_axi_awsize'high + 1);

  -- Arbiter for the address translation requests of AXI slave R/W channels.
  tr_req_arb_inst : BusReadArbiter
  generic map (
    BUS_ADDR_WIDTH              => BUS_ADDR_WIDTH,
    BUS_LEN_WIDTH               => 1,
    BUS_DATA_WIDTH              => BUS_ADDR_WIDTH * 3,
    NUM_SLAVE_PORTS             => 2,
    ARB_METHOD                  => "ROUND-ROBIN",
    MAX_OUTSTANDING             => 2,
    SLV_REQ_SLICES              => true,
    MST_REQ_SLICE               => true,
    MST_DAT_SLICE               => true,
    SLV_DAT_SLICES              => true
  )
  port map (
    bus_clk                     => bus_clk,
    bus_reset                   => bus_reset,

    mst_rreq_valid              => tr_q_valid,
    mst_rreq_ready              => tr_q_ready,
    mst_rreq_addr               => tr_q_addr,
    mst_rdat_valid              => tr_a_valid,
    mst_rdat_ready              => tr_a_ready,
    mst_rdat_data               => tr_a_data,
    mst_rdat_last               => '1',

    bs00_rreq_valid             => tr_rq_valid,
    bs00_rreq_ready             => tr_rq_ready,
    bs00_rreq_addr              => tr_rq_addr,
    bs00_rreq_len               => "1",
    bs00_rdat_valid             => tr_ra_valid,
    bs00_rdat_ready             => tr_ra_ready,
    bs00_rdat_data              => tr_ra_data,

    bs01_rreq_valid             => tr_wq_valid,
    bs01_rreq_ready             => tr_wq_ready,
    bs01_rreq_addr              => tr_wq_addr,
    bs01_rreq_len               => "1",
    bs01_rdat_valid             => tr_wa_valid,
    bs01_rdat_ready             => tr_wa_ready,
    bs01_rdat_data              => tr_wa_data
  );

  tr_a_data <= tr_a_virt & tr_a_phys & tr_a_mask;

  tr_ra_virt <= EXTRACT(tr_ra_data, BUS_ADDR_WIDTH*2, BUS_ADDR_WIDTH);
  tr_ra_phys <= EXTRACT(tr_ra_data, BUS_ADDR_WIDTH*1, BUS_ADDR_WIDTH);
  tr_ra_mask <= EXTRACT(tr_ra_data, BUS_ADDR_WIDTH*0, BUS_ADDR_WIDTH);

  tr_wa_virt <= EXTRACT(tr_wa_data, BUS_ADDR_WIDTH*2, BUS_ADDR_WIDTH);
  tr_wa_phys <= EXTRACT(tr_wa_data, BUS_ADDR_WIDTH*1, BUS_ADDR_WIDTH);
  tr_wa_mask <= EXTRACT(tr_wa_data, BUS_ADDR_WIDTH*0, BUS_ADDR_WIDTH);

end architecture;
