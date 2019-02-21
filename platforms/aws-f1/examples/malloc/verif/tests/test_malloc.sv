// Amazon FPGA Hardware Development Kit
//
// Copyright 2016 Amazon.com, Inc. or its affiliates. All Rights Reserved.
//
// Licensed under the Amazon Software License (the "License"). You may not use
// this file except in compliance with the License. A copy of the License is
// located at
//
//    http://aws.amazon.com/asl/
//
// or in the "license" file accompanying this file. This file is distributed on
// an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, express or
// implied. See the License for the specific language governing permissions and
// limitations under the License.


// Register offsets & some default values:
`define REG_STATUS          1
`define   STATUS_BUSY       32'h00000002
`define   STATUS_DONE       32'h00000005

`define REG_CONTROL         0
`define   CONTROL_START     32'h00000001
`define   CONTROL_RESET     32'h00000004

`define REG_RETURN_HI       3
`define REG_RETURN_LO       2

`define REG_OFF_ADDR_HI     4+3
`define REG_OFF_ADDR_LO     4+2

`define REG_DATA_ADDR_HI    4+5
`define REG_DATA_ADDR_LO    4+4

// Registers for first and last (exclusive) row index
`define REG_FIRST_IDX       4+0
`define REG_LAST_IDX        4+1

`define NUM_REGISTERS       10

// Offset buffer address in host memory
`define HOST_ADDR           64'h0000000000000000

module test_malloc();

import tb_type_defines_pkg::*;

int         error_count;
int         timeout_count;
int         fail;
logic [3:0] status;
logic       ddr_ready;
int         read_data;
int         read_data_lo;
int         read_data_hi;

int temp;

union {
  logic[63:0] i;
  logic[7:0][7:0] bytes;
} buf_data;

initial begin

  logic[63:0] host_buffer_address;
  logic[63:0] cl_buffer_address;

  // Power up the testbench
  tb.power_up(.clk_recipe_a(ClockRecipe::A1),
              .clk_recipe_b(ClockRecipe::B0),
              .clk_recipe_c(ClockRecipe::C0));

  tb.nsec_delay(1000);

  tb.poke_stat(.addr(8'h0c), .ddr_idx(0), .data(32'h0000_0000));
  tb.poke_stat(.addr(8'h0c), .ddr_idx(1), .data(32'h0000_0000));
  tb.poke_stat(.addr(8'h0c), .ddr_idx(2), .data(32'h0000_0000));

  // Allow memory to initialize
  tb.nsec_delay(27000);


  $display("[%t] : Starting tests", $realtime);

  // Set region to 1
  tb.poke_bar1(.addr(4 * 4), .data(32'h0000_0001));

  // Set size to 3 GB
  tb.poke_bar1(.addr(4 * 2), .data(32'hc000_0000));
  tb.poke_bar1(.addr(4 * 3), .data(32'h0000_0000));

  // Allocate
  tb.poke_bar1(.addr(4 * 5), .data(32'h0000_0011));

  // Wait for completion

  // Poll status at an interval of 2000 nsec
  // For the real thing, you should probably increase this to put 
  // less stress on the PCI interface
  do
    begin
      tb.nsec_delay(2000);
      tb.peek_bar1(.addr(4 * 8), .data(read_data));
      $display("[%t] : Status: %H", $realtime, read_data);
    end
  while(read_data[0] !== 1);

  // Get address
  tb.peek_bar1(.addr(4 * 6), .data(read_data_lo));
  tb.peek_bar1(.addr(4 * 7), .data(read_data_hi));
  $display("[%t] : malloc of size 3GB at %H_%H", $realtime, read_data_hi, read_data_lo);

  // Reset response
  tb.poke_bar1(.addr(4 * 8), .data(32'h0000_0000));



  // Set region to 1
  tb.poke_bar1(.addr(4 * 4), .data(32'h0000_0001));

  // Set size to 34 GB
  tb.poke_bar1(.addr(4 * 2), .data(32'h8000_0000));
  tb.poke_bar1(.addr(4 * 3), .data(32'h0000_0008));

  // Allocate
  tb.poke_bar1(.addr(4 * 5), .data(32'h0000_0003));

  // Wait for completion

  // Poll status at an interval of 2000 nsec
  // For the real thing, you should probably increase this to put 
  // less stress on the PCI interface
  do
    begin
      tb.nsec_delay(2000);
      tb.peek_bar1(.addr(4 * 8), .data(read_data));
      $display("[%t] : Status: %H", $realtime, read_data);
    end
  while(read_data[0] !== 1);

  // Get address
  tb.peek_bar1(.addr(4 * 6), .data(read_data_lo));
  tb.peek_bar1(.addr(4 * 7), .data(read_data_hi));
  $display("[%t] : malloc of size 34GB at %H_%H", $realtime, read_data_hi, read_data_lo);

  // Reset response
  tb.poke_bar1(.addr(4 * 8), .data(32'h0000_0000));


  // Report pass/fail status
  $display("[%t] : Checking total error count...", $realtime);
  if (error_count > 0) begin
    fail = 1;
    // Debug print of all registers
    for (int i=0; i<`NUM_REGISTERS; i++) begin
      tb.peek_bar1(.addr(i*4), .data(read_data));
      $display("[DEBUG] : Register %d: %H", i, read_data);
    end
  end

  $display(
    "[%t] : Detected %3d errors during this test",
    $realtime, error_count
  );

  if (fail || (tb.chk_prot_err_stat())) begin
    $display("[%t] : *** TEST FAILED ***", $realtime);
  end else begin
    $display("[%t] : *** TEST PASSED ***", $realtime);
  end


  // Power down
  #500ns;
  tb.power_down();

  $finish;
end // initial begin

endmodule // test_arrow_sum
