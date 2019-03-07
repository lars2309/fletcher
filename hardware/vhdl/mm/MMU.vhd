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

entity MMU is
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
    resp_mask                   : out std_logic_vector(BUS_ADDR_WIDTH-1 downto 0)
  );
end MMU;


architecture Behavioral of MMU is
  constant BUS_DATA_BYTES       : natural := BUS_DATA_WIDTH / BYTE_SIZE;
  constant PT_SIZE_LOG2         : natural := PT_ENTRIES_LOG2 + log2ceil(DIV_CEIL(PTE_BITS, BYTE_SIZE));
  constant PTE_SIZE             : natural := 2**log2ceil(DIV_CEIL(PTE_BITS, BYTE_SIZE));
  constant PTE_WIDTH            : natural := PTE_SIZE * BYTE_SIZE;

  function VA_TO_PTE (pt_base : unsigned(BUS_ADDR_WIDTH-1 downto 0);
                      vm_addr : unsigned(BUS_ADDR_WIDTH-1 downto 0);
                      pt_level: natural)
    return unsigned is
    variable index : unsigned(PT_ENTRIES_LOG2-1 downto 0);
    variable ret : unsigned(BUS_ADDR_WIDTH-1 downto 0) := (others => '0');
  begin
    if pt_level = 1 then
      index := EXTRACT(vm_addr, PAGE_SIZE_LOG2 + PT_ENTRIES_LOG2, PT_ENTRIES_LOG2);
    elsif pt_level = 2 then
      index := EXTRACT(vm_addr, PAGE_SIZE_LOG2, PT_ENTRIES_LOG2);
    else
      index := (others => 'X');
    end if;
    return OVERLAY(
      shift_left(
        resize(index, index'length + log2ceil(PTE_SIZE)),
        log2ceil(PTE_SIZE)),
      pt_base);
  end VA_TO_PTE;

  function ADDR_BUS_ALIGN (addr : unsigned(BUS_ADDR_WIDTH-1 downto 0))
    return unsigned is
  begin
    return OVERLAY(to_unsigned(0, log2ceil(BUS_DATA_BYTES)), addr);
  end ADDR_BUS_ALIGN;

  function ADDR_BUS_OFFSET (addr : unsigned(BUS_ADDR_WIDTH-1 downto 0))
    return unsigned is
  begin
    return resize(addr(log2ceil(BUS_DATA_BYTES)-1 downto 0), addr'length);
  end ADDR_BUS_OFFSET;

  type state_type is (RESET_ST, IDLE, FAIL,
                      LOOKUP_L1_ADDR, LOOKUP_L1_DATA,
                      LOOKUP_L2_ADDR, LOOKUP_L2_DATA);

  type reg_type is record
    state                       : state_type;
    addr                        : unsigned(BUS_ADDR_WIDTH-1 downto 0);
    addr_pt                     : unsigned(BUS_ADDR_WIDTH-1 downto 0);
    size                        : unsigned(BUS_ADDR_WIDTH-1 downto 0);
    beat                        : unsigned(log2ceil(BUS_BURST_MAX_LEN+1)-1 downto 0);
  end record;

  signal r                      : reg_type;
  signal d                      : reg_type;

begin

  process (clk) begin
    if rising_edge(clk) then
      if reset = '1' then
        r.state          <= RESET_ST;
        r.addr           <= (others => '0');
        r.addr_pt        <= (others => '0');
        r.size           <= (others => '0');
        r.beat           <= (others => '0');
      else
        r <= d;
      end if;
    end if;
  end process;

  process (r,
           bus_rreq_ready, bus_rdat_data, bus_rdat_last, bus_rdat_valid,
           resp_ready, req_valid, req_addr) is
    variable v : reg_type;
  begin
    v := r;

    bus_rreq_valid       <= '0';
    bus_rreq_len         <= (others => 'U');
    bus_rreq_addr        <= (others => 'U');
    bus_rdat_ready       <= '0';

    req_ready            <= '0';

    resp_valid           <= '0';
    resp_virt            <= (others => 'U');
    resp_phys            <= (others => 'U');
    resp_mask            <= (others => 'U');

    case v.state is

    when RESET_ST =>
      v.state            := IDLE;

    when IDLE =>
      if req_valid = '1' then
        bus_rreq_valid   <= '1';
        bus_rreq_len     <= slv(to_unsigned(1, bus_rreq_len'length));
        bus_rreq_addr    <= slv(ADDR_BUS_ALIGN(VA_TO_PTE(PT_ADDR, u(req_addr), 1)));
        v.addr           := u(req_addr);
        if bus_rreq_ready = '1' then
          v.state        := LOOKUP_L1_DATA;
          req_ready      <= '1';
        end if;
      end if;

    when LOOKUP_L1_DATA =>
      if bus_rdat_valid = '1' then
        -- Select the right PTE from the data bus
        -- and use the resulting address to request the L2 entry.
        v.addr_pt        := align_beq(
            EXTRACT(
              unsigned(bus_rdat_data),
              BYTE_SIZE * int(ADDR_BUS_OFFSET(VA_TO_PTE(PT_ADDR, v.addr, 1))),
              BYTE_SIZE * PTE_SIZE
            ),
            PT_SIZE_LOG2
          );
        bus_rreq_valid   <= '1';
        bus_rreq_len     <= slv(to_unsigned(1, bus_rreq_len'length));
        bus_rreq_addr    <= slv(
            ADDR_BUS_ALIGN(
              VA_TO_PTE(
                v.addr_pt,
                v.addr,
                2)));
        if bus_rreq_ready = '1' then
          v.state      := LOOKUP_L2_DATA;
          bus_rdat_ready <= '1';
        end if;
      end if;

    when LOOKUP_L2_DATA =>
      bus_rdat_ready     <= '1';
      if bus_rdat_valid = '1' then
        resp_valid       <= '1';
        resp_virt        <= slv(v.addr);
        resp_phys        <= slv(align_beq(
            EXTRACT(
              unsigned(bus_rdat_data),
              BYTE_SIZE * int(ADDR_BUS_OFFSET(VA_TO_PTE(v.addr_pt, v.addr, 2))),
              BYTE_SIZE * PTE_SIZE
            ),
            PAGE_SIZE_LOG2
          ));
        -- Create mask for single page
        resp_mask        <= std_logic_vector(shift_left(to_signed(-1, BUS_ADDR_WIDTH), PAGE_SIZE_LOG2));
        if resp_ready = '1' then
          v.state        := IDLE;
          bus_rdat_ready <= '1';
        end if;
      end if;

    when others =>
    end case;

    d <= v;
  end process;
end architecture;

