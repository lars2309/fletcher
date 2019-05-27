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

entity MMGapFinderStep is
  generic (
    MASK_WIDTH                  : natural := 8;
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
end MMGapFinderStep;

architecture Behavioral of MMGapFinderStep is
  constant REI : nat_array := cumulative((
    2 => 1,
    1 => log2ceil(MAX_SIZE+1),
    0 => MASK_WIDTH
  ));
  constant GAI : nat_array := cumulative((
    1 => log2ceil(MAX_SIZE+1),
    0 => log2ceil(MAX_SIZE+1)
  ));

  signal int_req_valid           : std_logic;
  signal int_req_ready           : std_logic;
  signal int_req_last            : std_logic;
  signal int_req_holes           : std_logic_vector(MASK_WIDTH-1 downto 0);
  signal int_req_size            : std_logic_vector(log2ceil(MAX_SIZE+1)-1 downto 0);
  signal int_req_data            : std_logic_vector(REI(REI'high)-1 downto 0);
  signal req_data                : std_logic_vector(REI(REI'high)-1 downto 0);

  signal int_gap_valid           : std_logic;
  signal int_gap_ready           : std_logic;
  signal int_gap_offset          : std_logic_vector(log2ceil(MAX_SIZE+1)-1 downto 0);
  signal int_gap_size            : std_logic_vector(log2ceil(MAX_SIZE+1)-1 downto 0);
  signal int_gap_data            : std_logic_vector(GAI(GAI'high)-1 downto 0);
  signal gap_data                : std_logic_vector(GAI(GAI'high)-1 downto 0);

  type reg_type is record
    size              : unsigned(log2ceil(MAX_SIZE+1)-1 downto 0);
    offset            : unsigned(log2ceil(MAX_SIZE+1)-1 downto 0);
    step              : unsigned(log2ceil((MAX_SIZE+MASK_WIDTH-1)/MASK_WIDTH+1)-1 downto 0);
    send              : std_logic;
    sent              : std_logic;
  end record;

  signal r : reg_type;
  signal d : reg_type;

begin

  reg_proc : process(clk) is
  begin
    if rising_edge(clk) then
      r <= d;
      if reset = '1' then
        r.step   <= (others => '0');
        r.size   <= (others => '0');
        r.offset <= (others => '0');
        r.send   <= '0';
        r.sent   <= '0';
      end if;
    end if;
  end process;

  comb_proc: process(r,
      int_req_valid, int_req_holes, int_req_size, int_gap_ready) is
    variable v : reg_type;
  begin
    v := r;

    if int_req_valid = '1' and v.sent = '0' then
      -- Search for gap in current mask.
      for N in 0 to MASK_WIDTH-1 loop
        -- The gap is already big enough, stop searching.
        exit when v.size = u(int_req_size);
        if int_req_holes(N) = '0' then
          -- Continue the gap.
          v.size             := v.size + 1;
        else
          -- Must start a new gap at the next position.
          v.size             := (others => '0');
          v.offset           := to_unsigned(N + 1, v.offset'length);
          if MAX_SIZE > MASK_WIDTH then
            -- Add the previous inputs to the offset as well.
            v.offset         := v.offset + mul(
                                   resize(v.step, v.offset'length),
                                   MASK_WIDTH
                                 );
          end if;
        end if;
      end loop;
      v.step                 := v.step + 1;

      -- Push the gap when found.
      if v.size = u(int_req_size) or int_req_last = '1' then
        v.send               := '1';
      end if;

    end if;

    -- Set the outputs
    int_gap_valid            <= v.send;
    if v.send = '1' then
      if int_gap_ready = '1' then
        -- Output handshaked, do not keep valid high on next cycle.
        v.send               := '0';
        v.sent               := '1';
      end if;
    end if;
    int_gap_size             <= slv(v.size);
    int_gap_offset           <= slv(v.offset);

    if int_req_last = '1' then
      -- For the last word, wait until the output has been sent.
      if v.sent = '1' then
        int_req_ready        <= '1';
        if int_req_valid = '1' then
          -- The last word is accepted, reset for the next search.
          v.size             := (others => '0');
          v.offset           := (others => '0');
          v.step             := (others => '0');
          v.sent             := '0';
        end if;
      else
        int_req_ready        <= '0';
      end if;
    else
      -- Accept input every cycle.
      int_req_ready          <= '1';
    end if;

    d <= v;
  end process;

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

end architecture;

