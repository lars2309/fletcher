library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.Utils.all;
use work.MM.all;

package MM_tc_params is
  constant TbPeriod                    : time    := 4 ns;

  constant BUS_ADDR_WIDTH              : natural := 64;
  constant BUS_DATA_WIDTH              : natural := 512;
  constant BUS_STROBE_WIDTH            : natural := 512/8;
  constant BUS_LEN_WIDTH               : natural := 9;
  constant BUS_BURST_STEP_LEN          : natural := 16;
  constant BUS_BURST_MAX_LEN           : natural := 128;

    -- Random timing for bus slave mock
  constant BUS_SLAVE_RND_REQ           : boolean := true;
  constant BUS_SLAVE_RND_RESP          : boolean := true;

  constant PAGE_SIZE_LOG2              : natural := 22;
  constant VM_BASE                     : unsigned(63 downto 0) := X"4000_0000_0000_0000";
  constant MEM_REGIONS                 : natural := 2;
  constant MEM_SIZES                   : mem_sizes_t := (10, 15);
  constant MEM_MAP_BASE                : unsigned(63 downto 0) := X"4000_0000_0000_0000";
  constant MEM_MAP_SIZE_LOG2           : natural := 37;
  constant PT_ADDR                     : std_logic_vector(63 downto 0) := X"4000_0000_0000_0000";

end package;

