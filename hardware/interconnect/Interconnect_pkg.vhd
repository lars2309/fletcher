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

library work;
use work.UtilInt_pkg.all;

package Interconnect_pkg is
  -----------------------------------------------------------------------------
  -- General address alignment requirements
  -----------------------------------------------------------------------------
  -- The burst boundary in bytes. Bursts will not cross this boundary unless
  -- burst lengths are set to something higher than this.
  -- This is currently set to the AXI4 specification of 4096 byte boundaries:
  constant BUS_BURST_BOUNDARY     : natural := 4096;

  -- Bus write data bits covered by single write strobe bit.
  -- This is currently set to the AXI4 specification of 1 byte / strobe bit.
  -- There is no practical reason why this should ever change.
  constant BUS_STROBE_COVER       : natural := 8;
  
  -----------------------------------------------------------------------------
  -- Bus devices
  -----------------------------------------------------------------------------
  component BusReadArbiterVec is
    generic (
      BUS_ADDR_WIDTH            : natural := 32;
      BUS_LEN_WIDTH             : natural := 8;
      BUS_DATA_WIDTH            : natural := 32;
      NUM_SLAVE_PORTS           : natural := 2;
      ARB_METHOD                : string  := "ROUND-ROBIN";
      MAX_OUTSTANDING           : natural := 2;
      RAM_CONFIG                : string  := "";
      SLV_REQ_SLICES            : boolean := true;
      MST_REQ_SLICE             : boolean := true;
      MST_DAT_SLICE             : boolean := true;
      SLV_DAT_SLICES            : boolean := true
    );
    port (
      bcd_clk                   : in  std_logic;
      bcd_reset                 : in  std_logic;

      mst_rreq_valid            : out std_logic;
      mst_rreq_ready            : in  std_logic;
      mst_rreq_addr             : out std_logic_vector(BUS_ADDR_WIDTH-1 downto 0);
      mst_rreq_len              : out std_logic_vector(BUS_LEN_WIDTH-1 downto 0);
      mst_rdat_valid            : in  std_logic;
      mst_rdat_ready            : out std_logic;
      mst_rdat_data             : in  std_logic_vector(BUS_DATA_WIDTH-1 downto 0);
      mst_rdat_last             : in  std_logic;

      bsv_rreq_valid            : in  std_logic_vector(NUM_SLAVE_PORTS-1 downto 0);
      bsv_rreq_ready            : out std_logic_vector(NUM_SLAVE_PORTS-1 downto 0);
      bsv_rreq_addr             : in  std_logic_vector(NUM_SLAVE_PORTS*BUS_ADDR_WIDTH-1 downto 0);
      bsv_rreq_len              : in  std_logic_vector(NUM_SLAVE_PORTS*BUS_LEN_WIDTH-1 downto 0);
      bsv_rdat_valid            : out std_logic_vector(NUM_SLAVE_PORTS-1 downto 0);
      bsv_rdat_ready            : in  std_logic_vector(NUM_SLAVE_PORTS-1 downto 0);
      bsv_rdat_data             : out std_logic_vector(NUM_SLAVE_PORTS*BUS_DATA_WIDTH-1 downto 0);
      bsv_rdat_last             : out std_logic_vector(NUM_SLAVE_PORTS-1 downto 0)
    );
  end component;

  component BusWriteArbiterVec is
    generic (
      BUS_ADDR_WIDTH            : natural := 32;
      BUS_LEN_WIDTH             : natural := 8;
      BUS_DATA_WIDTH            : natural := 32;
      BUS_STROBE_WIDTH          : natural := 32/8;
      NUM_SLAVE_PORTS           : natural := 2;
      ARB_METHOD                : string  := "ROUND-ROBIN";
      MAX_DATA_LAG              : natural := 2;
      MAX_OUTSTANDING           : natural := 2;
      RAM_CONFIG                : string  := "";
      SLV_REQ_SLICES            : boolean := true;
      MST_REQ_SLICE             : boolean := true;
      MST_DAT_SLICE             : boolean := true;
      SLV_DAT_SLICES            : boolean := true;
      MST_RSP_SLICE             : boolean := true;
      SLV_RSP_SLICES            : boolean := true
    );
    port (
      bcd_clk                   : in  std_logic;
      bcd_reset                 : in  std_logic;
      
      bsv_wreq_valid            : in  std_logic_vector(NUM_SLAVE_PORTS-1 downto 0);
      bsv_wreq_ready            : out std_logic_vector(NUM_SLAVE_PORTS-1 downto 0);
      bsv_wreq_addr             : in  std_logic_vector(NUM_SLAVE_PORTS*BUS_ADDR_WIDTH-1 downto 0);
      bsv_wreq_len              : in  std_logic_vector(NUM_SLAVE_PORTS*BUS_LEN_WIDTH-1 downto 0);
      bsv_wdat_valid            : in  std_logic_vector(NUM_SLAVE_PORTS-1 downto 0);
      bsv_wdat_ready            : out std_logic_vector(NUM_SLAVE_PORTS-1 downto 0);
      bsv_wdat_data             : in  std_logic_vector(NUM_SLAVE_PORTS*BUS_DATA_WIDTH-1 downto 0);
      bsv_wdat_strobe           : in  std_logic_vector(NUM_SLAVE_PORTS*BUS_STROBE_WIDTH-1 downto 0);
      bsv_wdat_last             : in  std_logic_vector(NUM_SLAVE_PORTS-1 downto 0);
      bsv_resp_valid            : out std_logic_vector(NUM_SLAVE_PORTS-1 downto 0);
      bsv_resp_ready            : in  std_logic_vector(NUM_SLAVE_PORTS-1 downto 0) := (others => '1');
      bsv_resp_ok               : out std_logic_vector(NUM_SLAVE_PORTS-1 downto 0);
      
      mst_wreq_valid            : out std_logic;
      mst_wreq_ready            : in  std_logic;
      mst_wreq_addr             : out std_logic_vector(BUS_ADDR_WIDTH-1 downto 0);
      mst_wreq_len              : out std_logic_vector(BUS_LEN_WIDTH-1 downto 0);
      mst_wdat_valid            : out std_logic;
      mst_wdat_ready            : in  std_logic;
      mst_wdat_data             : out std_logic_vector(BUS_DATA_WIDTH-1 downto 0);
      mst_wdat_strobe           : out std_logic_vector(BUS_STROBE_WIDTH-1 downto 0);
      mst_wdat_last             : out std_logic;
      mst_resp_valid            : in  std_logic := '0';
      mst_resp_ready            : out std_logic;
      mst_resp_ok               : in  std_logic := 'U'
    );
  end component;

  component BusReadBuffer is
    generic (
      BUS_ADDR_WIDTH            : natural;
      BUS_LEN_WIDTH             : natural;
      BUS_DATA_WIDTH            : natural;
      FIFO_DEPTH                : natural;
      RAM_CONFIG                : string;
      SLV_REQ_SLICE             : boolean := true;
      MST_REQ_SLICE             : boolean := true;
      MST_DAT_SLICE             : boolean := true;
      SLV_DAT_SLICE             : boolean := true
    );
    port (
      clk                       : in  std_logic;
      reset                     : in  std_logic;

      slv_rreq_valid            : in  std_logic;
      slv_rreq_ready            : out std_logic;
      slv_rreq_addr             : in  std_logic_vector(BUS_ADDR_WIDTH-1 downto 0);
      slv_rreq_len              : in  std_logic_vector(BUS_LEN_WIDTH-1 downto 0);
      slv_rdat_valid            : out std_logic;
      slv_rdat_ready            : in  std_logic;
      slv_rdat_data             : out std_logic_vector(BUS_DATA_WIDTH-1 downto 0);
      slv_rdat_last             : out std_logic;

      mst_rreq_valid            : out std_logic;
      mst_rreq_ready            : in  std_logic;
      mst_rreq_addr             : out std_logic_vector(BUS_ADDR_WIDTH-1 downto 0);
      mst_rreq_len              : out std_logic_vector(BUS_LEN_WIDTH-1 downto 0);
      mst_rdat_valid            : in  std_logic;
      mst_rdat_ready            : out std_logic;
      mst_rdat_data             : in  std_logic_vector(BUS_DATA_WIDTH-1 downto 0);
      mst_rdat_last             : in  std_logic
    );
  end component;

  component BusWriteBuffer is
    generic (
      BUS_ADDR_WIDTH            : natural;
      BUS_LEN_WIDTH             : natural;
      BUS_DATA_WIDTH            : natural;
      BUS_STROBE_WIDTH          : natural;
      CTRL_WIDTH                : natural := 1;
      FIFO_DEPTH                : natural;
      LEN_SHIFT                 : natural := 0;
      RAM_CONFIG                : string  := "";
      SLV_LAST_MODE             : string  := "burst";
      SLV_REQ_SLICE             : boolean := true;
      MST_REQ_SLICE             : boolean := true;
      SLV_DAT_SLICE             : boolean := true;
      MST_DAT_SLICE             : boolean := true
    );
    port (
      clk                       : in  std_logic;
      reset                     : in  std_logic;
      full                      : out std_logic;
      empty                     : out std_logic;
      count                     : out std_logic_vector(log2ceil(FIFO_DEPTH) downto 0);
      
      slv_wreq_valid            : in  std_logic;
      slv_wreq_ready            : out std_logic;
      slv_wreq_addr             : in  std_logic_vector(BUS_ADDR_WIDTH-1 downto 0);
      slv_wreq_len              : in  std_logic_vector(BUS_LEN_WIDTH-1 downto 0);
      slv_wdat_valid            : in  std_logic;
      slv_wdat_ready            : out std_logic;
      slv_wdat_data             : in  std_logic_vector(BUS_DATA_WIDTH-1 downto 0);
      slv_wdat_strobe           : in  std_logic_vector(BUS_STROBE_WIDTH-1 downto 0);
      slv_wdat_ctrl             : in  std_logic_vector(CTRL_WIDTH-1 downto 0)  := (others => 'U');
      slv_wdat_last             : in  std_logic;
      
      mst_wreq_valid            : out std_logic;
      mst_wreq_ready            : in  std_logic;
      mst_wreq_addr             : out std_logic_vector(BUS_ADDR_WIDTH-1 downto 0);
      mst_wreq_len              : out std_logic_vector(BUS_LEN_WIDTH-1 downto 0);
      mst_wdat_valid            : out std_logic;
      mst_wdat_ready            : in  std_logic;
      mst_wdat_data             : out std_logic_vector(BUS_DATA_WIDTH-1 downto 0);
      mst_wdat_strobe           : out std_logic_vector(BUS_STROBE_WIDTH-1 downto 0);
      mst_wdat_ctrl             : out std_logic_vector(CTRL_WIDTH-1 downto 0);
      mst_wdat_last             : out std_logic
    );
  end component;

  component BusReadBenchmarker is
    generic (
      BUS_ADDR_WIDTH              : natural := 64;
      BUS_DATA_WIDTH              : natural := 512;
      BUS_LEN_WIDTH               : natural := 9;
      BUS_MAX_BURST_LENGTH        : natural := 64;
      BUS_BURST_BOUNDARY          : natural := 4096;
      PATTERN                     : string := "RANDOM"
    );
    port (
      bcd_clk                     : in  std_logic;
      bcd_reset                   : in  std_logic;
      bus_rreq_valid              : out std_logic;
      bus_rreq_ready              : in  std_logic;
      bus_rreq_addr               : out std_logic_vector(BUS_ADDR_WIDTH-1 downto 0);
      bus_rreq_len                : out std_logic_vector(BUS_LEN_WIDTH-1 downto 0);
      bus_rdat_valid              : in  std_logic;
      bus_rdat_ready              : out std_logic;
      bus_rdat_data               : in  std_logic_vector(BUS_DATA_WIDTH-1 downto 0);
      bus_rdat_last               : in  std_logic;
      reg_control                 : in  std_logic_vector(31 downto 0);
      reg_status                  : out std_logic_vector(31 downto 0);
      reg_burst_length            : in  std_logic_vector(31 downto 0);
      reg_max_bursts              : in  std_logic_vector(31 downto 0);
      reg_base_addr_lo            : in  std_logic_vector(31 downto 0);
      reg_base_addr_hi            : in  std_logic_vector(31 downto 0);
      reg_addr_mask_lo            : in  std_logic_vector(31 downto 0);
      reg_addr_mask_hi            : in  std_logic_vector(31 downto 0);
      reg_cycles_per_word         : in  std_logic_vector(31 downto 0);
      reg_cycles                  : out std_logic_vector(31 downto 0);
      reg_checksum                : out std_logic_vector(31 downto 0)
    );
  end component;

  component BusWriteBenchmarker is
    generic (
      BUS_ADDR_WIDTH              : natural := 64;
      BUS_DATA_WIDTH              : natural := 512;
      BUS_LEN_WIDTH               : natural := 9;
      BUS_MAX_BURST_LENGTH        : natural := 64;
      BUS_BURST_BOUNDARY          : natural := 4096;
      PATTERN                     : string := "RANDOM"
    );
    port (
      bcd_clk                     : in  std_logic;
      bcd_reset                   : in  std_logic;

      bus_wreq_valid              : out std_logic;
      bus_wreq_ready              : in  std_logic;
      bus_wreq_addr               : out std_logic_vector(BUS_ADDR_WIDTH-1 downto 0);
      bus_wreq_len                : out std_logic_vector(BUS_LEN_WIDTH-1 downto 0);
      bus_wdat_valid              : out std_logic;
      bus_wdat_ready              : in  std_logic;
      bus_wdat_data               : out std_logic_vector(BUS_DATA_WIDTH-1 downto 0);
      bus_wdat_last               : out std_logic;
      
      -- Control / status registers
      reg_control                 : in  std_logic_vector(31 downto 0);
      reg_status                  : out std_logic_vector(31 downto 0);

      -- Configuration registers
      
      -- Burst length
      reg_burst_length            : in  std_logic_vector(31 downto 0);
      
      -- Maximum number of bursts
      reg_max_bursts              : in  std_logic_vector(31 downto 0);
      
      -- Base addresse
      reg_base_addr_lo            : in  std_logic_vector(31 downto 0);
      reg_base_addr_hi            : in  std_logic_vector(31 downto 0);
      
      -- Address mask
      reg_addr_mask_lo            : in  std_logic_vector(31 downto 0);
      reg_addr_mask_hi            : in  std_logic_vector(31 downto 0);
      
      -- Number of cycles to absorb a word, set 0 to always accept immediately
      reg_cycles_per_word         : in  std_logic_vector(31 downto 0);

      -- Result registers
      reg_cycles                  : out std_logic_vector(31 downto 0);
      reg_checksum                : out std_logic_vector(31 downto 0)
    );
  end component;

  component BusReadArbiter is
    generic (
      BUS_ADDR_WIDTH            : natural := 32;
      BUS_LEN_WIDTH             : natural := 8;
      BUS_DATA_WIDTH            : natural := 32;
      NUM_SLAVE_PORTS           : natural := 2;
      ARB_METHOD                : string  := "ROUND-ROBIN";
      MAX_OUTSTANDING           : natural := 2;
      RAM_CONFIG                : string  := "";
      SLV_REQ_SLICES            : boolean := true;
      MST_REQ_SLICE             : boolean := true;
      MST_DAT_SLICE             : boolean := true;
      SLV_DAT_SLICES            : boolean := true
    );
    port (
      bcd_clk                   : in  std_logic;
      bcd_reset                 : in  std_logic;

      mst_rreq_valid            : out std_logic;
      mst_rreq_ready            : in  std_logic;
      mst_rreq_addr             : out std_logic_vector(BUS_ADDR_WIDTH-1 downto 0);
      mst_rreq_len              : out std_logic_vector(BUS_LEN_WIDTH-1 downto 0);
      mst_rdat_valid            : in  std_logic;
      mst_rdat_ready            : out std_logic;
      mst_rdat_data             : in  std_logic_vector(BUS_DATA_WIDTH-1 downto 0);
      mst_rdat_last             : in  std_logic;

      -- Ph'nglui mglw'nafh Cthulhu R'lyeh wgah'nagl fhtagn

      bs00_rreq_valid           : in  std_logic := '0';
      bs00_rreq_ready           : out std_logic;
      bs00_rreq_addr            : in  std_logic_vector(BUS_ADDR_WIDTH-1 downto 0) := (others => '0');
      bs00_rreq_len             : in  std_logic_vector(BUS_LEN_WIDTH-1 downto 0) := (others => '0');
      bs00_rdat_valid           : out std_logic;
      bs00_rdat_ready           : in  std_logic := '1';
      bs00_rdat_data            : out std_logic_vector(BUS_DATA_WIDTH-1 downto 0);
      bs00_rdat_last            : out std_logic;

      bs01_rreq_valid           : in  std_logic := '0';
      bs01_rreq_ready           : out std_logic;
      bs01_rreq_addr            : in  std_logic_vector(BUS_ADDR_WIDTH-1 downto 0) := (others => '0');
      bs01_rreq_len             : in  std_logic_vector(BUS_LEN_WIDTH-1 downto 0) := (others => '0');
      bs01_rdat_valid           : out std_logic;
      bs01_rdat_ready           : in  std_logic := '1';
      bs01_rdat_data            : out std_logic_vector(BUS_DATA_WIDTH-1 downto 0);
      bs01_rdat_last            : out std_logic;

      bs02_rreq_valid           : in  std_logic := '0';
      bs02_rreq_ready           : out std_logic;
      bs02_rreq_addr            : in  std_logic_vector(BUS_ADDR_WIDTH-1 downto 0) := (others => '0');
      bs02_rreq_len             : in  std_logic_vector(BUS_LEN_WIDTH-1 downto 0) := (others => '0');
      bs02_rdat_valid           : out std_logic;
      bs02_rdat_ready           : in  std_logic := '1';
      bs02_rdat_data            : out std_logic_vector(BUS_DATA_WIDTH-1 downto 0);
      bs02_rdat_last            : out std_logic;

      bs03_rreq_valid           : in  std_logic := '0';
      bs03_rreq_ready           : out std_logic;
      bs03_rreq_addr            : in  std_logic_vector(BUS_ADDR_WIDTH-1 downto 0) := (others => '0');
      bs03_rreq_len             : in  std_logic_vector(BUS_LEN_WIDTH-1 downto 0) := (others => '0');
      bs03_rdat_valid           : out std_logic;
      bs03_rdat_ready           : in  std_logic := '1';
      bs03_rdat_data            : out std_logic_vector(BUS_DATA_WIDTH-1 downto 0);
      bs03_rdat_last            : out std_logic;

      bs04_rreq_valid           : in  std_logic := '0';
      bs04_rreq_ready           : out std_logic;
      bs04_rreq_addr            : in  std_logic_vector(BUS_ADDR_WIDTH-1 downto 0) := (others => '0');
      bs04_rreq_len             : in  std_logic_vector(BUS_LEN_WIDTH-1 downto 0) := (others => '0');
      bs04_rdat_valid           : out std_logic;
      bs04_rdat_ready           : in  std_logic := '1';
      bs04_rdat_data            : out std_logic_vector(BUS_DATA_WIDTH-1 downto 0);
      bs04_rdat_last            : out std_logic;

      bs05_rreq_valid           : in  std_logic := '0';
      bs05_rreq_ready           : out std_logic;
      bs05_rreq_addr            : in  std_logic_vector(BUS_ADDR_WIDTH-1 downto 0) := (others => '0');
      bs05_rreq_len             : in  std_logic_vector(BUS_LEN_WIDTH-1 downto 0) := (others => '0');
      bs05_rdat_valid           : out std_logic;
      bs05_rdat_ready           : in  std_logic := '1';
      bs05_rdat_data            : out std_logic_vector(BUS_DATA_WIDTH-1 downto 0);
      bs05_rdat_last            : out std_logic;

      bs06_rreq_valid           : in  std_logic := '0';
      bs06_rreq_ready           : out std_logic;
      bs06_rreq_addr            : in  std_logic_vector(BUS_ADDR_WIDTH-1 downto 0) := (others => '0');
      bs06_rreq_len             : in  std_logic_vector(BUS_LEN_WIDTH-1 downto 0) := (others => '0');
      bs06_rdat_valid           : out std_logic;
      bs06_rdat_ready           : in  std_logic := '1';
      bs06_rdat_data            : out std_logic_vector(BUS_DATA_WIDTH-1 downto 0);
      bs06_rdat_last            : out std_logic;

      bs07_rreq_valid           : in  std_logic := '0';
      bs07_rreq_ready           : out std_logic;
      bs07_rreq_addr            : in  std_logic_vector(BUS_ADDR_WIDTH-1 downto 0) := (others => '0');
      bs07_rreq_len             : in  std_logic_vector(BUS_LEN_WIDTH-1 downto 0) := (others => '0');
      bs07_rdat_valid           : out std_logic;
      bs07_rdat_ready           : in  std_logic := '1';
      bs07_rdat_data            : out std_logic_vector(BUS_DATA_WIDTH-1 downto 0);
      bs07_rdat_last            : out std_logic;

      bs08_rreq_valid           : in  std_logic := '0';
      bs08_rreq_ready           : out std_logic;
      bs08_rreq_addr            : in  std_logic_vector(BUS_ADDR_WIDTH-1 downto 0) := (others => '0');
      bs08_rreq_len             : in  std_logic_vector(BUS_LEN_WIDTH-1 downto 0) := (others => '0');
      bs08_rdat_valid           : out std_logic;
      bs08_rdat_ready           : in  std_logic := '1';
      bs08_rdat_data            : out std_logic_vector(BUS_DATA_WIDTH-1 downto 0);
      bs08_rdat_last            : out std_logic;

      bs09_rreq_valid           : in  std_logic := '0';
      bs09_rreq_ready           : out std_logic;
      bs09_rreq_addr            : in  std_logic_vector(BUS_ADDR_WIDTH-1 downto 0) := (others => '0');
      bs09_rreq_len             : in  std_logic_vector(BUS_LEN_WIDTH-1 downto 0) := (others => '0');
      bs09_rdat_valid           : out std_logic;
      bs09_rdat_ready           : in  std_logic := '1';
      bs09_rdat_data            : out std_logic_vector(BUS_DATA_WIDTH-1 downto 0);
      bs09_rdat_last            : out std_logic;

      bs10_rreq_valid           : in  std_logic := '0';
      bs10_rreq_ready           : out std_logic;
      bs10_rreq_addr            : in  std_logic_vector(BUS_ADDR_WIDTH-1 downto 0) := (others => '0');
      bs10_rreq_len             : in  std_logic_vector(BUS_LEN_WIDTH-1 downto 0) := (others => '0');
      bs10_rdat_valid           : out std_logic;
      bs10_rdat_ready           : in  std_logic := '1';
      bs10_rdat_data            : out std_logic_vector(BUS_DATA_WIDTH-1 downto 0);
      bs10_rdat_last            : out std_logic;

      bs11_rreq_valid           : in  std_logic := '0';
      bs11_rreq_ready           : out std_logic;
      bs11_rreq_addr            : in  std_logic_vector(BUS_ADDR_WIDTH-1 downto 0) := (others => '0');
      bs11_rreq_len             : in  std_logic_vector(BUS_LEN_WIDTH-1 downto 0) := (others => '0');
      bs11_rdat_valid           : out std_logic;
      bs11_rdat_ready           : in  std_logic := '1';
      bs11_rdat_data            : out std_logic_vector(BUS_DATA_WIDTH-1 downto 0);
      bs11_rdat_last            : out std_logic;

      bs12_rreq_valid           : in  std_logic := '0';
      bs12_rreq_ready           : out std_logic;
      bs12_rreq_addr            : in  std_logic_vector(BUS_ADDR_WIDTH-1 downto 0) := (others => '0');
      bs12_rreq_len             : in  std_logic_vector(BUS_LEN_WIDTH-1 downto 0) := (others => '0');
      bs12_rdat_valid           : out std_logic;
      bs12_rdat_ready           : in  std_logic := '1';
      bs12_rdat_data            : out std_logic_vector(BUS_DATA_WIDTH-1 downto 0);
      bs12_rdat_last            : out std_logic;

      bs13_rreq_valid           : in  std_logic := '0';
      bs13_rreq_ready           : out std_logic;
      bs13_rreq_addr            : in  std_logic_vector(BUS_ADDR_WIDTH-1 downto 0) := (others => '0');
      bs13_rreq_len             : in  std_logic_vector(BUS_LEN_WIDTH-1 downto 0) := (others => '0');
      bs13_rdat_valid           : out std_logic;
      bs13_rdat_ready           : in  std_logic := '1';
      bs13_rdat_data            : out std_logic_vector(BUS_DATA_WIDTH-1 downto 0);
      bs13_rdat_last            : out std_logic;

      bs14_rreq_valid           : in  std_logic := '0';
      bs14_rreq_ready           : out std_logic;
      bs14_rreq_addr            : in  std_logic_vector(BUS_ADDR_WIDTH-1 downto 0) := (others => '0');
      bs14_rreq_len             : in  std_logic_vector(BUS_LEN_WIDTH-1 downto 0) := (others => '0');
      bs14_rdat_valid           : out std_logic;
      bs14_rdat_ready           : in  std_logic := '1';
      bs14_rdat_data            : out std_logic_vector(BUS_DATA_WIDTH-1 downto 0);
      bs14_rdat_last            : out std_logic;

      bs15_rreq_valid           : in  std_logic := '0';
      bs15_rreq_ready           : out std_logic;
      bs15_rreq_addr            : in  std_logic_vector(BUS_ADDR_WIDTH-1 downto 0) := (others => '0');
      bs15_rreq_len             : in  std_logic_vector(BUS_LEN_WIDTH-1 downto 0) := (others => '0');
      bs15_rdat_valid           : out std_logic;
      bs15_rdat_ready           : in  std_logic := '1';
      bs15_rdat_data            : out std_logic_vector(BUS_DATA_WIDTH-1 downto 0);
      bs15_rdat_last            : out std_logic
    );
  end component;

  component BusWriteArbiter is
    generic (
      BUS_ADDR_WIDTH            : natural := 32;
      BUS_LEN_WIDTH             : natural := 8;
      BUS_DATA_WIDTH            : natural := 32;
      BUS_STROBE_WIDTH          : natural := 32/8;
      NUM_SLAVE_PORTS           : natural := 2;
      ARB_METHOD                : string := "ROUND-ROBIN";
      MAX_DATA_LAG              : natural := 2;
      MAX_OUTSTANDING           : natural := 2;
      RAM_CONFIG                : string := "";
      SLV_REQ_SLICES            : boolean := true;
      MST_REQ_SLICE             : boolean := true;
      MST_DAT_SLICE             : boolean := true;
      SLV_DAT_SLICES            : boolean := true;
      MST_RSP_SLICE             : boolean := true;
      SLV_RSP_SLICES            : boolean := true
    );
    port (
      bcd_clk                   : in  std_logic;
      bcd_reset                 : in  std_logic;

      mst_wreq_valid            : out std_logic;
      mst_wreq_ready            : in  std_logic;
      mst_wreq_addr             : out std_logic_vector(BUS_ADDR_WIDTH-1 downto 0);
      mst_wreq_len              : out std_logic_vector(BUS_LEN_WIDTH-1 downto 0);
      mst_wdat_valid            : out std_logic;
      mst_wdat_ready            : in  std_logic;
      mst_wdat_data             : out std_logic_vector(BUS_DATA_WIDTH-1 downto 0);
      mst_wdat_strobe           : out std_logic_vector(BUS_STROBE_WIDTH-1 downto 0);
      mst_wdat_last             : out std_logic;
      mst_resp_valid            : in  std_logic := '0';
      mst_resp_ready            : out std_logic;
      mst_resp_ok               : in  std_logic := 'U';

      -- Ph'nglui mglw'nafh Cthulhu R'lyeh wgah'nagl fhtagn

      bs00_wreq_valid           : in  std_logic := '0';
      bs00_wreq_ready           : out std_logic;
      bs00_wreq_addr            : in  std_logic_vector(BUS_ADDR_WIDTH-1 downto 0) := (others => '0');
      bs00_wreq_len             : in  std_logic_vector(BUS_LEN_WIDTH-1 downto 0) := (others => '0');
      bs00_wdat_valid           : in  std_logic := '0';
      bs00_wdat_ready           : out std_logic := '1';
      bs00_wdat_data            : in  std_logic_vector(BUS_DATA_WIDTH-1 downto 0) := (others => 'U');
      bs00_wdat_strobe          : in  std_logic_vector(BUS_STROBE_WIDTH-1 downto 0) := (others => 'U');
      bs00_wdat_last            : in  std_logic := 'U';
      bs00_resp_valid           : out std_logic;
      bs00_resp_ready           : in  std_logic := '1';
      bs00_resp_ok              : out std_logic;

      bs01_wreq_valid           : in  std_logic := '0';
      bs01_wreq_ready           : out std_logic;
      bs01_wreq_addr            : in  std_logic_vector(BUS_ADDR_WIDTH-1 downto 0) := (others => '0');
      bs01_wreq_len             : in  std_logic_vector(BUS_LEN_WIDTH-1 downto 0) := (others => '0');
      bs01_wdat_valid           : in  std_logic := '0';
      bs01_wdat_ready           : out std_logic := '1';
      bs01_wdat_data            : in  std_logic_vector(BUS_DATA_WIDTH-1 downto 0) := (others => 'U');
      bs01_wdat_strobe          : in  std_logic_vector(BUS_STROBE_WIDTH-1 downto 0) := (others => 'U');
      bs01_wdat_last            : in  std_logic := 'U';
      bs01_resp_valid           : out std_logic;
      bs01_resp_ready           : in  std_logic := '1';
      bs01_resp_ok              : out std_logic;

      bs02_wreq_valid           : in  std_logic := '0';
      bs02_wreq_ready           : out std_logic;
      bs02_wreq_addr            : in  std_logic_vector(BUS_ADDR_WIDTH-1 downto 0) := (others => '0');
      bs02_wreq_len             : in  std_logic_vector(BUS_LEN_WIDTH-1 downto 0) := (others => '0');
      bs02_wdat_valid           : in  std_logic := '0';
      bs02_wdat_ready           : out std_logic := '1';
      bs02_wdat_data            : in  std_logic_vector(BUS_DATA_WIDTH-1 downto 0) := (others => 'U');
      bs02_wdat_strobe          : in  std_logic_vector(BUS_STROBE_WIDTH-1 downto 0) := (others => 'U');
      bs02_wdat_last            : in  std_logic := 'U';
      bs02_resp_valid           : out std_logic;
      bs02_resp_ready           : in  std_logic := '1';
      bs02_resp_ok              : out std_logic;

      bs03_wreq_valid           : in  std_logic := '0';
      bs03_wreq_ready           : out std_logic;
      bs03_wreq_addr            : in  std_logic_vector(BUS_ADDR_WIDTH-1 downto 0) := (others => '0');
      bs03_wreq_len             : in  std_logic_vector(BUS_LEN_WIDTH-1 downto 0) := (others => '0');
      bs03_wdat_valid           : in  std_logic := '0';
      bs03_wdat_ready           : out std_logic := '1';
      bs03_wdat_data            : in  std_logic_vector(BUS_DATA_WIDTH-1 downto 0) := (others => 'U');
      bs03_wdat_strobe          : in  std_logic_vector(BUS_STROBE_WIDTH-1 downto 0) := (others => 'U');
      bs03_wdat_last            : in  std_logic := 'U';
      bs03_resp_valid           : out std_logic;
      bs03_resp_ready           : in  std_logic := '1';
      bs03_resp_ok              : out std_logic;

      bs04_wreq_valid           : in  std_logic := '0';
      bs04_wreq_ready           : out std_logic;
      bs04_wreq_addr            : in  std_logic_vector(BUS_ADDR_WIDTH-1 downto 0) := (others => '0');
      bs04_wreq_len             : in  std_logic_vector(BUS_LEN_WIDTH-1 downto 0) := (others => '0');
      bs04_wdat_valid           : in  std_logic := '0';
      bs04_wdat_ready           : out std_logic := '1';
      bs04_wdat_data            : in  std_logic_vector(BUS_DATA_WIDTH-1 downto 0) := (others => 'U');
      bs04_wdat_strobe          : in  std_logic_vector(BUS_STROBE_WIDTH-1 downto 0) := (others => 'U');
      bs04_wdat_last            : in  std_logic := 'U';
      bs04_resp_valid           : out std_logic;
      bs04_resp_ready           : in  std_logic := '1';
      bs04_resp_ok              : out std_logic;

      bs05_wreq_valid           : in  std_logic := '0';
      bs05_wreq_ready           : out std_logic;
      bs05_wreq_addr            : in  std_logic_vector(BUS_ADDR_WIDTH-1 downto 0) := (others => '0');
      bs05_wreq_len             : in  std_logic_vector(BUS_LEN_WIDTH-1 downto 0) := (others => '0');
      bs05_wdat_valid           : in  std_logic := '0';
      bs05_wdat_ready           : out std_logic := '1';
      bs05_wdat_data            : in  std_logic_vector(BUS_DATA_WIDTH-1 downto 0) := (others => 'U');
      bs05_wdat_strobe          : in  std_logic_vector(BUS_STROBE_WIDTH-1 downto 0) := (others => 'U');
      bs05_wdat_last            : in  std_logic := 'U';
      bs05_resp_valid           : out std_logic;
      bs05_resp_ready           : in  std_logic := '1';
      bs05_resp_ok              : out std_logic;

      bs06_wreq_valid           : in  std_logic := '0';
      bs06_wreq_ready           : out std_logic;
      bs06_wreq_addr            : in  std_logic_vector(BUS_ADDR_WIDTH-1 downto 0) := (others => '0');
      bs06_wreq_len             : in  std_logic_vector(BUS_LEN_WIDTH-1 downto 0) := (others => '0');
      bs06_wdat_valid           : in  std_logic := '0';
      bs06_wdat_ready           : out std_logic := '1';
      bs06_wdat_data            : in  std_logic_vector(BUS_DATA_WIDTH-1 downto 0) := (others => 'U');
      bs06_wdat_strobe          : in  std_logic_vector(BUS_STROBE_WIDTH-1 downto 0) := (others => 'U');
      bs06_wdat_last            : in  std_logic := 'U';
      bs06_resp_valid           : out std_logic;
      bs06_resp_ready           : in  std_logic := '1';
      bs06_resp_ok              : out std_logic;

      bs07_wreq_valid           : in  std_logic := '0';
      bs07_wreq_ready           : out std_logic;
      bs07_wreq_addr            : in  std_logic_vector(BUS_ADDR_WIDTH-1 downto 0) := (others => '0');
      bs07_wreq_len             : in  std_logic_vector(BUS_LEN_WIDTH-1 downto 0) := (others => '0');
      bs07_wdat_valid           : in  std_logic := '0';
      bs07_wdat_ready           : out std_logic := '1';
      bs07_wdat_data            : in  std_logic_vector(BUS_DATA_WIDTH-1 downto 0) := (others => 'U');
      bs07_wdat_strobe          : in  std_logic_vector(BUS_STROBE_WIDTH-1 downto 0) := (others => 'U');
      bs07_wdat_last            : in  std_logic := 'U';
      bs07_resp_valid           : out std_logic;
      bs07_resp_ready           : in  std_logic := '1';
      bs07_resp_ok              : out std_logic;

      bs08_wreq_valid           : in  std_logic := '0';
      bs08_wreq_ready           : out std_logic;
      bs08_wreq_addr            : in  std_logic_vector(BUS_ADDR_WIDTH-1 downto 0) := (others => '0');
      bs08_wreq_len             : in  std_logic_vector(BUS_LEN_WIDTH-1 downto 0) := (others => '0');
      bs08_wdat_valid           : in  std_logic := '0';
      bs08_wdat_ready           : out std_logic := '1';
      bs08_wdat_data            : in  std_logic_vector(BUS_DATA_WIDTH-1 downto 0) := (others => 'U');
      bs08_wdat_strobe          : in  std_logic_vector(BUS_STROBE_WIDTH-1 downto 0) := (others => 'U');
      bs08_wdat_last            : in  std_logic := 'U';
      bs08_resp_valid           : out std_logic;
      bs08_resp_ready           : in  std_logic := '1';
      bs08_resp_ok              : out std_logic;

      bs09_wreq_valid           : in  std_logic := '0';
      bs09_wreq_ready           : out std_logic;
      bs09_wreq_addr            : in  std_logic_vector(BUS_ADDR_WIDTH-1 downto 0) := (others => '0');
      bs09_wreq_len             : in  std_logic_vector(BUS_LEN_WIDTH-1 downto 0) := (others => '0');
      bs09_wdat_valid           : in  std_logic := '0';
      bs09_wdat_ready           : out std_logic := '1';
      bs09_wdat_data            : in  std_logic_vector(BUS_DATA_WIDTH-1 downto 0) := (others => 'U');
      bs09_wdat_strobe          : in  std_logic_vector(BUS_STROBE_WIDTH-1 downto 0) := (others => 'U');
      bs09_wdat_last            : in  std_logic := 'U';
      bs09_resp_valid           : out std_logic;
      bs09_resp_ready           : in  std_logic := '1';
      bs09_resp_ok              : out std_logic;

      bs10_wreq_valid           : in  std_logic := '0';
      bs10_wreq_ready           : out std_logic;
      bs10_wreq_addr            : in  std_logic_vector(BUS_ADDR_WIDTH-1 downto 0) := (others => '0');
      bs10_wreq_len             : in  std_logic_vector(BUS_LEN_WIDTH-1 downto 0) := (others => '0');
      bs10_wdat_valid           : in  std_logic := '0';
      bs10_wdat_ready           : out std_logic := '1';
      bs10_wdat_data            : in  std_logic_vector(BUS_DATA_WIDTH-1 downto 0) := (others => 'U');
      bs10_wdat_strobe          : in  std_logic_vector(BUS_STROBE_WIDTH-1 downto 0) := (others => 'U');
      bs10_wdat_last            : in  std_logic := 'U';
      bs10_resp_valid           : out std_logic;
      bs10_resp_ready           : in  std_logic := '1';
      bs10_resp_ok              : out std_logic;

      bs11_wreq_valid           : in  std_logic := '0';
      bs11_wreq_ready           : out std_logic;
      bs11_wreq_addr            : in  std_logic_vector(BUS_ADDR_WIDTH-1 downto 0) := (others => '0');
      bs11_wreq_len             : in  std_logic_vector(BUS_LEN_WIDTH-1 downto 0) := (others => '0');
      bs11_wdat_valid           : in  std_logic := '0';
      bs11_wdat_ready           : out std_logic := '1';
      bs11_wdat_data            : in  std_logic_vector(BUS_DATA_WIDTH-1 downto 0) := (others => 'U');
      bs11_wdat_strobe          : in  std_logic_vector(BUS_STROBE_WIDTH-1 downto 0) := (others => 'U');
      bs11_wdat_last            : in  std_logic := 'U';
      bs11_resp_valid           : out std_logic;
      bs11_resp_ready           : in  std_logic := '1';
      bs11_resp_ok              : out std_logic;

      bs12_wreq_valid           : in  std_logic := '0';
      bs12_wreq_ready           : out std_logic;
      bs12_wreq_addr            : in  std_logic_vector(BUS_ADDR_WIDTH-1 downto 0) := (others => '0');
      bs12_wreq_len             : in  std_logic_vector(BUS_LEN_WIDTH-1 downto 0) := (others => '0');
      bs12_wdat_valid           : in  std_logic := '0';
      bs12_wdat_ready           : out std_logic := '1';
      bs12_wdat_data            : in  std_logic_vector(BUS_DATA_WIDTH-1 downto 0) := (others => 'U');
      bs12_wdat_strobe          : in  std_logic_vector(BUS_STROBE_WIDTH-1 downto 0) := (others => 'U');
      bs12_wdat_last            : in  std_logic := 'U';
      bs12_resp_valid           : out std_logic;
      bs12_resp_ready           : in  std_logic := '1';
      bs12_resp_ok              : out std_logic;

      bs13_wreq_valid           : in  std_logic := '0';
      bs13_wreq_ready           : out std_logic;
      bs13_wreq_addr            : in  std_logic_vector(BUS_ADDR_WIDTH-1 downto 0) := (others => '0');
      bs13_wreq_len             : in  std_logic_vector(BUS_LEN_WIDTH-1 downto 0) := (others => '0');
      bs13_wdat_valid           : in  std_logic := '0';
      bs13_wdat_ready           : out std_logic := '1';
      bs13_wdat_data            : in  std_logic_vector(BUS_DATA_WIDTH-1 downto 0) := (others => 'U');
      bs13_wdat_strobe          : in  std_logic_vector(BUS_STROBE_WIDTH-1 downto 0) := (others => 'U');
      bs13_wdat_last            : in  std_logic := 'U';
      bs13_resp_valid           : out std_logic;
      bs13_resp_ready           : in  std_logic := '1';
      bs13_resp_ok              : out std_logic;

      bs14_wreq_valid           : in  std_logic := '0';
      bs14_wreq_ready           : out std_logic;
      bs14_wreq_addr            : in  std_logic_vector(BUS_ADDR_WIDTH-1 downto 0) := (others => '0');
      bs14_wreq_len             : in  std_logic_vector(BUS_LEN_WIDTH-1 downto 0) := (others => '0');
      bs14_wdat_valid           : in  std_logic := '0';
      bs14_wdat_ready           : out std_logic := '1';
      bs14_wdat_data            : in  std_logic_vector(BUS_DATA_WIDTH-1 downto 0) := (others => 'U');
      bs14_wdat_strobe          : in  std_logic_vector(BUS_STROBE_WIDTH-1 downto 0) := (others => 'U');
      bs14_wdat_last            : in  std_logic := 'U';
      bs14_resp_valid           : out std_logic;
      bs14_resp_ready           : in  std_logic := '1';
      bs14_resp_ok              : out std_logic;

      bs15_wreq_valid           : in  std_logic := '0';
      bs15_wreq_ready           : out std_logic;
      bs15_wreq_addr            : in  std_logic_vector(BUS_ADDR_WIDTH-1 downto 0) := (others => '0');
      bs15_wreq_len             : in  std_logic_vector(BUS_LEN_WIDTH-1 downto 0) := (others => '0');
      bs15_wdat_valid           : in  std_logic := '0';
      bs15_wdat_ready           : out std_logic := '1';
      bs15_wdat_data            : in  std_logic_vector(BUS_DATA_WIDTH-1 downto 0) := (others => 'U');
      bs15_wdat_strobe          : in  std_logic_vector(BUS_STROBE_WIDTH-1 downto 0) := (others => 'U');
      bs15_wdat_last            : in  std_logic := 'U';
      bs15_resp_valid           : out std_logic;
      bs15_resp_ready           : in  std_logic := '1';
      bs15_resp_ok              : out std_logic
    );
  end component;
   
  -----------------------------------------------------------------------------
  -- Component declarations for simulation-only helper units
  -----------------------------------------------------------------------------
  -- pragma translate_off

  component BusReadMasterMock is
    generic (
      BUS_ADDR_WIDTH            : natural := 32;
      BUS_LEN_WIDTH             : natural := 8;
      BUS_DATA_WIDTH            : natural := 32;
      SEED                      : positive
    );
    port (
      clk                       : in  std_logic;
      reset                     : in  std_logic;

      rreq_valid                : out std_logic;
      rreq_ready                : in  std_logic;
      rreq_addr                 : out std_logic_vector(BUS_ADDR_WIDTH-1 downto 0);
      rreq_len                  : out std_logic_vector(BUS_LEN_WIDTH-1 downto 0);
      rdat_valid                : in  std_logic;
      rdat_ready                : out std_logic;
      rdat_data                 : in  std_logic_vector(BUS_DATA_WIDTH-1 downto 0);
      rdat_last                 : in  std_logic
    );
  end component;

  component BusReadSlaveMock is
    generic (
      BUS_ADDR_WIDTH            : natural := 32;
      BUS_LEN_WIDTH             : natural := 8;
      BUS_DATA_WIDTH            : natural := 32;
      SEED                      : positive := 1;
      RANDOM_REQUEST_TIMING     : boolean := true;
      RANDOM_RESPONSE_TIMING    : boolean := true;
      SREC_FILE                 : string := ""
    );
    port (
      clk                       : in  std_logic;
      reset                     : in  std_logic;

      rreq_valid                : in  std_logic;
      rreq_ready                : out std_logic;
      rreq_addr                 : in  std_logic_vector(BUS_ADDR_WIDTH-1 downto 0);
      rreq_len                  : in  std_logic_vector(BUS_LEN_WIDTH-1 downto 0);
      rdat_valid                : out std_logic;
      rdat_ready                : in  std_logic;
      rdat_data                 : out std_logic_vector(BUS_DATA_WIDTH-1 downto 0);
      rdat_last                 : out std_logic
    );
  end component;

  component BusWriteMasterMock is
    generic (
      BUS_ADDR_WIDTH            : natural;
      BUS_LEN_WIDTH             : natural;
      BUS_DATA_WIDTH            : natural;
      BUS_STROBE_WIDTH          : natural;
      SEED                      : positive

    );
    port (
      clk                       : in  std_logic;
      reset                     : in  std_logic;
      wreq_valid                : out std_logic;
      wreq_ready                : in  std_logic;
      wreq_addr                 : out std_logic_vector(BUS_ADDR_WIDTH-1 downto 0);
      wreq_len                  : out std_logic_vector(BUS_LEN_WIDTH-1 downto 0);
      wdat_valid                : out std_logic;
      wdat_ready                : in  std_logic;
      wdat_data                 : out std_logic_vector(BUS_DATA_WIDTH-1 downto 0);
      wdat_strobe               : out std_logic_vector(BUS_STROBE_WIDTH-1 downto 0);
      wdat_last                 : out std_logic
    );
  end component;

  component BusWriteSlaveMock is
    generic (
      BUS_ADDR_WIDTH            : natural;
      BUS_LEN_WIDTH             : natural;
      BUS_DATA_WIDTH            : natural;
      BUS_STROBE_WIDTH          : natural;
      SEED                      : positive;
      RANDOM_REQUEST_TIMING     : boolean := false;
      RANDOM_RESPONSE_TIMING    : boolean := false;
      SREC_FILE                 : string  := ""
    );
    port (
      clk                       : in  std_logic;
      reset                     : in  std_logic;
      wreq_valid                : in  std_logic;
      wreq_ready                : out std_logic;
      wreq_addr                 : in  std_logic_vector(BUS_ADDR_WIDTH-1 downto 0);
      wreq_len                  : in  std_logic_vector(BUS_LEN_WIDTH-1 downto 0);
      wdat_valid                : in  std_logic;
      wdat_ready                : out std_logic;
      wdat_data                 : in  std_logic_vector(BUS_DATA_WIDTH-1 downto 0);
      wdat_strobe               : in  std_logic_vector(BUS_STROBE_WIDTH-1 downto 0);
      wdat_last                 : in  std_logic
    );
  end component;
  
  component BusReadWriteSlaveMock is
    generic (
      BUS_ADDR_WIDTH              : natural := 32;
      BUS_LEN_WIDTH               : natural := 8;
      BUS_DATA_WIDTH              : natural := 32;
      BUS_STROBE_WIDTH            : natural := 32/8;
      SEED                        : positive := 1;
      RANDOM_REQUEST_TIMING       : boolean := true;
      RANDOM_RESPONSE_TIMING      : boolean := true;
      SREC_FILE                   : string := ""
    );
    port (
      clk                         : in  std_logic;
      reset                       : in  std_logic;
      wreq_valid                  : in  std_logic;
      wreq_ready                  : out std_logic;
      wreq_addr                   : in  std_logic_vector(BUS_ADDR_WIDTH-1 downto 0);
      wreq_len                    : in  std_logic_vector(BUS_LEN_WIDTH-1 downto 0);
      wdat_valid                  : in  std_logic;
      wdat_ready                  : out std_logic;
      wdat_data                   : in  std_logic_vector(BUS_DATA_WIDTH-1 downto 0);
      wdat_strobe                 : in  std_logic_vector(BUS_STROBE_WIDTH-1 downto 0);
      wdat_last                   : in  std_logic;
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
  
  -- pragma translate_on
  
end Interconnect_pkg;
