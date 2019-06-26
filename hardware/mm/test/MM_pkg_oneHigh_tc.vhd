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
use ieee.numeric_std.all;

library work;
use work.MM_pkg.all;

--pragma simulation timeout 1 ms

entity MM_pkg_oneHigh_tc is
  generic (
    ---------------------------------------------------------------------------
    -- TEST BENCH
    ---------------------------------------------------------------------------
    TbPeriod                    : time    := 4 ns
  );
end MM_pkg_oneHigh_tc;

architecture tb of MM_pkg_oneHigh_tc is
  signal TbClock                : std_logic := '0';
  signal TbSimEnded             : std_logic := '0';
begin

  -- Clock generation
  TbClock <= not TbClock after TbPeriod/2 when TbSimEnded /= '1' else '0';

  process
    variable inp : std_logic_vector(30 downto 0);
  begin

    -- Various sizes of all zeros
    inp := (others => '0');
    for size in 1 to inp'high loop
      wait until rising_edge(TbClock);
      if ONE_HIGH(inp(size-1 downto 0)) then
        report "oneHigh: zero vector should return false" severity failure;
      end if;
    end loop;

    -- Various sizes with only one bit high
    for size in 1 to inp'high loop
      for idx in 0 to size-1 loop
        inp := (others => '0');
        inp(idx) := '1';
        wait until rising_edge(TbClock);
        if not ONE_HIGH(inp(size-1 downto 0)) then
          report "oneHigh: single bit high should return true" severity failure;
        end if;
      end loop;
    end loop;

    -- Various sizes with two bits high
    for size in 1 to inp'high loop
      for idxa in 0 to size-1 loop
        for idxb in 0 to size-1 loop
          if idxa /= idxb then
            inp := (others => '0');
            inp(idxa) := '1';
            inp(idxb) := '1';
            wait until rising_edge(TbClock);
            if ONE_HIGH(inp(size-1 downto 0)) then
              report "oneHigh: two bits high should return false" severity failure;
            end if;
          end if;
        end loop;
      end loop;
    end loop;

    -- Various sizes with all bits high
    inp := (others => '1');
    for size in 2 to inp'high loop
      wait until rising_edge(TbClock);
      if ONE_HIGH(inp(size-1 downto 0)) then
        report "oneHigh: all bits high should return false" severity failure;
      end if;
    end loop;

    -- Various sizes with thermometer test
    for size in 3 to inp'high loop
      inp := (others => '0');
      inp(0) := '1';
      for level in 1 to size-1 loop
        inp(level) := '1';
        wait until rising_edge(TbClock);
        if ONE_HIGH(inp(size-1 downto 0)) then
          report "oneHigh: thermometer above 1 should return false" severity failure;
        end if;
      end loop;
    end loop;

    TbSimEnded <= '1';
    wait;
  end process;

end architecture;
