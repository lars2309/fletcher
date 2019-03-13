library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.Utils.all;

package MM is
  constant ADDR_WIDTH_LIMIT : natural := 64;
  constant BYTE_SIZE        : natural := 8;

  constant PTE_MAPPED       : natural := 0;
  constant PTE_PRESENT      : natural := 1;
  constant PTE_BOUNDARY     : natural := 2;
  constant PTE_SEGMENT      : natural := 3;

  function LOG2_TO_UNSIGNED (v : natural)
                             return unsigned;

  function XOR_REDUCT(arg : in std_logic_vector)
                      return std_logic;

  function DIV_CEIL (numerator   : natural;
                     denominator : natural)
    return natural;

  function OVERLAY (over  : unsigned;
                    under : unsigned;
                    offset: natural)
    return unsigned;

  function OVERLAY (over  : unsigned;
                    under : unsigned)
    return unsigned;
  function EXTRACT (vec    : unsigned;
                    offset : natural;
                    length : natural)
    return unsigned;

  component MMFrames is
    generic (
      PAGE_SIZE_LOG2              : natural;
      MEM_REGIONS                 : natural;
      MEM_SIZES                   : nat_array;
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
      MEM_SIZES                   : nat_array;
      MEM_MAP_BASE                : unsigned(ADDR_WIDTH_LIMIT-1 downto 0);
      MEM_MAP_SIZE_LOG2           : natural;
      VM_BASE                     : unsigned(ADDR_WIDTH_LIMIT-1 downto 0);
      PT_ADDR                     : unsigned(ADDR_WIDTH_LIMIT-1 downto 0);
      PT_ENTRIES_LOG2             : natural;
      PTE_BITS                    : natural;

      MAX_OUTSTANDING_TRANSACTIONS: natural := 63;

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
      cmd_region                  : in  std_logic_vector(log2ceil(MEM_REGIONS+1)-1 downto 0);
      cmd_addr                    : in  std_logic_vector(BUS_ADDR_WIDTH-1 downto 0);
      cmd_size                    : in  std_logic_vector(BUS_ADDR_WIDTH-1 downto 0);
      cmd_free                    : in  std_logic;
      cmd_alloc                   : in  std_logic;
      cmd_realloc                 : in  std_logic;
      cmd_valid                   : in  std_logic;
      cmd_ready                   : out std_logic;

      resp_addr                   : out std_logic_vector(BUS_ADDR_WIDTH-1 downto 0);
      resp_success                : out std_logic;
      resp_valid                  : out std_logic;
      resp_ready                  : in  std_logic;

      mmu_req_valid               : in  std_logic := '0';
      mmu_req_ready               : out std_logic;
      mmu_req_addr                : in  std_logic_vector(BUS_ADDR_WIDTH-1 downto 0) := (others => '0');

      mmu_resp_valid              : out std_logic;
      mmu_resp_ready              : in  std_logic := '1';
      mmu_resp_addr               : out std_logic_vector(BUS_ADDR_WIDTH-1 downto 0);

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

      -- Response channel
      bus_resp_valid              : in  std_logic;
      bus_resp_ready              : out std_logic;
      bus_resp_ok                 : in  std_logic;

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

  component MMHostInterface is
    generic (
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
  end component;

  component MMBarrier is
    generic (
      BUS_ADDR_WIDTH              : natural := 64;
      BUS_LEN_WIDTH               : natural := 8;
      MAX_OUTSTANDING             : natural := 31
    );
    port (
      clk                         : in  std_logic;
      reset                       : in  std_logic;
      dirty                       : out std_logic;

      -- Slave write request channel
      slv_wreq_valid              : in  std_logic;
      slv_wreq_ready              : out std_logic;
      slv_wreq_addr               : in  std_logic_vector(BUS_ADDR_WIDTH-1 downto 0);
      slv_wreq_len                : in  std_logic_vector(BUS_LEN_WIDTH-1 downto 0);
      slv_wreq_barrier            : in  std_logic;
      -- Master write request channel
      mst_wreq_valid              : out std_logic;
      mst_wreq_ready              : in  std_logic;
      mst_wreq_addr               : out std_logic_vector(BUS_ADDR_WIDTH-1 downto 0);
      mst_wreq_len                : out std_logic_vector(BUS_LEN_WIDTH-1 downto 0);

      -- Slave response channel
      slv_resp_valid              : out std_logic;
      slv_resp_ready              : in  std_logic := '1';
      slv_resp_ok                 : out std_logic;
      -- Master response channel
      mst_resp_valid              : in  std_logic;
      mst_resp_ready              : out std_logic;
      mst_resp_ok                 : in  std_logic
    );
  end component;

  component MMTranslator is
    generic (
      VM_BASE                     : unsigned(ADDR_WIDTH_LIMIT-1 downto 0);
      PT_ENTRIES_LOG2             : natural;
      PAGE_SIZE_LOG2              : natural;
      BUS_ADDR_WIDTH              : natural := 64;
      BUS_LEN_WIDTH               : natural := 8
    );
    port (
      clk                         : in  std_logic;
      reset                       : in  std_logic;

      -- Slave request channel
      slv_req_valid               : in  std_logic;
      slv_req_ready               : out std_logic;
      slv_req_addr                : in  std_logic_vector(BUS_ADDR_WIDTH-1 downto 0);
      slv_req_len                 : in  std_logic_vector(BUS_LEN_WIDTH-1 downto 0);
      -- Master request channel
      mst_req_valid               : out std_logic;
      mst_req_ready               : in  std_logic;
      mst_req_addr                : out std_logic_vector(BUS_ADDR_WIDTH-1 downto 0);
      mst_req_len                 : out std_logic_vector(BUS_LEN_WIDTH-1 downto 0);

      -- Translate request channel
      req_valid                   : out std_logic;
      req_ready                   : in  std_logic;
      req_addr                    : out std_logic_vector(BUS_ADDR_WIDTH-1 downto 0);
      -- Translate response channel
      resp_valid                  : in  std_logic;
      resp_ready                  : out std_logic;
      resp_virt                   : in  std_logic_vector(BUS_ADDR_WIDTH-1 downto 0);
      resp_phys                   : in  std_logic_vector(BUS_ADDR_WIDTH-1 downto 0);
      resp_mask                   : in  std_logic_vector(BUS_ADDR_WIDTH-1 downto 0)
    );
  end component;

  component MMU is
    generic (
      PAGE_SIZE_LOG2              : natural;
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

      -- Read address channel
      bus_rreq_addr               : out std_logic_vector(BUS_ADDR_WIDTH-1 downto 0);
      bus_rreq_len                : out std_logic_vector(BUS_LEN_WIDTH-1 downto 0);
      bus_rreq_valid              : out std_logic;
      bus_rreq_ready              : in  std_logic;

      -- Read data channel
      bus_rdat_data               : in  std_logic_vector(BUS_DATA_WIDTH-1 downto 0);
      bus_rdat_last               : in  std_logic;
      bus_rdat_valid              : in  std_logic;
      bus_rdat_ready              : out std_logic;

      -- Translate request channel
      req_valid                   : in  std_logic;
      req_ready                   : out std_logic;
      req_addr                    : in  std_logic_vector(BUS_ADDR_WIDTH-1 downto 0);
      -- Translate response channel
      resp_valid                  : out std_logic;
      resp_ready                  : in  std_logic;
      resp_virt                   : out std_logic_vector(BUS_ADDR_WIDTH-1 downto 0);
      resp_phys                   : out std_logic_vector(BUS_ADDR_WIDTH-1 downto 0);
      resp_mask                   : out std_logic_vector(BUS_ADDR_WIDTH-1 downto 0);

      dir_req_valid               : out std_logic;
      dir_req_ready               : in  std_logic := '0';
      dir_req_addr                : out std_logic_vector(BUS_ADDR_WIDTH-1 downto 0);
      
      dir_resp_valid              : in  std_logic := '0';
      dir_resp_ready              : out std_logic;
      dir_resp_addr               : in  std_logic_vector(BUS_ADDR_WIDTH-1 downto 0) := (others => '0')
    );
  end component;

end package;

package body MM is
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

  function DIV_CEIL (numerator   : natural;
                     denominator : natural)
    return natural is
  begin
    return (numerator + denominator - 1) / denominator;
  end DIV_CEIL;

  function OVERLAY (over  : unsigned;
                    under : unsigned;
                    offset: natural)
    return unsigned is
    variable ret : unsigned(under'length-1 downto 0);
  begin
    ret := under;
    ret(over'length + offset - 1 downto offset) := over;
    return ret;
  end OVERLAY;

  function OVERLAY (over  : unsigned;
                    under : unsigned)
    return unsigned is
    variable ret : unsigned(under'length-1 downto 0);
  begin
    return OVERLAY(over, under, 0);
  end OVERLAY;

  function EXTRACT (vec    : unsigned;
                    offset : natural;
                    length : natural)
    return unsigned is
  begin
    return vec(offset + length - 1 downto offset);
  end EXTRACT;

end MM;
