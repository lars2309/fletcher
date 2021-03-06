library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
entity Kernel is
  generic (
    BUS_ADDR_WIDTH : integer := 64
  );
  port (
    kcd_clk                       : in  std_logic;
    kcd_reset                     : in  std_logic;
    mmio_awvalid                  : in  std_logic;
    mmio_awready                  : out std_logic;
    mmio_awaddr                   : in  std_logic_vector(31 downto 0);
    mmio_wvalid                   : in  std_logic;
    mmio_wready                   : out std_logic;
    mmio_wdata                    : in  std_logic_vector(31 downto 0);
    mmio_wstrb                    : in  std_logic_vector(3 downto 0);
    mmio_bvalid                   : out std_logic;
    mmio_bready                   : in  std_logic;
    mmio_bresp                    : out std_logic_vector(1 downto 0);
    mmio_arvalid                  : in  std_logic;
    mmio_arready                  : out std_logic;
    mmio_araddr                   : in  std_logic_vector(31 downto 0);
    mmio_rvalid                   : out std_logic;
    mmio_rready                   : in  std_logic;
    mmio_rdata                    : out std_logic_vector(31 downto 0);
    mmio_rresp                    : out std_logic_vector(1 downto 0);
    MyNumbers_number_valid        : in  std_logic;
    MyNumbers_number_ready        : out std_logic;
    MyNumbers_number_dvalid       : in  std_logic;
    MyNumbers_number_last         : in  std_logic;
    MyNumbers_number              : in  std_logic_vector(63 downto 0);
    MyNumbers_number_cmd_valid    : out std_logic;
    MyNumbers_number_cmd_ready    : in  std_logic;
    MyNumbers_number_cmd_firstIdx : out std_logic_vector(31 downto 0);
    MyNumbers_number_cmd_lastidx  : out std_logic_vector(31 downto 0);
    MyNumbers_number_cmd_ctrl     : out std_logic_vector(1*bus_addr_width-1 downto 0);
    MyNumbers_number_cmd_tag      : out std_logic_vector(0 downto 0);
    MyNumbers_number_unl_valid    : in  std_logic;
    MyNumbers_number_unl_ready    : out std_logic;
    MyNumbers_number_unl_tag      : in  std_logic_vector(0 downto 0)
  );
end entity;
architecture Implementation of Kernel is
begin
end architecture;
