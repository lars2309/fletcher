-- Copyright 2018 Delft University of Technology
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
use ieee.std_logic_misc.all;
use IEEE.numeric_std.all;

library work;
use work.Utils.all;

entity sum is
    generic(
      SUM_UNITS                                  : natural := 1;
      TAG_WIDTH                                  : natural;
      BUS_ADDR_WIDTH                             : natural;
      INDEX_WIDTH                                : natural;
      REG_WIDTH                                  : natural
    );
    port(
      weight4_out_last                           : in std_logic;
      weight5_out_last                           : in std_logic;
      weight5_out_ready                          : out std_logic;
      weight5_out_valid                          : in std_logic;
      weight4_cmd_weight4_values_addr            : out std_logic_vector(BUS_ADDR_WIDTH-1 downto 0);
      weight4_cmd_tag                            : out std_logic_vector(TAG_WIDTH-1 downto 0);
      weight4_cmd_lastIdx                        : out std_logic_vector(INDEX_WIDTH-1 downto 0);
      weight4_cmd_firstIdx                       : out std_logic_vector(INDEX_WIDTH-1 downto 0);
      weight4_cmd_ready                          : in std_logic;
      weight4_cmd_valid                          : out std_logic;
      weight4_out_data                           : in std_logic_vector(63 downto 0);
      weight5_out_data                           : in std_logic_vector(63 downto 0);
      weight4_out_ready                          : out std_logic;
      weight4_out_valid                          : in std_logic;
      weight3_cmd_weight3_values_addr            : out std_logic_vector(BUS_ADDR_WIDTH-1 downto 0);
      weight3_cmd_tag                            : out std_logic_vector(TAG_WIDTH-1 downto 0);
      weight3_cmd_lastIdx                        : out std_logic_vector(INDEX_WIDTH-1 downto 0);
      weight3_cmd_firstIdx                       : out std_logic_vector(INDEX_WIDTH-1 downto 0);
      weight3_cmd_ready                          : in std_logic;
      weight3_cmd_valid                          : out std_logic;
      weight3_out_data                           : in std_logic_vector(63 downto 0);
      weight6_out_data                           : in std_logic_vector(63 downto 0);
      weight7_out_last                           : in std_logic;
      weight7_out_ready                          : out std_logic;
      weight7_out_valid                          : in std_logic;
      weight6_cmd_weight6_values_addr            : out std_logic_vector(BUS_ADDR_WIDTH-1 downto 0);
      weight6_cmd_tag                            : out std_logic_vector(TAG_WIDTH-1 downto 0);
      weight6_cmd_lastIdx                        : out std_logic_vector(INDEX_WIDTH-1 downto 0);
      weight6_cmd_firstIdx                       : out std_logic_vector(INDEX_WIDTH-1 downto 0);
      weight6_cmd_ready                          : in std_logic;
      weight6_cmd_valid                          : out std_logic;
      weight3_out_last                           : in std_logic;
      weight6_out_last                           : in std_logic;
      weight6_out_ready                          : out std_logic;
      weight6_out_valid                          : in std_logic;
      weight5_cmd_weight5_values_addr            : out std_logic_vector(BUS_ADDR_WIDTH-1 downto 0);
      weight5_cmd_tag                            : out std_logic_vector(TAG_WIDTH-1 downto 0);
      weight5_cmd_lastIdx                        : out std_logic_vector(INDEX_WIDTH-1 downto 0);
      weight5_cmd_firstIdx                       : out std_logic_vector(INDEX_WIDTH-1 downto 0);
      weight5_cmd_ready                          : in std_logic;
      weight5_cmd_valid                          : out std_logic;
      weight0_out_last                           : in std_logic;
      weight1_out_ready                          : out std_logic;
      weight1_out_valid                          : in std_logic;
      weight0_cmd_weight0_values_addr            : out std_logic_vector(BUS_ADDR_WIDTH-1 downto 0);
      weight0_cmd_tag                            : out std_logic_vector(TAG_WIDTH-1 downto 0);
      weight0_cmd_lastIdx                        : out std_logic_vector(INDEX_WIDTH-1 downto 0);
      weight0_cmd_firstIdx                       : out std_logic_vector(INDEX_WIDTH-1 downto 0);
      weight0_cmd_ready                          : in std_logic;
      weight0_cmd_valid                          : out std_logic;
      weight0_out_data                           : in std_logic_vector(63 downto 0);
      weight1_out_last                           : in std_logic;
      weight0_out_ready                          : out std_logic;
      weight0_out_valid                          : in std_logic;
      weight7_out_data                           : in std_logic_vector(63 downto 0);
      weight7_cmd_valid                          : out std_logic;
      weight7_cmd_ready                          : in std_logic;
      weight7_cmd_firstIdx                       : out std_logic_vector(INDEX_WIDTH-1 downto 0);
      weight7_cmd_lastIdx                        : out std_logic_vector(INDEX_WIDTH-1 downto 0);
      weight7_cmd_tag                            : out std_logic_vector(TAG_WIDTH-1 downto 0);
      weight7_cmd_weight7_values_addr            : out std_logic_vector(BUS_ADDR_WIDTH-1 downto 0);
      weight2_out_last                           : in std_logic;
      weight3_out_ready                          : out std_logic;
      weight3_out_valid                          : in std_logic;
      weight2_cmd_weight2_values_addr            : out std_logic_vector(BUS_ADDR_WIDTH-1 downto 0);
      weight2_cmd_tag                            : out std_logic_vector(TAG_WIDTH-1 downto 0);
      weight2_cmd_lastIdx                        : out std_logic_vector(INDEX_WIDTH-1 downto 0);
      weight2_cmd_firstIdx                       : out std_logic_vector(INDEX_WIDTH-1 downto 0);
      weight2_cmd_ready                          : in std_logic;
      weight2_cmd_valid                          : out std_logic;
      weight2_out_data                           : in std_logic_vector(63 downto 0);
      weight2_out_ready                          : out std_logic;
      weight2_out_valid                          : in std_logic;
      weight1_cmd_weight1_values_addr            : out std_logic_vector(BUS_ADDR_WIDTH-1 downto 0);
      weight1_cmd_tag                            : out std_logic_vector(TAG_WIDTH-1 downto 0);
      weight1_cmd_lastIdx                        : out std_logic_vector(INDEX_WIDTH-1 downto 0);
      weight1_cmd_firstIdx                       : out std_logic_vector(INDEX_WIDTH-1 downto 0);
      weight1_cmd_ready                          : in std_logic;
      weight1_cmd_valid                          : out std_logic;
      weight1_out_data                           : in std_logic_vector(63 downto 0);
      -------------------------------------------------------------------------
      acc_reset                                  : in std_logic;
      acc_clk                                    : in std_logic;
      -------------------------------------------------------------------------
      ctrl_busy                                  : out std_logic;
      ctrl_idle                                  : out std_logic;
      ctrl_reset                                 : in std_logic;
      ctrl_stop                                  : in std_logic;
      ctrl_start                                 : in std_logic;
      ctrl_done                                  : out std_logic;
      -------------------------------------------------------------------------
      reg_return0                                : out std_logic_vector(REG_WIDTH-1 downto 0);
      reg_return1                                : out std_logic_vector(REG_WIDTH-1 downto 0);
      idx_last                                   : in std_logic_vector(REG_WIDTH-1 downto 0);
      idx_first                                  : in std_logic_vector(REG_WIDTH-1 downto 0);
      -------------------------------------------------------------------------
      reg_weight0_values_addr                    : in std_logic_vector(BUS_ADDR_WIDTH-1 downto 0);
      reg_weight1_values_addr                    : in std_logic_vector(BUS_ADDR_WIDTH-1 downto 0);
      reg_weight2_values_addr                    : in std_logic_vector(BUS_ADDR_WIDTH-1 downto 0);
      reg_weight3_values_addr                    : in std_logic_vector(BUS_ADDR_WIDTH-1 downto 0);
      reg_weight4_values_addr                    : in std_logic_vector(BUS_ADDR_WIDTH-1 downto 0);
      reg_weight5_values_addr                    : in std_logic_vector(BUS_ADDR_WIDTH-1 downto 0);
      reg_weight6_values_addr                    : in std_logic_vector(BUS_ADDR_WIDTH-1 downto 0);
      reg_weight7_values_addr                    : in std_logic_vector(BUS_ADDR_WIDTH-1 downto 0)
    );
end entity sum;


architecture rtl of sum is

  component sum_unit is
    generic(
      REG_WIDTH : natural
    );
    port(
      reset : in  std_logic;
      clk   : in  std_logic;
      ready : out std_logic;
      valid : in  std_logic;
      last  : in  std_logic;
      data  : in  std_logic_vector(63 downto 0);
      done  : out std_logic;
      accum : out std_logic_vector(63 downto 0)
    );
  end component;

  type haf_state_t IS (RESET, WAITING, SETUP, RUNNING, DONE);
	signal state, state_next : haf_state_t;

  signal rst : std_logic;
  signal accumulator : signed(2*REG_WIDTH-1 downto 0);

  -- Individual sums of each sum unit
  type sums_t is array (7 downto 0) of std_logic_vector(63 downto 0);
  signal sx_sums  : sums_t;
  -- Individual input data for each sum unit
  signal sx_data  : sums_t;

  -- Individual sum unit to corresponding ColumnReader signals
  signal sx_ready : std_logic_vector(7 downto 0);
  signal sx_valid : std_logic_vector(7 downto 0);
  signal sx_last  : std_logic_vector(7 downto 0);
  signal sx_done  : std_logic_vector(7 downto 0);

  signal weightx_cmd_ready : std_logic_vector(7 downto 0);
  signal weightx_cmd_valid : std_logic_vector(7 downto 0);
  signal weightx_cmd_valid_next : std_logic_vector(7 downto 0);

begin

  -- Merge reset signals
  rst <= acc_reset or ctrl_reset;

  -- Module output is the accumulator value
  reg_return0 <= std_logic_vector(accumulator(1*REG_WIDTH-1 downto 0*REG_WIDTH));
  reg_return1 <= std_logic_vector(accumulator(2*REG_WIDTH-1 downto 1*REG_WIDTH));

  -- Provide base address to ColumnReaders
  -- Use the first base address, the runtime will only give a single buffer
  weight0_cmd_weight0_values_addr <= reg_weight0_values_addr;
  weight1_cmd_weight1_values_addr <= reg_weight0_values_addr;
  weight2_cmd_weight2_values_addr <= reg_weight0_values_addr;
  weight3_cmd_weight3_values_addr <= reg_weight0_values_addr;
  weight4_cmd_weight4_values_addr <= reg_weight0_values_addr;
  weight5_cmd_weight5_values_addr <= reg_weight0_values_addr;
  weight6_cmd_weight6_values_addr <= reg_weight0_values_addr;
  weight7_cmd_weight7_values_addr <= reg_weight0_values_addr;

  -- We're not using command tags
  weight0_cmd_tag <= (others => '0');
  weight1_cmd_tag <= (others => '0');
  weight2_cmd_tag <= (others => '0');
  weight3_cmd_tag <= (others => '0');
  weight4_cmd_tag <= (others => '0');
  weight5_cmd_tag <= (others => '0');
  weight6_cmd_tag <= (others => '0');
  weight7_cmd_tag <= (others => '0');

  weight0_cmd_valid <= weightx_cmd_valid(0);
  weight1_cmd_valid <= weightx_cmd_valid(1);
  weight2_cmd_valid <= weightx_cmd_valid(2);
  weight3_cmd_valid <= weightx_cmd_valid(3);
  weight4_cmd_valid <= weightx_cmd_valid(4);
  weight5_cmd_valid <= weightx_cmd_valid(5);
  weight6_cmd_valid <= weightx_cmd_valid(6);
  weight7_cmd_valid <= weightx_cmd_valid(7);

  weightx_cmd_ready(0) <= weight0_cmd_ready;
  weightx_cmd_ready(1) <= weight1_cmd_ready;
  weightx_cmd_ready(2) <= weight2_cmd_ready;
  weightx_cmd_ready(3) <= weight3_cmd_ready;
  weightx_cmd_ready(4) <= weight4_cmd_ready;
  weightx_cmd_ready(5) <= weight5_cmd_ready;
  weightx_cmd_ready(6) <= weight6_cmd_ready;
  weightx_cmd_ready(7) <= weight7_cmd_ready;

  -- To support port mapping in the generate statements
  weight0_out_ready <= sx_ready(0);
  weight1_out_ready <= sx_ready(1);
  weight2_out_ready <= sx_ready(2);
  weight3_out_ready <= sx_ready(3);
  weight4_out_ready <= sx_ready(4);
  weight5_out_ready <= sx_ready(5);
  weight6_out_ready <= sx_ready(6);
  weight7_out_ready <= sx_ready(7);

  sx_valid(0) <= weight0_out_valid;
  sx_valid(1) <= weight1_out_valid;
  sx_valid(2) <= weight2_out_valid;
  sx_valid(3) <= weight3_out_valid;
  sx_valid(4) <= weight4_out_valid;
  sx_valid(5) <= weight5_out_valid;
  sx_valid(6) <= weight6_out_valid;
  sx_valid(7) <= weight7_out_valid;

  sx_last(0) <= weight0_out_last;
  sx_last(1) <= weight1_out_last;
  sx_last(2) <= weight2_out_last;
  sx_last(3) <= weight3_out_last;
  sx_last(4) <= weight4_out_last;
  sx_last(5) <= weight5_out_last;
  sx_last(6) <= weight6_out_last;
  sx_last(7) <= weight7_out_last;

  sx_data(0) <= weight0_out_data;
  sx_data(1) <= weight1_out_data;
  sx_data(2) <= weight2_out_data;
  sx_data(3) <= weight3_out_data;
  sx_data(4) <= weight4_out_data;
  sx_data(5) <= weight5_out_data;
  sx_data(6) <= weight6_out_data;
  sx_data(7) <= weight7_out_data;

  -- Distribute work over units
  work_p: process (idx_first, idx_last)
    variable num_rows  : unsigned(REG_WIDTH-1 downto 0);
    variable step_size : unsigned(REG_WIDTH-log2floor(SUM_UNITS)-1 downto 0);
  begin
    num_rows := unsigned(idx_last) - unsigned(idx_first);
    -- Underestimate step_size, the remainder will be added to the last unit
    step_size := num_rows(REG_WIDTH-1 downto log2floor(SUM_UNITS));

    -- Always start with the given first row
    weight0_cmd_firstIdx <= idx_first;

    weight0_cmd_lastIdx  <= std_logic_vector(resize(
          unsigned(idx_first) + step_size * 1,
          REG_WIDTH ));
    weight1_cmd_firstIdx <= std_logic_vector(resize(
          unsigned(idx_first) + step_size * 1,
          REG_WIDTH ));

    if SUM_UNITS = 2 then
      -- End with the given last row if this is the last unit
      weight1_cmd_lastIdx  <= idx_last;
    else
      weight1_cmd_lastIdx  <= std_logic_vector(resize(
            unsigned(idx_first) + step_size * 2,
            REG_WIDTH ));
    end if;
    weight2_cmd_firstIdx <= std_logic_vector(resize(
          unsigned(idx_first) + step_size * 2,
          REG_WIDTH ));

    if SUM_UNITS = 3 then
      weight2_cmd_lastIdx  <= idx_last;
    else
      weight2_cmd_lastIdx  <= std_logic_vector(resize(
            unsigned(idx_first) + step_size * 3,
            REG_WIDTH ));
    end if;
    weight3_cmd_firstIdx <= std_logic_vector(resize(
          unsigned(idx_first) + step_size * 3,
          REG_WIDTH ));

    if SUM_UNITS = 4 then
      weight3_cmd_lastIdx  <= idx_last;
    else
      weight3_cmd_lastIdx  <= std_logic_vector(resize(
            unsigned(idx_first) + step_size * 4,
            REG_WIDTH ));
    end if;
    weight4_cmd_firstIdx <= std_logic_vector(resize(
          unsigned(idx_first) + step_size * 4,
          REG_WIDTH ));

    if SUM_UNITS = 5 then
      weight4_cmd_lastIdx  <= idx_last;
    else
      weight4_cmd_lastIdx  <= std_logic_vector(resize(
            unsigned(idx_first) + step_size * 5,
            REG_WIDTH ));
    end if;
    weight5_cmd_firstIdx <= std_logic_vector(resize(
          unsigned(idx_first) + step_size * 5,
          REG_WIDTH ));

    if SUM_UNITS = 6 then
      weight5_cmd_lastIdx  <= idx_last;
    else
      weight5_cmd_lastIdx  <= std_logic_vector(resize(
            unsigned(idx_first) + step_size * 6,
            REG_WIDTH ));
    end if;
    weight6_cmd_firstIdx <= std_logic_vector(resize(
          unsigned(idx_first) + step_size * 6,
          REG_WIDTH ));

    if SUM_UNITS = 7 then
      weight6_cmd_lastIdx  <= idx_last;
    else
      weight6_cmd_lastIdx  <= std_logic_vector(resize(
            unsigned(idx_first) + step_size * 7,
            REG_WIDTH ));
    end if;
    weight7_cmd_firstIdx <= std_logic_vector(resize(
          unsigned(idx_first) + step_size * 7,
          REG_WIDTH ));
    weight7_cmd_lastIdx  <= idx_last;
  end process;


  -- Instantiate sum units
  gen_sum:
  for I in 0 to SUM_UNITS-1 generate
    sumx : sum_unit
    generic map(
      REG_WIDTH => REG_WIDTH
    )
    port map(
      reset => rst,
      clk   => acc_clk,
      ready => sx_ready(I),
      valid => sx_valid(I),
      last  => sx_last(I),
      data  => sx_data(I),
      done  => sx_done(I),
      accum => sx_sums(I)
    );
  end generate gen_sum;

  -- Tie off connections for unused sum unit positions
  gen_sum_open:
  for I in SUM_UNITS to 7 generate
    sx_ready(I) <= '0';
    sx_done(I)  <= '1';
    sx_sums(I)  <= (others => '0');
  end generate gen_sum_open;

  -- Aggregate sums of units
  accumulator <=
      signed(sx_sums(0)) +
      signed(sx_sums(1)) +
      signed(sx_sums(2)) +
      signed(sx_sums(3)) +
      signed(sx_sums(4)) +
      signed(sx_sums(5)) +
      signed(sx_sums(6)) +
      signed(sx_sums(7));


  -- Main state machine
  logic_p: process (state, ctrl_start,
    sx_done, weightx_cmd_ready, weightx_cmd_valid)
  begin
    -- Default values
    -- Wait for commands to be accepted
    weightx_cmd_valid_next <= weightx_cmd_valid;
    -- Stay in same state
    state_next <= state;

    case state is
      when RESET =>
        ctrl_done <= '0';
        ctrl_busy <= '0';
        ctrl_idle <= '0';
        state_next <= WAITING;

      when WAITING =>
        ctrl_done <= '0';
        ctrl_busy <= '0';
        ctrl_idle <= '1';

        -- Wait for start signal from UserCore (initiated by software)
        if ctrl_start = '1' then
          state_next <= SETUP;
          -- Send address and row indices to the ColumnReaders that are in use
          weightx_cmd_valid_next <= std_logic_vector(to_unsigned(2**SUM_UNITS-1, 8));
        end if;

      when SETUP =>
        ctrl_done <= '0';
        ctrl_busy <= '1';
        ctrl_idle <= '0';

        -- Wait for each reader to accept the command
        weightx_cmd_valid_next <= weightx_cmd_valid and (not weightx_cmd_ready);
        if unsigned(not weightx_cmd_ready(SUM_UNITS-1 downto 0)) = 0 then
          -- All ColumnReaders have received the command
          state_next <= RUNNING;
        end if;

      when RUNNING =>
        ctrl_done <= '0';
        ctrl_busy <= '1';
        ctrl_idle <= '0';

        -- Wait for all units to be ready
        if sx_done = "11111111" then
          state_next <= DONE;
        end if;

      when DONE =>
        ctrl_done <= '1';
        ctrl_busy <= '0';
        ctrl_idle <= '1';

      when others =>
        ctrl_done <= '0';
        ctrl_busy <= '0';
        ctrl_idle <= '0';
    end case;
  end process;


  state_p: process (acc_clk)
  begin
    -- Control state machine
    if rising_edge(acc_clk) then
      if rst = '1' then
        state <= RESET;
        weightx_cmd_valid <= (others => '0');
      else
        state <= state_next;
        weightx_cmd_valid <= weightx_cmd_valid_next;
      end if;
    end if;
  end process;

end architecture; --sum



library ieee;
use ieee.std_logic_1164.all;
use ieee.std_logic_misc.all;
use IEEE.numeric_std.all;

library work;

-- Simple accumulator for a single column reader
entity sum_unit is
  generic(
    REG_WIDTH : natural
  );
  port(
    reset : in  std_logic;
    clk   : in  std_logic;
    ready : out std_logic;
    valid : in  std_logic;
    last  : in  std_logic;
    data  : in  std_logic_vector(63 downto 0);
    done  : out std_logic;
    accum : out std_logic_vector(63 downto 0)
  );
end entity;

architecture rtl of sum_unit is
  -- Accumulate the total sum here
  signal accumulator, accumulator_next : signed(2*REG_WIDTH-1 downto 0);
begin
  ready <= '1'; -- We're always ready for new data
  accum <= std_logic_vector(accumulator);
  accumulator_next <= accumulator + signed(data);

  state_p: process (clk)
  begin
    if rising_edge(clk) then

      if reset = '1' then
        accumulator <= (others => '0');
        done <= '0';

      elsif valid = '1' then -- Only apply addition when input data is valid
        accumulator <= accumulator_next;

        if last = '1' then
          done <= '1';
        end if;

      end if;
    end if; --rising_edge
  end process; --state_p
end architecture; --sum_unit

