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

library work;
use work.Arrow.all;
use work.Columns.all;
use work.Interconnect.all;
use work.Wrapper.all;
use work.Utils.all;
use work.MM.all;
use work.MM_tc_params.all;

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
    TAG_WIDTH                                  : natural
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
    regs_out_en                                : out std_logic_vector(NUM_REGS-1 downto 0)
  );
end fletcher_wrapper;

architecture Implementation of fletcher_wrapper is

  signal cmd_region   : std_logic_vector(log2ceil(MEM_REGIONS)-1 downto 0);
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

begin
  mm_inst : MMDirector
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

      -- Request channel
      bus_wreq_valid              => mst_wreq_valid,
      bus_wreq_ready              => mst_wreq_ready,
      bus_wreq_addr               => mst_wreq_addr,
      bus_wreq_len                => mst_wreq_len,

      -- Data channel             
      bus_wdat_valid              => mst_wdat_valid,
      bus_wdat_ready              => mst_wdat_ready,
      bus_wdat_data               => mst_wdat_data,
      bus_wdat_strobe             => mst_wdat_strobe,
      bus_wdat_last               => mst_wdat_last,

      -- Response channel
      bus_resp_valid              => mst_resp_valid,
      bus_resp_ready              => mst_resp_ready,
      bus_resp_ok                 => mst_resp_ok,

      -- Read address channel
      bus_rreq_addr               => mst_rreq_addr,
      bus_rreq_len                => mst_rreq_len,
      bus_rreq_valid              => mst_rreq_valid,
      bus_rreq_ready              => mst_rreq_ready,

      -- Read data channel
      bus_rdat_data               => mst_rdat_data,
      bus_rdat_last               => mst_rdat_last,
      bus_rdat_valid              => mst_rdat_valid,
      bus_rdat_ready              => mst_rdat_ready
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

      regs_in                     => regs_in (9*REG_WIDTH-1 downto 0),
      regs_out                    => regs_out(9*REG_WIDTH-1 downto 0),
      regs_out_en                 => regs_out_en(9-1 downto 0)
    );

end architecture;

