library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.Utils.all;

package MM is
  type mem_sizes_t is array(natural range <>) of natural;
  constant ADDR_WIDTH_LIMIT : natural := 64;
  constant BYTE_SIZE        : natural := 8;

  function MEM_SUM (v : mem_sizes_t)
                    return natural;

  function LOG2_TO_UNSIGNED (v : natural)
                             return unsigned;

  function XOR_REDUCT(arg : in std_logic_vector)
                      return std_logic;

  function ZEROS(arg : in natural)
                 return std_logic_vector;

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

  component MMDirector is
    generic (
      PAGE_SIZE_LOG2              : natural;
      MEM_REGIONS                 : natural;
      MEM_SIZES                   : mem_sizes_t;
      MEM_MAP_BASE                : unsigned(ADDR_WIDTH_LIMIT-1 downto 0);
      MEM_MAP_SIZE_LOG2           : natural;
      PT_ADDR                     : unsigned(ADDR_WIDTH_LIMIT-1 downto 0);
      PT_ENTRIES_LOG2             : natural;
      PTE_BITS                    : natural;

      ---------------------------------------------------------------------------
      -- Bus metrics and configuration
      ---------------------------------------------------------------------------
      -- Bus address width.
      BUS_ADDR_WIDTH              : natural := 64;

      -- Bus burst length width.
      BUS_LEN_WIDTH               : natural := 8;

      -- Bus data width.
      BUS_DATA_WIDTH              : natural := 512;

      -- Bus strobe width.
      BUS_STROBE_WIDTH            : natural := 512/BYTE_SIZE;

      -- Number of beats in a burst step.
      BUS_BURST_STEP_LEN          : natural := 4;

      -- Maximum number of beats in a burst.
      BUS_BURST_MAX_LEN           : natural := 16
    );
    port (
      clk                         : in  std_logic;
      reset                       : in  std_logic;
      cmd_region                  : in  std_logic_vector(log2ceil(MEM_REGIONS)-1 downto 0);
      cmd_addr                    : in  std_logic_vector(BUS_ADDR_WIDTH-1 downto 0);
      cmd_free                    : in  std_logic;
      cmd_alloc                   : in  std_logic;
      cmd_realloc                 : in  std_logic;
      cmd_valid                   : in  std_logic;
      cmd_ready                   : out std_logic;

      resp_addr                   : out std_logic_vector(BUS_ADDR_WIDTH-1 downto 0);
      resp_success                : out std_logic;
      resp_valid                  : out std_logic;
      resp_ready                  : in  std_logic;

      ---------------------------------------------------------------------------
      -- Bus write channels
      ---------------------------------------------------------------------------
      -- Request channel
      bus_wreq_valid              : out std_logic;
      bus_wreq_ready              : in  std_logic;
      bus_wreq_addr               : out std_logic_vector(BUS_ADDR_WIDTH-1 downto 0);
      bus_wreq_len                : out std_logic_vector(BUS_LEN_WIDTH-1 downto 0);

      -- Data channel             
      bus_wdat_valid              : out std_logic;
      bus_wdat_ready              : in  std_logic;
      bus_wdat_data               : out std_logic_vector(BUS_DATA_WIDTH-1 downto 0);
      bus_wdat_strobe             : out std_logic_vector(BUS_STROBE_WIDTH-1 downto 0);
      bus_wdat_last               : out std_logic;

      -- Read address channel
      bus_rreq_addr               : out std_logic_vector(BUS_ADDR_WIDTH-1 downto 0);
      bus_rreq_len                : out std_logic_vector(BUS_LEN_WIDTH-1 downto 0);
      bus_rreq_valid              : out std_logic;
      bus_rreq_ready              : in  std_logic;

      -- Read data channel
      bus_rdat_data               : in  std_logic_vector(BUS_DATA_WIDTH-1 downto 0);
      bus_rdat_last               : in  std_logic;
      bus_rdat_valid              : in  std_logic;
      bus_rdat_ready              : out std_logic
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

  function XOR_REDUCT(arg : in std_logic_vector)
                      return std_logic is
    variable ret : std_logic := '0';
  begin
    for i in arg'range loop
      ret := ret xor arg(i);
    end loop;
    return ret;
  end XOR_REDUCT;

  function ZEROS(arg : in natural)
                 return std_logic_vector is
    variable ret : std_logic_vector(arg-1 downto 0) := (others => '0');
  begin
    return ret;
  end ZEROS;

end MM;
