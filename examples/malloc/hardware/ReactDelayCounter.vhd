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

entity ReactDelayCounter is
  generic (
    COUNT_WIDTH                 : natural := 32
  );
  port (
    clk                         : in  std_logic;
    reset                       : in  std_logic;

    req_valid                   : in  std_logic;
    req_ready                   : in  std_logic;
    resp_valid                  : in  std_logic;
    resp_ready                  : in  std_logic;

    delay                       : out std_logic_vector(COUNT_WIDTH-1 downto 0)
  );
end ReactDelayCounter;


architecture Behavioral of ReactDelayCounter is

  type reg_type is record
    counter      : unsigned(COUNT_WIDTH-1 downto 0);
    counting     : std_logic;
    accepted     : std_logic;
  end record;

  signal r : reg_type;
  signal d : reg_type;

begin

  process (clk) is
  begin
    if rising_edge(clk) then
      if reset = '1' then
        r.counting <= '0';
        r.accepted <= '1';
      end if;
    end if;
  end process;

  process (r, req_valid, resp_valid, req_ready, resp_ready) is
    variable v : reg_type;
  begin
    v := r;

    if req_valid = '1' then
      if v.counting = '0' and v.accepted = '1' then
        v.counter  := (others => '0');
        v.accepted := '0';
      end if;
      if req_ready = '1' then
        v.accepted := '1';
      end if;
      v.counting   := '1';
    end if;

    if resp_valid = '1' then
      v.counting   := '0';
    end if;

    if v.counting = '1' then
      v.counter    := v.counter + 1;
    end if;

    d <= v;
  end process;

  delay <= slv(r.counter);

end architecture;

