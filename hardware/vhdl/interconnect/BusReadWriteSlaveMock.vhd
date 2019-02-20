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
use ieee.math_real.all;

library work;
use work.Memory.all;
use work.Utils.all;
use work.Streams.all;
use work.StreamSim.all;
use work.Interconnect.all;
use work.SimUtils.all;

-- This simulation-only unit is a mockup of a bus slave that can either write 
-- to an S-record file, or simply accept and print the written data on stdout.
-- The handshake signals can be randomized.

entity BusReadWriteSlaveMock is
  generic (

    -- Bus address width.
    BUS_ADDR_WIDTH              : natural := 32;

    -- Bus burst length width.
    BUS_LEN_WIDTH               : natural := 8;

    -- Bus data width.
    BUS_DATA_WIDTH              : natural := 32;
    
    -- Bus strobe width
    BUS_STROBE_WIDTH            : natural := 32/8;

    -- Random seed. This should be different for every instantiation if
    -- randomized handshake signals are used.
    SEED                        : positive := 1;

    -- Whether to randomize the request stream handshake timing.
    RANDOM_REQUEST_TIMING       : boolean := true;

    -- Whether to randomize the request stream handshake timing.
    RANDOM_RESPONSE_TIMING      : boolean := true;

    -- S-record file to dump writes. If not specified, the unit dumps the 
    -- writes on stdout
    SREC_FILE                   : string := ""

  );
  port (

    -- Rising-edge sensitive clock and active-high synchronous reset for the
    -- bus and control logic side of the BufferReader.
    clk                         : in  std_logic;
    reset                       : in  std_logic;

    -- Bus write interface.
    wreq_valid                  : in  std_logic;
    wreq_ready                  : out std_logic;
    wreq_addr                   : in  std_logic_vector(BUS_ADDR_WIDTH-1 downto 0);
    wreq_len                    : in  std_logic_vector(BUS_LEN_WIDTH-1 downto 0);
    wdat_valid                  : in  std_logic;
    wdat_ready                  : out std_logic;
    wdat_data                   : in  std_logic_vector(BUS_DATA_WIDTH-1 downto 0);
    wdat_strobe                 : in  std_logic_vector(BUS_STROBE_WIDTH-1 downto 0);
    wdat_last                   : in  std_logic;

    -- Bus read interface.
    rreq_valid                  : in  std_logic;
    rreq_ready                  : out std_logic := '0';
    rreq_addr                   : in  std_logic_vector(BUS_ADDR_WIDTH-1 downto 0);
    rreq_len                    : in  std_logic_vector(BUS_LEN_WIDTH-1 downto 0);
    rdat_valid                  : out std_logic := '0';
    rdat_ready                  : in  std_logic;
    rdat_data                   : out std_logic_vector(BUS_DATA_WIDTH-1 downto 0);
    rdat_last                   : out std_logic

  );
end BusReadWriteSlaveMock;

architecture Behavioral of BusReadWriteSlaveMock is

  signal wreq_cons_valid        : std_logic;
  signal wreq_cons_ready        : std_logic;

  signal wreq_int_valid         : std_logic;
  signal wreq_int_ready         : std_logic;

  signal wdat_prod_valid        : std_logic;
  signal wdat_prod_ready        : std_logic;

  signal wdat_int_valid         : std_logic;
  signal wdat_int_ready         : std_logic;
  

  signal rreq_cons_valid        : std_logic;
  signal rreq_cons_ready        : std_logic;

  signal rreq_int_valid         : std_logic;
  signal rreq_int_ready         : std_logic;

  signal rdat_prod_valid        : std_logic;
  signal rdat_prod_ready        : std_logic;

  signal rdat_int_valid         : std_logic;
  signal rdat_int_ready         : std_logic;

  signal rdat_out_valid         : std_logic;

  signal accept_req             : std_logic;

begin

  random_request_timing_gen: if RANDOM_REQUEST_TIMING generate
  begin

    -- Request consumer and synchronizer. These two units randomize the rate at
    -- which requests are consumed.
    consumer_sync: StreamSync
      generic map (
        NUM_INPUTS                => 1,
        NUM_OUTPUTS               => 2
      )
      port map (
        clk                       => clk,
        reset                     => reset,
        in_valid(0)               => rreq_valid,
        in_ready(0)               => rreq_ready,
        out_valid(1)              => rreq_cons_valid,
        out_valid(0)              => rreq_int_valid,
        out_ready(1)              => rreq_cons_ready,
        out_ready(0)              => rreq_int_ready
      );

    consumer_inst: StreamTbCons
      generic map (
        SEED                      => SEED
      )
      port map (
        clk                       => clk,
        reset                     => reset,
        in_valid                  => rreq_cons_valid,
        in_ready                  => rreq_cons_ready,
        in_data                   => (others => '0')
      );

  end generate;

  fast_request_timing_gen: if not RANDOM_REQUEST_TIMING generate
  begin
    rreq_int_valid <= rreq_valid;
    rreq_ready <= rreq_int_ready;
  end generate;

  process (accept_req, wreq_valid) is
  begin
    if accept_req = '0' then
      wreq_ready <= '0';
      rreq_int_ready <= '0';
    elsif wreq_valid = '1' then
      wreq_ready <= '1';
      rreq_int_ready <= '0';
    else
      wreq_ready <= '0';
      rreq_int_ready <= '1';
    end if;
  end process;

  -- Request handler. First accepts and ready's a command, then outputs the a
  -- response burst as fast as possible.
  process is
    variable len    : natural;
    variable addr   : unsigned(63 downto 0);
    variable data   : std_logic_vector(BUS_DATA_WIDTH-1 downto 0);
    variable wdata  : std_logic_vector(BUS_DATA_WIDTH-1 downto 0);
    variable mem    : mem_state_type;
  begin
    mem_clear(mem);
    if SREC_FILE /= "" then
      mem_loadSRec(mem, SREC_FILE);
    end if;

    state: loop

      -- Reset state.
      wdat_ready <= '0';
      rdat_int_valid <= '0';
      rdat_data <= (others => 'U');
      rdat_last <= 'U';
      accept_req <= '0';

      accept_req <= '1';
      loop
        wait until rising_edge(clk);
        exit state when reset = '1';
        exit when wreq_valid = '1' or rreq_int_valid = '1';
      end loop;

      if wreq_valid = '1' then
      
        addr := resize(unsigned(wreq_addr), 64);
        len := to_integer(unsigned(wreq_len));

        -- Stop accepting new requests after handshake
        wait for 0 ns;
        accept_req <= '0';

        for i in 0 to len-1 loop

          -- Accept the incoming data
          wdat_ready <= '1';
          
          -- Wait for response ready.
          loop
            wait until rising_edge(clk);
            exit state when reset = '1';
            exit when wdat_valid = '1';
          end loop;
          
          -- Print or dump the data to an SREC file
          mem_read(mem, std_logic_vector(addr), data);
          wdata := (others => '-');
          for i in 0 to wdat_strobe'length-1 loop
            if wdat_strobe(i) = '1' then
              data(8*(i+1)-1  downto 8*i) := wdat_data(8*(i+1)-1  downto 8*i);
              wdata(8*(i+1)-1  downto 8*i) := wdat_data(8*(i+1)-1  downto 8*i);
            end if;
          end loop;
          mem_write(mem, std_logic_vector(addr), data);
          if (SREC_FILE = "") then
            dumpStdOut("Write > " & sim_hex_no0x(std_logic_vector(addr)) & " > " & sim_hex_no0x(wdata));
          else
            mem_dumpSRec(mem, SREC_FILE);
          end if;
          
          -- Check the last signal
          if i = len-1 then
            assert wdat_last = '1'
              report "Last was not asserted."
              severity failure;
          end if;

          addr := addr + (BUS_DATA_WIDTH / 8);

        end loop;
        wait for 0 ns;

        -- Stop accepting data
        wdat_ready <= '0';
      end if; -- wreq_valid = '1'

      if rreq_int_valid = '1' then
        addr := resize(unsigned(rreq_addr), 64);
        len := to_integer(unsigned(rreq_len));

        -- Stop accepting new requests after handshake
        wait for 0 ns;
        accept_req <= '0';

        for i in 0 to len-1 loop

          -- Figure out what data to respond with.
          mem_read(mem, std_logic_vector(addr), data);

          -- Assert response.
          rdat_int_valid <= '1';
          wait until rdat_out_valid = '1';
          rdat_data <= data;
          if i = len-1 then
            rdat_last <= '1';
          else
            rdat_last <= '0';
          end if;

          -- Wait for response ready.
          loop
            wait until rising_edge(clk);
            exit state when reset = '1';
            exit when rdat_int_ready = '1';
          end loop;
          wait for 0 ns;
          rdat_last <= 'U';
          rdat_data <= (others => 'U');

          addr := addr + (BUS_DATA_WIDTH / 8);

        end loop;
      end if; -- rreq_int_valid = '1'

    end loop;
  end process;

  random_response_timing_gen: if RANDOM_RESPONSE_TIMING generate
  begin

    -- Response producer and synchronizer. These two units randomize the rate at
    -- which burst beats are generated.
    producer_inst: StreamTbProd
      generic map (
        SEED                      => SEED + 31415
      )
      port map (
        clk                       => clk,
        reset                     => reset,
        out_valid                 => rdat_prod_valid,
        out_ready                 => rdat_prod_ready
      );

    producer_sync: StreamSync
      generic map (
        NUM_INPUTS                => 2,
        NUM_OUTPUTS               => 1
      )
      port map (
        clk                       => clk,
        reset                     => reset,
        in_valid(1)               => rdat_prod_valid,
        in_valid(0)               => rdat_int_valid,
        in_ready(1)               => rdat_prod_ready,
        in_ready(0)               => rdat_int_ready,
        out_valid(0)              => rdat_out_valid,
        out_ready(0)              => rdat_ready
      );

  end generate;

  fast_response_timing_gen: if not RANDOM_RESPONSE_TIMING generate
  begin
    rdat_out_valid <= rdat_int_valid;
    rdat_int_ready <= rdat_ready;
  end generate;

  rdat_valid <= rdat_out_valid;

end Behavioral;

