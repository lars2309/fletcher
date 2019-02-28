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
use work.Streams.all;

entity MMHostInterface is
  generic (
    -- 1 cmd_region
    -- 2 cmd_addr
    -- 2 cmd_size
    -- 1 cmd_free/alloc/realloc/valid
    --  6 cmd
    -- 2 resp_addr
    -- 1 resp_success/valid
    --  3 resp
    NUM_REGS                    : natural := 6+3;
    REG_WIDTH                   : natural := 32;
    BUS_ADDR_WIDTH              : natural := 64;
    MEM_REGIONS                 : natural
  );
  port (
    clk                         : in  std_logic;
    reset                       : in  std_logic;
    cmd_region                  : out std_logic_vector(log2ceil(MEM_REGIONS+1)-1 downto 0);
    cmd_addr                    : out std_logic_vector(BUS_ADDR_WIDTH-1 downto 0);
    cmd_size                    : out std_logic_vector(BUS_ADDR_WIDTH-1 downto 0);
    cmd_free                    : out std_logic;
    cmd_alloc                   : out std_logic;
    cmd_realloc                 : out std_logic;
    cmd_valid                   : out std_logic;
    cmd_ready                   : in  std_logic;

    resp_addr                   : in  std_logic_vector(BUS_ADDR_WIDTH-1 downto 0);
    resp_success                : in  std_logic;
    resp_valid                  : in  std_logic;
    resp_ready                  : out std_logic;

    regs_in                     : in  std_logic_vector(NUM_REGS*REG_WIDTH-1 downto 0);
    regs_out                    : out std_logic_vector(NUM_REGS*REG_WIDTH-1 downto 0);
    regs_out_en                 : out std_logic_vector(NUM_REGS-1 downto 0)
  );
end MMHostInterface;


architecture Behavioral of MMHostInterface is

  -- Command stream serialization indices.
  constant CSI : nat_array := cumulative((
    5 => 1,
    4 => 1,
    3 => 1,
    2 => BUS_ADDR_WIDTH,
    1 => BUS_ADDR_WIDTH,
    0 => log2ceil(MEM_REGIONS+1)
  ));

  -- Response stream serialization indices.
  constant RSI : nat_array := cumulative((
    1 => 1,
    0 => BUS_ADDR_WIDTH
  ));

  signal int_cmd_region              : std_logic_vector(log2ceil(MEM_REGIONS+1)-1 downto 0);
  signal int_cmd_addr                : std_logic_vector(BUS_ADDR_WIDTH-1 downto 0);
  signal int_cmd_size                : std_logic_vector(BUS_ADDR_WIDTH-1 downto 0);
  signal int_cmd_free                : std_logic;
  signal int_cmd_alloc               : std_logic;
  signal int_cmd_realloc             : std_logic;
  signal int_cmd_valid               : std_logic;
  signal int_cmd_ready               : std_logic;
  signal int_cmd_all                 : std_logic_vector(CSI(CSI'high)-1 downto 0);
  signal cmd_all                     : std_logic_vector(CSI(CSI'high)-1 downto 0);

  signal int_resp_addr               : std_logic_vector(BUS_ADDR_WIDTH-1 downto 0);
  signal int_resp_success            : std_logic;
  signal int_resp_valid              : std_logic;
  signal int_resp_ready              : std_logic;
  signal int_resp_all                : std_logic_vector(RSI(RSI'high)-1 downto 0);
  signal resp_all                    : std_logic_vector(RSI(RSI'high)-1 downto 0);
begin

  int_cmd_addr    <= regs_in(2*REG_WIDTH-1 downto 0*REG_WIDTH);
  int_cmd_size    <= regs_in(4*REG_WIDTH-1 downto 2*REG_WIDTH);
  int_cmd_region  <= slv(resize(unsigned(regs_in(5*REG_WIDTH-1 downto 4*REG_WIDTH)), cmd_region'length));
  int_cmd_valid   <= regs_in(5*REG_WIDTH + 0);
  int_cmd_alloc   <= regs_in(5*REG_WIDTH + 1);
  int_cmd_free    <= regs_in(5*REG_WIDTH + 2);
  int_cmd_realloc <= regs_in(5*REG_WIDTH + 3);


  process (regs_in, int_cmd_ready, int_resp_addr, int_resp_success, int_resp_valid)
  begin
    regs_out_en <= (others => '0');
    regs_out <= (others => 'U');

    -- reset cmd_valid bit when command was accepted
    regs_out(6*REG_WIDTH-1 downto 5*REG_WIDTH) <= (others => '0');
    regs_out_en(5) <= int_cmd_ready;

    regs_out(8*REG_WIDTH-1 downto 6*REG_WIDTH) <= int_resp_addr;
    regs_out(9*REG_WIDTH-1 downto 8*REG_WIDTH) <= (others => '0');
    regs_out(8*REG_WIDTH + 0) <= int_resp_valid;
    regs_out(8*REG_WIDTH + 1) <= int_resp_success;
    regs_out_en(8 downto 6) <= (others => int_resp_valid);
    int_resp_ready <= not regs_in(8*REG_WIDTH + 0);
  end process;


  int_cmd_all(                CSI(5)) <= int_cmd_realloc;
  int_cmd_all(                CSI(4)) <= int_cmd_free;
  int_cmd_all(                CSI(3)) <= int_cmd_alloc;
  int_cmd_all(CSI(3)-1 downto CSI(2)) <= int_cmd_addr;
  int_cmd_all(CSI(2)-1 downto CSI(1)) <= int_cmd_size;
  int_cmd_all(CSI(1)-1 downto CSI(0)) <= int_cmd_region;

  cmd_slice : StreamSlice
    generic map (
      DATA_WIDTH                  => CSI(CSI'high)
    )
    port map (
      clk                         => clk,
      reset                       => reset,

      in_valid                    => int_cmd_valid,
      in_ready                    => int_cmd_ready,
      in_data                     => int_cmd_all,

      out_valid                   => cmd_valid,
      out_ready                   => cmd_ready,
      out_data                    => cmd_all
    );

  cmd_realloc <= cmd_all(                CSI(5));
  cmd_free    <= cmd_all(                CSI(4));
  cmd_alloc   <= cmd_all(                CSI(3));
  cmd_addr    <= cmd_all(CSI(3)-1 downto CSI(2));
  cmd_size    <= cmd_all(CSI(2)-1 downto CSI(1));
  cmd_region  <= cmd_all(CSI(1)-1 downto CSI(0));


  resp_all(                RSI(1)) <= resp_success;
  resp_all(RSI(1)-1 downto RSI(0)) <= resp_addr;

  resp_slice : StreamSlice
    generic map (
      DATA_WIDTH                  => RSI(RSI'high)
    )
    port map (
      clk                         => clk,
      reset                       => reset,

      in_valid                    => resp_valid,
      in_ready                    => resp_ready,
      in_data                     => resp_all,

      out_valid                   => int_resp_valid,
      out_ready                   => int_resp_ready,
      out_data                    => int_resp_all
    );

  int_resp_success <= int_resp_all(                RSI(1));
  int_resp_addr    <= int_resp_all(RSI(1)-1 downto RSI(0));

end architecture;

