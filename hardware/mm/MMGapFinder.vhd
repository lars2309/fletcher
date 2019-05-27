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
use work.MM.all;

entity MMGapFinder is
  generic (
    -- Must be a multiple of the internal width when the `last' signal is used.
    MASK_WIDTH                  : natural := 8;
    MASK_WIDTH_INTERNAL         : natural := 64;
    MAX_SIZE                    : natural := 8;
    SLV_SLICE                   : boolean := false;
    MST_SLICE                   : boolean := false
  );
  port (
    clk                         : in  std_logic;
    reset                       : in  std_logic;

    req_valid                   : in  std_logic;
    req_ready                   : out std_logic;
    req_holes                   : in  std_logic_vector(MASK_WIDTH-1 downto 0);
    req_size                    : in  std_logic_vector(log2ceil(MAX_SIZE+1)-1 downto 0);
    req_last                    : in  std_logic := '1';

    gap_valid                   : out std_logic;
    gap_ready                   : in  std_logic;
    gap_offset                  : out std_logic_vector(log2ceil(MAX_SIZE+1)-1 downto 0);
    gap_size                    : out std_logic_vector(log2ceil(MAX_SIZE+1)-1 downto 0)
  );
end MMGapFinder;

architecture Behavioral of MMGapFinder is
  constant SIZE_WIDTH : natural := log2ceil(MAX_SIZE+1);
  -- Mask width that will be evaluated sequentially by the subcomponent.
  constant MASK_WIDTH_SUB : natural := work.Utils.min(MASK_WIDTH, MASK_WIDTH_INTERNAL);
  -- Find multiple of MASK_WIDTH_SUB to cover the original mask.
  constant MASK_WIDTH_MUL : natural := ((MASK_WIDTH+MASK_WIDTH_SUB-1)/MASK_WIDTH_SUB)*MASK_WIDTH_SUB;

  constant REI : nat_array := cumulative((
    2 => 1,
    1 => SIZE_WIDTH,
    0 => MASK_WIDTH
  ));

  signal int_req_valid           : std_logic;
  signal int_req_ready           : std_logic;
  signal int_req_last            : std_logic;
  signal int_req_holes           : std_logic_vector(MASK_WIDTH-1 downto 0);
  signal int_req_size            : std_logic_vector(SIZE_WIDTH-1 downto 0);
  signal int_req_data            : std_logic_vector(REI(REI'high)-1 downto 0);
  signal req_data                : std_logic_vector(REI(REI'high)-1 downto 0);

  signal sub_req_valid           : std_logic;
  signal sub_req_ready           : std_logic;
  signal sub_req_last            : std_logic;
  signal sub_req_holes           : std_logic_vector(MASK_WIDTH_SUB-1 downto 0);
  signal sub_req_size            : std_logic_vector(SIZE_WIDTH-1 downto 0);
  signal sub_req_data            : std_logic_vector(REI(REI'high)-1 downto 0);

begin

  gapfinder_inst : MMGapFinderStep
    generic map (
      MASK_WIDTH                  => MASK_WIDTH_SUB,
      MAX_SIZE                    => MAX_SIZE,
      SLV_SLICE                   => false,
      MST_SLICE                   => MST_SLICE
    )
    port map (
      clk                         => clk,
      reset                       => reset,
      req_valid                   => sub_req_valid,
      req_ready                   => sub_req_ready,
      req_holes                   => sub_req_holes,
      req_size                    => sub_req_size,
      req_last                    => sub_req_last,

      gap_valid                   => gap_valid,
      gap_ready                   => gap_ready,
      gap_offset                  => gap_offset,
      gap_size                    => gap_size
    );

  serializer_gen: if MASK_WIDTH /= MASK_WIDTH_SUB generate
      signal in_data  : std_logic_vector(MASK_WIDTH_MUL + SIZE_WIDTH - 1 downto 0);
      signal out_data : std_logic_vector(MASK_WIDTH_SUB + SIZE_WIDTH - 1 downto 0);
    begin
    serializer_inst: StreamSerializer
      generic map (
        -- Width of the serialized part of the output stream data vector.
        DATA_WIDTH                  => MASK_WIDTH_SUB,
        CTRL_WIDTH                  => SIZE_WIDTH,
        IN_COUNT_MAX                => MASK_WIDTH_MUL/MASK_WIDTH_SUB,
        IN_COUNT_WIDTH              => log2ceil(MASK_WIDTH/MASK_WIDTH_SUB),
        OUT_COUNT_MAX               => 1
      )
      port map (
        clk                         => clk,
        reset                       => reset,
        in_valid                    => int_req_valid,
        in_ready                    => int_req_ready,
        in_data                     => in_data,
        in_last                     => int_req_last,
        out_valid                   => sub_req_valid,
        out_ready                   => sub_req_ready,
        out_data                    => out_data,
        out_last                    => sub_req_last
      );
      in_data(MASK_WIDTH - 1 downto 0)                               <= int_req_holes;
      -- Fill remaining bits when input MASK_WIDTH is not a multiple of the
      -- internal MASK_WIDTH.
      in_data(MASK_WIDTH_MUL - 1 downto MASK_WIDTH)                  <= (others => '1');
      in_data(MASK_WIDTH_MUL + SIZE_WIDTH - 1 downto MASK_WIDTH_MUL) <= int_req_size;
      sub_req_holes <= out_data(MASK_WIDTH_SUB - 1 downto 0);
      sub_req_size  <= out_data(MASK_WIDTH_SUB + SIZE_WIDTH - 1 downto MASK_WIDTH_SUB);
  end generate;

  no_serializer_gen: if MASK_WIDTH = MASK_WIDTH_SUB generate
  begin
    sub_req_valid            <= int_req_valid;
    int_req_ready            <= sub_req_ready;
    sub_req_size             <= int_req_size;
    sub_req_holes            <= int_req_holes;
    sub_req_last             <= int_req_last;
  end generate;

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
    req_data(REI(2))                 <= req_last;
    int_req_holes <= int_req_data(REI(1)-1 downto REI(0));
    int_req_size  <= int_req_data(REI(2)-1 downto REI(1));
    int_req_last  <= int_req_data(REI(2));
  end generate;
  no_input_slice_gen: if not SLV_SLICE generate
  begin
    int_req_valid <= req_valid;
    req_ready     <= int_req_ready;
    int_req_holes <= req_holes;
    int_req_size  <= req_size;
    int_req_last  <= req_last;
  end generate;

end architecture;

