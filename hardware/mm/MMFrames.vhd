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
use work.UtilInt_pkg.all;
use work.UtilConv_pkg.all;
use work.UtilRam_pkg.all;
use work.MM_pkg.all;

entity MMFrames is
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
    cmd_action                  : in  std_logic_vector(MM_FRAMES_CMD_WIDTH-1 downto 0);
    cmd_valid                   : in  std_logic;
    cmd_ready                   : out std_logic;

    resp_addr                   : out std_logic_vector(BUS_ADDR_WIDTH-1 downto 0);
    resp_success                : out std_logic;
    resp_valid                  : out std_logic;
    resp_ready                  : in  std_logic
  );
end MMFrames;


architecture Behavioral of MMFrames is
  constant TOTAL_FRAMES_LOG2    : natural := log2ceil(sum(MEM_SIZES));

  function PAGE_TO_FRAME (addr_in : std_logic_vector(BUS_ADDR_WIDTH-1 downto 0))
                    return unsigned is
    variable addr   : unsigned(BUS_ADDR_WIDTH-1 downto 0);
    variable frame  : unsigned(TOTAL_FRAMES_LOG2-1 downto 0);
    variable region : natural;
  begin
    if xor_reduct(addr_in) /= '0' and xor_reduct(addr_in) /= '1' then
      frame := (others => 'X');
      return frame;
    end if;
    addr := unsigned(addr_in);
    addr(PAGE_SIZE_LOG2-1 downto 0) := (others => '0');
    if addr < MEM_MAP_BASE then
      frame := (others => 'X');
      return frame;
    end if;
    addr := addr - MEM_MAP_BASE;
    region := 0;
    frame := to_unsigned(0, frame'length);
    while addr > LOG2_TO_UNSIGNED(MEM_MAP_SIZE_LOG2) loop
      addr := addr - LOG2_TO_UNSIGNED(MEM_MAP_SIZE_LOG2);
      frame := frame + MEM_SIZES(region);
      region := region + 1;
      exit when region = MEM_REGIONS;
    end loop;
    frame := frame + addr(TOTAL_FRAMES_LOG2 + PAGE_SIZE_LOG2 - 1 downto PAGE_SIZE_LOG2);
    return unsigned(frame);
  end PAGE_TO_FRAME;

  function FRAME_TO_PAGE (frame_in : unsigned(TOTAL_FRAMES_LOG2-1 downto 0))
                    return std_logic_vector is
    variable addr   : unsigned(BUS_ADDR_WIDTH-1 downto 0);
    variable frame  : unsigned(TOTAL_FRAMES_LOG2-1 downto 0);
    variable region : natural;
  begin
    if xor_reduct(slv(frame_in)) /= '0' and xor_reduct(slv(frame_in)) /= '1' then
      addr := (others => 'X');
      return slv(addr);
    end if;
    frame := unsigned(frame_in);
    region := 0;
    addr := MEM_MAP_BASE;
    while frame >= MEM_SIZES(region) loop
      addr := addr + LOG2_TO_UNSIGNED(MEM_MAP_SIZE_LOG2);
      frame := frame - MEM_SIZES(region);
      region := region + 1;
      exit when region = MEM_REGIONS;
    end loop;
    addr := addr + (frame & to_unsigned(0, PAGE_SIZE_LOG2));
    return std_logic_vector(addr);
  end FRAME_TO_PAGE;

  function PAGE_TO_REGION (addr_in : std_logic_vector(BUS_ADDR_WIDTH-1 downto 0))
                    return natural is
    variable addr   : unsigned(BUS_ADDR_WIDTH-1 downto 0);
    variable region : natural;
  begin
    if xor_reduct(addr_in) /= '0' and xor_reduct(addr_in) /= '1' then
      region := 0;
      return region;
    end if;
    addr := unsigned(addr_in);
    if addr < MEM_MAP_BASE then
      return 0;
    end if;
    addr := addr - MEM_MAP_BASE;
    region := 0;
    while addr > LOG2_TO_UNSIGNED(MEM_MAP_SIZE_LOG2) loop
      addr := addr - LOG2_TO_UNSIGNED(MEM_MAP_SIZE_LOG2);
      region := region + 1;
      exit when region = MEM_REGIONS;
    end loop;
    return region;
  end PAGE_TO_REGION;

  function REGION_TO_FRAME (region : natural)
                    return unsigned is
    variable frame : unsigned(TOTAL_FRAMES_LOG2-1 downto 0);
  begin
    frame := (others => '0');
    if region > 0 then
      for i in 0 to region-1 loop
        frame := frame + MEM_SIZES(i);
      end loop;
    end if;
    return frame;
  end REGION_TO_FRAME;

  signal r_addr                 : std_logic_vector(TOTAL_FRAMES_LOG2-1 downto 0);
  signal w_addr                 : std_logic_vector(TOTAL_FRAMES_LOG2-1 downto 0);
  signal r_data                 : std_logic_vector(0 downto 0);
  signal w_data                 : std_logic_vector(0 downto 0);
  signal w_en                   : std_logic;
  signal region, region_next    : unsigned(log2ceil(MEM_REGIONS)-1 downto 0);
  signal frame, frame_next      : unsigned(TOTAL_FRAMES_LOG2-1 downto 0);
  type rover_t is array (0 to MEM_REGIONS-1) of unsigned(TOTAL_FRAMES_LOG2-1 downto 0);
  signal roving_ptr, roving_ptr_next : rover_t;

  type state_type is (IDLE, CLEAR, ALLOC_CHECK, ALLOC_APPLY,
                      FREE, FIND, FIND_LOOP, FIND_DONE, SUCCESS, FAIL);
  signal state, state_next      : state_type;
begin

  process (clk) begin
    if rising_edge(clk) then
      if reset = '1' then
        state  <= IDLE;
        region <= (others => '0');
        frame  <= (others => '0');
        for I in 0 to MEM_REGIONS-1 loop
          roving_ptr(I) <= REGION_TO_FRAME(I);
        end loop;
      else
        state  <= state_next;
        region <= region_next;
        frame  <= frame_next;
        roving_ptr <= roving_ptr_next;
      end if;
    end if;
  end process;

  process (state, region, frame, roving_ptr, r_data,
           cmd_addr, cmd_region, cmd_valid, cmd_action, resp_ready) begin
    state_next   <= state;
    frame_next   <= frame;
    region_next  <= region;
    roving_ptr_next <= roving_ptr;
    resp_addr    <= (others => '0');
    resp_success <= '0';
    resp_valid   <= '0';
    cmd_ready    <= '0';
    w_data       <= "0";
    w_en         <= '0';
    w_addr       <= std_logic_vector(frame);
    r_addr       <= std_logic_vector(frame);

    case state is

    when IDLE =>
      cmd_ready <= '1';

      if cmd_valid = '1' then
        case cmd_action is
        when MM_FRAMES_ALLOC =>
          state_next  <= ALLOC_CHECK;
          region_next <= to_unsigned(PAGE_TO_REGION(cmd_addr), region'length);
          frame_next  <= PAGE_TO_FRAME(cmd_addr);

        when MM_FRAMES_FREE =>
          state_next  <= FREE;
          frame_next  <= PAGE_TO_FRAME(cmd_addr);

        when MM_FRAMES_CLEAR =>
          state_next  <= CLEAR;
          frame_next  <= (others => '0');

        when MM_FRAMES_FIND =>
          state_next  <= FIND;
          region_next <= unsigned(cmd_region);
          frame_next  <= roving_ptr(to_integer(unsigned(cmd_region)));

        when others =>
        end case;
      end if;

    when CLEAR =>
      frame_next <= frame + 1;
      w_data     <= "0";
      w_en       <= '1';
      if frame = sum(MEM_SIZES)-1 then
        state_next <= SUCCESS;
        frame_next <= frame;
      end if;

    when ALLOC_CHECK =>
      state_next  <= ALLOC_APPLY;

    when ALLOC_APPLY =>
      if r_data = "0" then
        state_next <= SUCCESS;
        w_data     <= "1";
        w_en       <= '1';
      else
        state_next <= FIND;
        frame_next <= roving_ptr(to_integer(unsigned(region)));
      end if;

    when FREE =>
      state_next <= SUCCESS;
      w_data     <= "0";
      w_en       <= '1';

    when FIND =>
      state_next <= FIND_LOOP;
      if frame + 1 = REGION_TO_FRAME(to_integer(region)+1) then
        frame_next <= REGION_TO_FRAME(to_integer(region));
      else
        frame_next <= frame + 1;
      end if;

    when FIND_LOOP =>
      if frame + 1 = REGION_TO_FRAME(to_integer(region)+1) then
        frame_next <= REGION_TO_FRAME(to_integer(region));
      else
        frame_next <= frame + 1;
      end if;
      if r_data = "0" then
        state_next <= FIND_DONE;
        frame_next <= frame - 1;
        roving_ptr_next(to_integer(region)) <= frame;
      elsif frame = roving_ptr(to_integer(region)) then
        state_next <= FAIL;
      end if;

    when FIND_DONE =>
      state_next <= SUCCESS;
      w_data     <= "1";
      w_en       <= '1';

    when SUCCESS =>
      resp_valid   <= '1';
      resp_addr    <= FRAME_TO_PAGE(frame);
      resp_success <= '1';
      if resp_ready = '1' then
        state_next <= IDLE;
      end if;

    when FAIL =>
      resp_valid   <= '1';
      resp_addr    <= FRAME_TO_PAGE(frame);
      resp_success <= '0';
      if resp_ready = '1' then
        state_next <= IDLE;
      end if;

    when others =>
      resp_valid   <= '1';
      resp_success <= '0';
    end case;
  end process;

  frame_mem : UtilRam1R1W
    generic map (
      -- Width of a data word.
      WIDTH                     => 1,
      -- Depth of the memory as log2(depth in words).
      DEPTH_LOG2                => TOTAL_FRAMES_LOG2
    )
    port map (
      w_clk                       => clk,
      w_ena                       => w_en,
      w_addr                      => w_addr,
      w_data                      => w_data,

      r_clk                       => clk,
      r_addr                      => r_addr,
      r_data                      => r_data
    );

end architecture;


