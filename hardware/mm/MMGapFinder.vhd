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
use work.Streams.all;

entity MMGapFinder is
  generic (
    MASK_WIDTH                  : natural := 8;
    SLV_SLICE                   : boolean := false;
    MST_SLICE                   : boolean := false
  );
  port (
    clk                         : in  std_logic;
    reset                       : in  std_logic;

    req_valid                   : in  std_logic;
    req_ready                   : out std_logic;
    req_holes                   : in  std_logic_vector(MASK_WIDTH-1 downto 0);
    req_size                    : in  std_logic_vector(log2ceil(MASK_WIDTH+1)-1 downto 0);

    gap_valid                   : out std_logic;
    gap_ready                   : in  std_logic;
    gap_offset                  : out std_logic_vector(log2ceil(MASK_WIDTH+1)-1 downto 0);
    gap_size                    : out std_logic_vector(log2ceil(MASK_WIDTH+1)-1 downto 0)
  );
end MMGapFinder;

architecture Behavioral of MMGapFinder is
  constant REI : nat_array := cumulative((
    1 => log2ceil(MASK_WIDTH+1),
    0 => MASK_WIDTH
  ));
  constant GAI : nat_array := cumulative((
    1 => log2ceil(MASK_WIDTH+1),
    0 => log2ceil(MASK_WIDTH+1)
  ));

  signal int_req_valid           : std_logic;
  signal int_req_ready           : std_logic;
  signal int_req_holes           : std_logic_vector(MASK_WIDTH-1 downto 0);
  signal int_req_size            : std_logic_vector(log2ceil(MASK_WIDTH+1)-1 downto 0);
  signal int_req_data            : std_logic_vector(REI(REI'high)-1 downto 0);
  signal req_data                : std_logic_vector(REI(REI'high)-1 downto 0);

  signal int_gap_valid           : std_logic;
  signal int_gap_ready           : std_logic;
  signal int_gap_offset          : std_logic_vector(log2ceil(MASK_WIDTH+1)-1 downto 0);
  signal int_gap_size            : std_logic_vector(log2ceil(MASK_WIDTH+1)-1 downto 0);
  signal int_gap_data            : std_logic_vector(GAI(GAI'high)-1 downto 0);
  signal gap_data                : std_logic_vector(GAI(GAI'high)-1 downto 0);

begin

  input_slice_gen: if SLV_SLICE generate
  begin
    slice_inst: StreamSlice
      generic map (
        DATA_WIDTH              => req_data'length
      )
      port map (
        clk                     => clk,
        reset                   => reset,
        in_valid                => req_valid,
        in_ready                => req_ready,
        in_data                 => req_data,
        out_valid               => int_req_valid,
        out_ready               => int_req_ready,
        out_data                => int_req_data
      );
    req_data(REI(1)-1 downto REI(0)) <= req_holes;
    req_data(REI(2)-1 downto REI(1)) <= req_size;
    int_req_holes <= int_req_data(REI(1)-1 downto REI(0));
    int_req_size  <= int_req_data(REI(2)-1 downto REI(1));
  end generate;
  no_input_slice_gen: if not SLV_SLICE generate
  begin
    int_req_valid <= req_valid;
    req_ready     <= int_req_ready;
    int_req_holes <= req_holes;
    int_req_size  <= req_size;
  end generate;

  output_slice_gen: if MST_SLICE generate
  begin
    slice_inst: StreamSlice
      generic map (
        DATA_WIDTH              => gap_data'length
      )
      port map (
        clk                     => clk,
        reset                   => reset,
        in_valid                => int_gap_valid,
        in_ready                => int_gap_ready,
        in_data                 => int_gap_data,
        out_valid               => gap_valid,
        out_ready               => gap_ready,
        out_data                => gap_data
      );
    int_gap_data(GAI(1)-1 downto GAI(0)) <= int_gap_offset;
    int_gap_data(GAI(2)-1 downto GAI(1)) <= int_gap_size;
    gap_offset <= gap_data(GAI(1)-1 downto GAI(0));
    gap_size   <= gap_data(GAI(2)-1 downto GAI(1));
  end generate;
  no_output_slice_gen: if not MST_SLICE generate
  begin
    gap_valid     <= int_gap_valid;
    int_gap_ready <= gap_ready;
    gap_offset    <= int_gap_offset;
    gap_size      <= int_gap_size;
  end generate;

  int_gap_valid <= int_req_valid;
  int_req_ready <= int_gap_ready;

  comb_proc: process(int_req_holes, int_req_size) is
    variable csize : unsigned(log2ceil(MASK_WIDTH+1)-1 downto 0);
    variable start : unsigned(log2ceil(MASK_WIDTH+1)-1 downto 0);
  begin
    csize := (others => '0');
    start := (others => '0');
    for N in 0 to MASK_WIDTH-1 loop
      if int_req_holes(N) = '0' then
        csize := csize + 1;
      else
        csize := (others => '0');
        start := to_unsigned(N + 1, start'length);
      end if;
      exit when csize = u(int_req_size);
    end loop;

    int_gap_offset <= slv(start);
    int_gap_size   <= slv(csize);
  end process;
end architecture;

