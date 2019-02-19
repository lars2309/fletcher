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
  constant BUS_LEN_WIDTH               : natural := 8;
  constant BUS_BURST_STEP_LEN          : natural := 16;
  constant BUS_BURST_MAX_LEN           : natural := 128;

    -- Random timing for bus slave mock
  constant BUS_SLAVE_RND_REQ           : boolean := true;
  constant BUS_SLAVE_RND_RESP          : boolean := true;

  constant PAGE_SIZE_LOG2              : natural := 22;
  constant VM_BASE                     : unsigned(BUS_ADDR_WIDTH-1 downto 0) := X"4000_0000_0000_0000";
  constant MEM_REGIONS                 : natural := 2;
  constant MEM_SIZES                   : nat_array := (10, 15);
  constant MEM_MAP_BASE                : unsigned(BUS_ADDR_WIDTH-1 downto 0) := VM_BASE;
  constant MEM_MAP_SIZE_LOG2           : natural := 37;
  constant PT_ENTRIES_LOG2             : natural := 13;
  constant PTE_BITS                    : natural := BUS_ADDR_WIDTH;
  constant PT_ADDR_INTERM              : unsigned(BUS_ADDR_WIDTH-1 downto 0) := MEM_MAP_BASE;
  constant PT_ADDR                     : unsigned(BUS_ADDR_WIDTH-1 downto 0) := PT_ADDR_INTERM + 2**PT_ENTRIES_LOG2 * ( (PTE_BITS+BYTE_SIZE-1) / BYTE_SIZE);
end package;

