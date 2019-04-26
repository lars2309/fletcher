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
  use ieee.numeric_std.all;
  use ieee.std_logic_misc.all;

package AXI is

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

      -- Accelerator properties
      TAG_WIDTH                   : natural := 1;
      NUM_ARROW_BUFFERS           : natural := 0;
      NUM_USER_REGS               : natural := 0;
      NUM_REGS                    : natural := 10
    );
    port (
      acc_clk                   : in  std_logic;
      acc_reset                 : in  std_logic;
      bus_clk                   : in  std_logic;
      bus_reset_n               : in  std_logic;
      m_axi_araddr              : out std_logic_vector(BUS_ADDR_WIDTH-1 downto 0);
      m_axi_arlen               : out std_logic_vector(7 downto 0);
      m_axi_arvalid             : out std_logic;
      m_axi_arready             : in  std_logic;
      m_axi_arsize              : out std_logic_vector(2 downto 0);
      m_axi_rdata               : in  std_logic_vector(BUS_DATA_WIDTH-1 downto 0);
      m_axi_rresp               : in  std_logic_vector(1 downto 0);
      m_axi_rlast               : in  std_logic;
      m_axi_rvalid              : in  std_logic;
      m_axi_rready              : out std_logic;
      m_axi_awvalid             : out std_logic;
      m_axi_awready             : in  std_logic;
      m_axi_awaddr              : out std_logic_vector(BUS_ADDR_WIDTH-1 downto 0);
      m_axi_awlen               : out std_logic_vector(7 downto 0);
      m_axi_awsize              : out std_logic_vector(2 downto 0);
      m_axi_wvalid              : out std_logic;
      m_axi_wready              : in  std_logic;
      m_axi_wdata               : out std_logic_vector(BUS_DATA_WIDTH-1 downto 0);
      m_axi_wlast               : out std_logic;
      m_axi_wstrb               : out std_logic_vector(BUS_DATA_WIDTH/8-1 downto 0);
      m_axi_bvalid              : in  std_logic;
      m_axi_bready              : out std_logic;
      m_axi_bresp               : in  std_logic_vector(1 downto 0);
      s_axi_awvalid             : in std_logic;
      s_axi_awready             : out std_logic;
      s_axi_awaddr              : in std_logic_vector(SLV_BUS_ADDR_WIDTH-1 downto 0);
      s_axi_wvalid              : in std_logic;
      s_axi_wready              : out std_logic;
      s_axi_wdata               : in std_logic_vector(SLV_BUS_DATA_WIDTH-1 downto 0);
      s_axi_wstrb               : in std_logic_vector((SLV_BUS_DATA_WIDTH/8)-1 downto 0);
      s_axi_bvalid              : out std_logic;
      s_axi_bready              : in std_logic;
      s_axi_bresp               : out std_logic_vector(1 downto 0);
      s_axi_arvalid             : in std_logic;
      s_axi_arready             : out std_logic;
      s_axi_araddr              : in std_logic_vector(SLV_BUS_ADDR_WIDTH-1 downto 0);
      s_axi_rvalid              : out std_logic;
      s_axi_rready              : in std_logic;
      s_axi_rdata               : out std_logic_vector(SLV_BUS_DATA_WIDTH-1 downto 0);
      s_axi_rresp               : out std_logic_vector(1 downto 0)
    );
  end component;
  
  component axi_read_converter is
    generic (
      ADDR_WIDTH                : natural;
      MASTER_DATA_WIDTH         : natural;
      MASTER_LEN_WIDTH          : natural;
      SLAVE_DATA_WIDTH          : natural;
      SLAVE_LEN_WIDTH           : natural;
      SLAVE_MAX_BURST           : natural;
      ENABLE_FIFO               : boolean := true;
      SLV_REQ_SLICE_DEPTH       : natural := 2;
      SLV_DAT_SLICE_DEPTH       : natural := 2;
      MST_REQ_SLICE_DEPTH       : natural := 2;
      MST_DAT_SLICE_DEPTH       : natural := 2
    );

    port (
      clk                       : in  std_logic;
      reset_n                   : in  std_logic;
      slv_bus_rreq_addr         : in  std_logic_vector(ADDR_WIDTH-1 downto 0);
      slv_bus_rreq_len          : in  std_logic_vector(SLAVE_LEN_WIDTH-1 downto 0);
      slv_bus_rreq_valid        : in  std_logic;
      slv_bus_rreq_ready        : out std_logic;
      slv_bus_rdat_data         : out std_logic_vector(SLAVE_DATA_WIDTH-1 downto 0);
      slv_bus_rdat_last         : out std_logic;
      slv_bus_rdat_valid        : out std_logic;
      slv_bus_rdat_ready        : in  std_logic;
      m_axi_araddr              : out std_logic_vector(ADDR_WIDTH-1 downto 0);
      m_axi_arlen               : out std_logic_vector(MASTER_LEN_WIDTH-1 downto 0);
      m_axi_arvalid             : out std_logic;
      m_axi_arready             : in  std_logic;
      m_axi_arsize              : out std_logic_vector(2 downto 0);
      m_axi_rdata               : in  std_logic_vector(MASTER_DATA_WIDTH-1 downto 0);
      m_axi_rlast               : in  std_logic;
      m_axi_rvalid              : in  std_logic;
      m_axi_rready              : out std_logic
    );
  end component;
  
  component axi_write_converter is
    generic (
      ADDR_WIDTH                : natural;
      MASTER_DATA_WIDTH         : natural;
      MASTER_LEN_WIDTH          : natural;
      SLAVE_DATA_WIDTH          : natural;
      SLAVE_LEN_WIDTH           : natural;
      SLAVE_MAX_BURST           : natural;
      ENABLE_FIFO               : boolean := true;
      SLV_REQ_SLICE_DEPTH       : natural := 2;
      SLV_DAT_SLICE_DEPTH       : natural := 2;
      SLV_RSP_SLICE_DEPTH       : natural := 2;
      MST_REQ_SLICE_DEPTH       : natural := 2;
      MST_DAT_SLICE_DEPTH       : natural := 2;
      MST_RSP_SLICE_DEPTH       : natural := 2
    );                          
    port (                      
      clk                       : in  std_logic;
      reset_n                   : in  std_logic;
      slv_bus_wreq_valid        : in  std_logic;
      slv_bus_wreq_ready        : out std_logic;
      slv_bus_wreq_addr         : in  std_logic_vector(ADDR_WIDTH-1 downto 0);
      slv_bus_wreq_len          : in  std_logic_vector(SLAVE_LEN_WIDTH-1 downto 0);
      slv_bus_wdat_valid        : in  std_logic;
      slv_bus_wdat_ready        : out std_logic;
      slv_bus_wdat_data         : in  std_logic_vector(SLAVE_DATA_WIDTH-1 downto 0);
      slv_bus_wdat_strobe       : in  std_logic_vector(SLAVE_DATA_WIDTH/8-1 downto 0);
      slv_bus_wdat_last         : in  std_logic;
      slv_bus_resp_valid        : out std_logic;
      slv_bus_resp_ready        : in  std_logic;
      slv_bus_resp_ok           : out std_logic;
      m_axi_awaddr              : out std_logic_vector(ADDR_WIDTH-1 downto 0);
      m_axi_awlen               : out std_logic_vector(MASTER_LEN_WIDTH-1 downto 0);
      m_axi_awvalid             : out std_logic;
      m_axi_awready             : in  std_logic;
      m_axi_awsize              : out std_logic_vector(2 downto 0);
      m_axi_wvalid              : out std_logic;
      m_axi_wready              : in  std_logic;
      m_axi_wdata               : out std_logic_vector(MASTER_DATA_WIDTH-1 downto 0);
      m_axi_wstrb               : out std_logic_vector(MASTER_DATA_WIDTH/8-1 downto 0);
      m_axi_wlast               : out std_logic;
      m_axi_bvalid              : in  std_logic;
      m_axi_bready              : out std_logic;
      m_axi_bresp               : in  std_logic_vector(1 downto 0)
    );
  end component;

  component axi_mmio is
    generic (
      BUS_ADDR_WIDTH            : natural;
      BUS_DATA_WIDTH            : natural;   
      NUM_REGS                  : natural;
      REG_CONFIG                : string := "";
      REG_RESET                 : string := "";
      SLV_R_SLICE_DEPTH         : natural := 2;
      SLV_W_SLICE_DEPTH         : natural := 2
    );
    port (
      clk                       : in  std_logic;
      reset_n                   : in  std_logic;
      s_axi_awvalid             : in  std_logic;
      s_axi_awready             : out std_logic;
      s_axi_awaddr              : in  std_logic_vector(BUS_ADDR_WIDTH-1 downto 0);
      s_axi_wvalid              : in  std_logic;
      s_axi_wready              : out std_logic;
      s_axi_wdata               : in  std_logic_vector(BUS_DATA_WIDTH-1 downto 0);
      s_axi_wstrb               : in  std_logic_vector((BUS_DATA_WIDTH/8)-1 downto 0);
      s_axi_bvalid              : out std_logic;
      s_axi_bready              : in  std_logic;
      s_axi_bresp               : out std_logic_vector(1 downto 0);
      s_axi_arvalid             : in  std_logic;
      s_axi_arready             : out std_logic;
      s_axi_araddr              : in  std_logic_vector(BUS_ADDR_WIDTH-1 downto 0);
      s_axi_rvalid              : out std_logic;
      s_axi_rready              : in  std_logic;
      s_axi_rdata               : out std_logic_vector(BUS_DATA_WIDTH-1 downto 0);
      s_axi_rresp               : out std_logic_vector(1 downto 0);
      regs_out                  : out std_logic_vector(BUS_DATA_WIDTH*NUM_REGS-1 downto 0);
      regs_in                   : in  std_logic_vector(BUS_DATA_WIDTH*NUM_REGS-1 downto 0);
      regs_in_en                : in  std_logic_vector(NUM_REGS-1 downto 0)
    );
  end component;

  component AXIReadWriteSlaveMock is
    generic (

      -- Bus address width.
      BUS_ADDR_WIDTH              : natural := 32;

      -- Bus burst length width.
      BUS_LEN_WIDTH               : natural := 8;

      -- Bus data width.
      BUS_DATA_WIDTH              : natural := 32;
      
      -- Bus strobe width
      BUS_STROBE_WIDTH            : natural := 32/8;

      -- Random seed. This should be different for every instantiation if
      -- randomized handshake signals are used.
      SEED                        : positive := 1;

      -- Whether to randomize the request stream handshake timing.
      RANDOM_REQUEST_TIMING       : boolean := true;

      -- Whether to randomize the request stream handshake timing.
      RANDOM_RESPONSE_TIMING      : boolean := true;

      -- S-record file to dump writes. If not specified, the unit dumps the 
      -- writes on stdout
      SREC_FILE                   : string := ""

    );
    port (

      -- Rising-edge sensitive clock and active-high synchronous reset for the
      -- bus and control logic side of the BufferReader.
      clk                         : in  std_logic;
      reset                       : in  std_logic;

      -- Bus write interface.
      wreq_valid                  : in  std_logic;
      wreq_ready                  : out std_logic;
      wreq_addr                   : in  std_logic_vector(BUS_ADDR_WIDTH-1 downto 0);
      wreq_len                    : in  std_logic_vector(BUS_LEN_WIDTH-1 downto 0);
      wdat_valid                  : in  std_logic;
      wdat_ready                  : out std_logic;
      wdat_data                   : in  std_logic_vector(BUS_DATA_WIDTH-1 downto 0);
      wdat_strobe                 : in  std_logic_vector(BUS_STROBE_WIDTH-1 downto 0);
      wdat_last                   : in  std_logic;

      resp_valid                  : out std_logic;
      resp_ready                  : in  std_logic;
      resp_resp                   : out std_logic_vector(1 downto 0);

      -- Bus read interface.
      rreq_valid                  : in  std_logic;
      rreq_ready                  : out std_logic := '0';
      rreq_addr                   : in  std_logic_vector(BUS_ADDR_WIDTH-1 downto 0);
      rreq_len                    : in  std_logic_vector(BUS_LEN_WIDTH-1 downto 0);
      rdat_valid                  : out std_logic := '0';
      rdat_ready                  : in  std_logic;
      rdat_data                   : out std_logic_vector(BUS_DATA_WIDTH-1 downto 0);
      rdat_last                   : out std_logic

    );
  end component;

end AXI;
