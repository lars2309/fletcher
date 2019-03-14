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
use work.MM.all;
use work.MM_tc_params.all;

entity MMSystem_tc is
end MMSystem_tc;

architecture tb of MMSystem_tc is
signal bus_clk                : std_logic                                               := '0';
signal acc_clk                : std_logic                                               := '0';
signal bus_reset              : std_logic                                               := '0';
signal acc_reset              : std_logic                                               := '0';

signal cmd_region             : std_logic_vector(log2ceil(MEM_REGIONS+1)-1 downto 0);
signal cmd_addr               : std_logic_vector(BUS_ADDR_WIDTH-1 downto 0);
signal cmd_size               : std_logic_vector(BUS_ADDR_WIDTH-1 downto 0);
signal cmd_free               : std_logic                                               := '0';
signal cmd_alloc              : std_logic                                               := '0';
signal cmd_realloc            : std_logic                                               := '0';
signal cmd_valid              : std_logic                                               := '0';
signal cmd_ready              : std_logic;
signal resp_addr              : std_logic_vector(BUS_ADDR_WIDTH-1 downto 0);
signal resp_success           : std_logic;
signal resp_valid             : std_logic;
signal resp_ready             : std_logic                                               := '0';

signal mmu_req_valid          : std_logic;
signal mmu_req_ready          : std_logic;
signal mmu_req_addr           : std_logic_vector(BUS_ADDR_WIDTH-1 downto 0);

signal mmu_resp_valid         : std_logic;
signal mmu_resp_ready         : std_logic;
signal mmu_resp_addr          : std_logic_vector(BUS_ADDR_WIDTH-1 downto 0);

signal bus_r                  : bus_r_t;
signal bus_w                  : bus_w_t;
signal dir_r                  : bus_r_t;
signal dir_w                  : bus_w_t;
signal tra_r                  : bus_r_t;
signal bufl_r                 : bus_r_t;
signal bufp_r                 : bus_r_t;

-- Translate request channel
signal req_valid              : std_logic;
signal req_ready              : std_logic;
signal req_addr               : std_logic_vector(BUS_ADDR_WIDTH-1 downto 0);
-- Translate response channel
signal tra_valid              : std_logic;
signal tra_ready              : std_logic;
signal tra_virt               : std_logic_vector(BUS_ADDR_WIDTH-1 downto 0);
signal tra_phys               : std_logic_vector(BUS_ADDR_WIDTH-1 downto 0);
signal tra_mask               : std_logic_vector(BUS_ADDR_WIDTH-1 downto 0);

signal TbClock                : std_logic                                               := '0';
signal TbReset                : std_logic                                               := '0';
signal TbSimEnded             : std_logic                                               := '0';

procedure handshake_out (signal clk : in std_logic; signal rdy : in std_logic;
                         signal valid : out std_logic) is
begin
  valid <= '1';
  loop
    wait until rising_edge(clk);
    exit when rdy = '1';
  end loop;
  wait for 0 ns;
  valid <= '0';
end handshake_out;

procedure handshake_in (signal clk : in std_logic; signal rdy : out std_logic;
                        signal valid : in std_logic) is
begin
  rdy <= '1';
  loop
    wait until rising_edge(clk);
    exit when valid = '1';
  end loop;
  wait for 0 ns;
  rdy <= '0';
end handshake_in;

begin

-- Clock generation
TbClock <= not TbClock after TbPeriod/2 when TbSimEnded /= '1' else '0';

bus_clk <= TbClock;
acc_clk <= TbClock;

bus_reset <= TbReset;
acc_reset <= TbReset;

bus_w.resp_ok    <= '1';
bus_w.resp_valid <= bus_w.dat_valid and bus_w.dat_ready and bus_w.dat_last;

stimuli : process
  variable addr_a : std_logic_vector(BUS_ADDR_WIDTH-1 downto 0);
  variable addr_b : std_logic_vector(BUS_ADDR_WIDTH-1 downto 0);
begin
  ---------------------------------------------------------------------------
  wait until rising_edge(TbClock);
  TbReset                     <= '1';
  bufl_r.req_valid            <= '0';
  bufp_r.dat_ready            <= '1';
  wait until rising_edge(TbClock);
  TbReset                     <= '0';
  wait until rising_edge(TbClock);

  -- Allocate 3 GB (buffer A)
  cmd_alloc  <= '1';
  cmd_size   <= slv(shift_left(to_unsigned(3, cmd_size'length), 30));
  cmd_region <= slv(to_unsigned(1, cmd_region'length));
  handshake_out(TbClock, cmd_ready, cmd_valid);
  cmd_alloc  <= '0';

  resp_ready <= '1';
  loop
    wait until rising_edge(TbClock);
    exit when resp_valid = '1';
  end loop;
  addr_a := resp_addr;
  wait for 0 ns;
  resp_ready <= '0';

  -- Allocate 34 GB (buffer B)
  cmd_alloc  <= '1';
  cmd_size   <= slv(shift_left(to_unsigned(34, cmd_size'length), 30));
  cmd_region <= slv(to_unsigned(1, cmd_region'length));
  handshake_out(TbClock, cmd_ready, cmd_valid);
  cmd_alloc  <= '0';

  resp_ready <= '1';
  loop
    wait until rising_edge(TbClock);
    exit when resp_valid = '1';
  end loop;
  addr_b := resp_addr;
  wait for 0 ns;
  resp_ready <= '0';


  -- Try reading from buffer A
  bufl_r.req_addr  <= addr_a;
  bufl_r.req_len   <= slv(to_unsigned(1, bufl_r.req_len'length));
  handshake_out(TbClock, bufl_r.req_ready, bufl_r.req_valid);

  for data_line in 0 to 11 loop
    bufl_r.req_addr  <= slv(u(bufl_r.req_addr) + (BUS_DATA_WIDTH/BYTE_SIZE));
    handshake_out(TbClock, bufl_r.req_ready, bufl_r.req_valid);
  end loop;


  -- Try reading from buffer B
  bufl_r.req_addr  <= addr_b;
  handshake_out(TbClock, bufl_r.req_ready, bufl_r.req_valid);

  -- Read next page from buffer B
  bufl_r.req_addr  <= slv(u(addr_b) + 2**PAGE_SIZE_LOG2);
  handshake_out(TbClock, bufl_r.req_ready, bufl_r.req_valid);


  -- Purge pipelines
  for n in 0 to 20 loop
    wait until rising_edge(TbClock);
  end loop;

  -- Free the first allocation
--    cmd_free <= '1';
--    cmd_addr <= addr;
--    handshake_out(TbClock, cmd_ready, cmd_valid);


  TbSimEnded                  <= '0';

  report "END OF TEST"  severity note;

  wait;

end process;

translator_inst : MMTranslator
  generic map (
    VM_BASE                   => VM_BASE,
    PT_ENTRIES_LOG2           => PT_ENTRIES_LOG2,
    PAGE_SIZE_LOG2            => PAGE_SIZE_LOG2,
    BUS_ADDR_WIDTH            => BUS_ADDR_WIDTH,
    BUS_LEN_WIDTH             => BUS_LEN_WIDTH
  )
  port map (
    clk                       => bus_clk,
    reset                     => bus_reset,

    -- Slave request channel
    slv_req_valid             => bufl_r.req_valid,
    slv_req_ready             => bufl_r.req_ready,
    slv_req_addr              => bufl_r.req_addr,
    slv_req_len               => bufl_r.req_len,
    -- Master request channel
    mst_req_valid             => bufp_r.req_valid,
    mst_req_ready             => bufp_r.req_ready,
    mst_req_addr              => bufp_r.req_addr,
    mst_req_len               => bufp_r.req_len,

    -- Translate request channel
    req_valid                 => req_valid,
    req_ready                 => req_ready,
    req_addr                  => req_addr,
    -- Translate response channel
    resp_valid                => tra_valid,
    resp_ready                => tra_ready,
    resp_virt                 => tra_virt,
    resp_phys                 => tra_phys,
    resp_mask                 => tra_mask
  );

mmu_inst : MMWalker
  generic map (
    PAGE_SIZE_LOG2            => PAGE_SIZE_LOG2,
    PT_ADDR                   => PT_ADDR,
    PT_ENTRIES_LOG2           => PT_ENTRIES_LOG2,
    PTE_BITS                  => PTE_BITS,
    ---------------------------------------------------------------------------
    -- Bus metrics and configuration
    ---------------------------------------------------------------------------
    BUS_ADDR_WIDTH            => BUS_ADDR_WIDTH,
    BUS_LEN_WIDTH             => BUS_LEN_WIDTH,
    BUS_DATA_WIDTH            => BUS_DATA_WIDTH,
    BUS_STROBE_WIDTH          => BUS_STROBE_WIDTH,
    BUS_BURST_STEP_LEN        => BUS_BURST_STEP_LEN,
    BUS_BURST_MAX_LEN         => BUS_BURST_MAX_LEN
  )
  port map (
    clk                       => bus_clk,
    reset                     => bus_reset,

    -- Read address channel
    bus_rreq_addr             => tra_r.req_addr,
    bus_rreq_len              => tra_r.req_len,
    bus_rreq_valid            => tra_r.req_valid,
    bus_rreq_ready            => tra_r.req_ready,

    -- Read data channel
    bus_rdat_data             => tra_r.dat_data,
    bus_rdat_last             => tra_r.dat_last,
    bus_rdat_valid            => tra_r.dat_valid,
    bus_rdat_ready            => tra_r.dat_ready,

    -- Translate request channel
    req_valid                 => req_valid,
    req_ready                 => req_ready,
    req_addr                  => req_addr,
    -- Translate response channel
    resp_valid                => tra_valid,
    resp_ready                => tra_ready,
    resp_virt                 => tra_virt,
    resp_phys                 => tra_phys,
    resp_mask                 => tra_mask,

    dir_req_valid             => mmu_req_valid,
    dir_req_ready             => mmu_req_ready,
    dir_req_addr              => mmu_req_addr,

    dir_resp_valid            => mmu_resp_valid,
    dir_resp_ready            => mmu_resp_ready,
    dir_resp_addr             => mmu_resp_addr
  );

director : MMDirector
  generic map (
    PAGE_SIZE_LOG2            => PAGE_SIZE_LOG2,
    MEM_REGIONS               => MEM_REGIONS,
    MEM_SIZES                 => MEM_SIZES,
    MEM_MAP_BASE              => MEM_MAP_BASE,
    MEM_MAP_SIZE_LOG2         => MEM_MAP_SIZE_LOG2,
    VM_BASE                   => VM_BASE,
    PT_ADDR                   => PT_ADDR,
    PT_ENTRIES_LOG2           => PT_ENTRIES_LOG2,
    PTE_BITS                  => PTE_BITS,
    BUS_ADDR_WIDTH            => BUS_ADDR_WIDTH,
    BUS_LEN_WIDTH             => BUS_LEN_WIDTH
  )
  port map (
    clk                       => bus_clk,
    reset                     => bus_reset,

    cmd_region                => cmd_region,
    cmd_addr                  => cmd_addr,
    cmd_size                  => cmd_size,
    cmd_free                  => cmd_free,
    cmd_alloc                 => cmd_alloc,
    cmd_realloc               => cmd_realloc,
    cmd_valid                 => cmd_valid,
    cmd_ready                 => cmd_ready,

    resp_addr                 => resp_addr,
    resp_success              => resp_success,
    resp_valid                => resp_valid,
    resp_ready                => resp_ready,

    mmu_req_valid             => mmu_req_valid,
    mmu_req_ready             => mmu_req_ready,
    mmu_req_addr              => mmu_req_addr,

    mmu_resp_valid            => mmu_resp_valid,
    mmu_resp_ready            => mmu_resp_ready,
    mmu_resp_addr             => mmu_resp_addr,

    bus_wreq_valid            => bus_w.req_valid,
    bus_wreq_ready            => bus_w.req_ready,
    bus_wreq_addr             => bus_w.req_addr,
    bus_wreq_len              => bus_w.req_len,
    bus_wdat_valid            => bus_w.dat_valid,
    bus_wdat_ready            => bus_w.dat_ready,
    bus_wdat_data             => bus_w.dat_data,
    bus_wdat_strobe           => bus_w.dat_strobe,
    bus_wdat_last             => bus_w.dat_last,

    bus_rreq_valid            => dir_r.req_valid,
    bus_rreq_ready            => dir_r.req_ready,
    bus_rreq_addr             => dir_r.req_addr,
    bus_rreq_len              => dir_r.req_len,
    bus_rdat_valid            => dir_r.dat_valid,
    bus_rdat_ready            => dir_r.dat_ready,
    bus_rdat_data             => dir_r.dat_data,
    bus_rdat_last             => dir_r.dat_last,
    
    bus_resp_valid            => bus_w.resp_valid,
    bus_resp_ready            => bus_w.resp_ready,
    bus_resp_ok               => bus_w.resp_ok
  );

read_arb_inst : BusReadArbiter
  generic map (
    BUS_ADDR_WIDTH            => BUS_ADDR_WIDTH,
    BUS_LEN_WIDTH             => BUS_LEN_WIDTH,
    BUS_DATA_WIDTH            => BUS_DATA_WIDTH,
    NUM_SLAVE_PORTS           => 3
  )
  port map (
    bus_clk                   => bus_clk,
    bus_reset                 => bus_reset,

    mst_rreq_valid            => bus_r.req_valid,
    mst_rreq_ready            => bus_r.req_ready,
    mst_rreq_addr             => bus_r.req_addr,
    mst_rreq_len              => bus_r.req_len,
    mst_rdat_valid            => bus_r.dat_valid,
    mst_rdat_ready            => bus_r.dat_ready,
    mst_rdat_data             => bus_r.dat_data,
    mst_rdat_last             => bus_r.dat_last,

    bs00_rreq_valid           => dir_r.req_valid,
    bs00_rreq_ready           => dir_r.req_ready,
    bs00_rreq_addr            => dir_r.req_addr,
    bs00_rreq_len             => dir_r.req_len,
    bs00_rdat_valid           => dir_r.dat_valid,
    bs00_rdat_ready           => dir_r.dat_ready,
    bs00_rdat_data            => dir_r.dat_data,
    bs00_rdat_last            => dir_r.dat_last,

    bs01_rreq_valid           => tra_r.req_valid,
    bs01_rreq_ready           => tra_r.req_ready,
    bs01_rreq_addr            => tra_r.req_addr,
    bs01_rreq_len             => tra_r.req_len,
    bs01_rdat_valid           => tra_r.dat_valid,
    bs01_rdat_ready           => tra_r.dat_ready,
    bs01_rdat_data            => tra_r.dat_data,
    bs01_rdat_last            => tra_r.dat_last,

    bs02_rreq_valid           => bufp_r.req_valid,
    bs02_rreq_ready           => bufp_r.req_ready,
    bs02_rreq_addr            => bufp_r.req_addr,
    bs02_rreq_len             => bufp_r.req_len,
    bs02_rdat_valid           => bufp_r.dat_valid,
    bs02_rdat_ready           => bufp_r.dat_ready,
    bs02_rdat_data            => bufp_r.dat_data,
    bs02_rdat_last            => bufp_r.dat_last
  );


dev_mem : BusReadWriteSlaveMock
  generic map (
    BUS_ADDR_WIDTH            => BUS_ADDR_WIDTH,
    BUS_LEN_WIDTH             => BUS_LEN_WIDTH,
    BUS_DATA_WIDTH            => BUS_DATA_WIDTH,
    BUS_STROBE_WIDTH          => BUS_STROBE_WIDTH,
    SEED                      => 1337,
    RANDOM_REQUEST_TIMING     => BUS_SLAVE_RND_REQ,
    RANDOM_RESPONSE_TIMING    => BUS_SLAVE_RND_RESP,
    SREC_FILE                 => ""
  )
  port map (
    clk                       => bus_clk,
    reset                     => bus_reset,

    wreq_valid                => bus_w.req_valid,
    wreq_ready                => bus_w.req_ready,
    wreq_addr                 => bus_w.req_addr,
    wreq_len                  => bus_w.req_len,
    wdat_valid                => bus_w.dat_valid,
    wdat_ready                => bus_w.dat_ready,
    wdat_data                 => bus_w.dat_data,
    wdat_strobe               => bus_w.dat_strobe,
    wdat_last                 => bus_w.dat_last,

    rreq_valid                => bus_r.req_valid,
    rreq_ready                => bus_r.req_ready,
    rreq_addr                 => bus_r.req_addr,
    rreq_len                  => bus_r.req_len,
    rdat_valid                => bus_r.dat_valid,
    rdat_ready                => bus_r.dat_ready,
    rdat_data                 => bus_r.dat_data,
    rdat_last                 => bus_r.dat_last
  );

end architecture;
