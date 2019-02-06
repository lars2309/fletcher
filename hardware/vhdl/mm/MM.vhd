library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.Utils.all;

package MM is
  type mem_sizes_t is array(natural range <>) of natural;
  constant ADDR_WIDTH_LIMIT : natural := 64;

  function MEM_SUM (v : mem_sizes_t)
                    return natural;

  function LOG2_TO_UNSIGNED (v : natural)
                             return unsigned;

  component MMFrames is
    generic (
      PAGE_SIZE_LOG2              : natural;
      MEM_REGIONS                 : natural;
      MEM_SIZES                   : mem_sizes_t;
      MEM_MAP_BASE                : unsigned(ADDR_WIDTH_LIMIT-1 downto 0);
      MEM_MAP_SIZE_LOG2           : natural;
      BUS_ADDR_WIDTH              : natural
    );
    port (
      clk                         : in  std_logic;
      reset                       : in  std_logic;
      cmd_region                  : in  std_logic_vector(log2ceil(MEM_REGIONS)-1 downto 0);
      cmd_addr                    : in  std_logic_vector(BUS_ADDR_WIDTH-1 downto 0);
      cmd_free                    : in  std_logic;
      cmd_alloc                   : in  std_logic;
      cmd_find                    : in  std_logic;
      cmd_clear                   : in  std_logic;
      cmd_valid                   : in  std_logic;
      cmd_ready                   : out std_logic;

      resp_addr                   : out std_logic_vector(BUS_ADDR_WIDTH-1 downto 0);
      resp_success                : out std_logic;
      resp_valid                  : out std_logic;
      resp_ready                  : in  std_logic
    );
  end component;
end package;

package body MM is
  function MEM_SUM (v : mem_sizes_t)
                    return natural is
    variable sum : natural := 0;
  begin
    for i in v'range loop
      sum := sum + v(i);
    end loop;
    return sum;
  end MEM_SUM;

  function LOG2_TO_UNSIGNED (v : natural)
                             return unsigned is
    variable r : unsigned(v downto 0) := (others => '0');
  begin
    r(v) := '1';
    return r;
  end LOG2_TO_UNSIGNED;
end MM;
