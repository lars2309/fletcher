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
    cmd_region                  : out std_logic_vector(log2ceil(MEM_REGIONS)-1 downto 0);
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
begin

  cmd_addr    <= regs_in(2*REG_WIDTH-1 downto 0*REG_WIDTH);
  cmd_size    <= regs_in(4*REG_WIDTH-1 downto 2*REG_WIDTH);
  cmd_region <= slv(resize(unsigned(regs_in(5*REG_WIDTH-1 downto 4*REG_WIDTH)), cmd_region'length));
  cmd_valid   <= regs_in(5*REG_WIDTH + 0);
  cmd_alloc   <= regs_in(5*REG_WIDTH + 1);
  cmd_free    <= regs_in(5*REG_WIDTH + 2);
  cmd_realloc <= regs_in(5*REG_WIDTH + 3);

  process (regs_in, cmd_ready, resp_addr, resp_success, resp_valid)
  begin
    regs_out_en <= (others => '0');
    regs_out <= (others => 'U');

    -- reset cmd_valid bit when command was accepted
    regs_out(6*REG_WIDTH-1 downto 5*REG_WIDTH) <= (others => '0');
    regs_out_en(5) <= cmd_ready;

    regs_out(8*REG_WIDTH-1 downto 6*REG_WIDTH) <= resp_addr;
    regs_out(9*REG_WIDTH-1 downto 8*REG_WIDTH) <= (others => '0');
    regs_out(8*REG_WIDTH + 0) <= resp_valid;
    regs_out(8*REG_WIDTH + 1) <= resp_success;
    regs_out_en(8 downto 6) <= (others => resp_valid);
    resp_ready <= not regs_in(8*REG_WIDTH + 0);
  end process;

end architecture;

