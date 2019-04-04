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

// Memory management interface (H2D, request and answer)
`define FLETCHER_REG_MM_HDR_ADDR_LO  6
`define FLETCHER_REG_MM_HDR_ADDR_HI  7
`define FLETCHER_REG_MM_HDR_SIZE_LO  8
`define FLETCHER_REG_MM_HDR_SIZE_HI  9
`define FLETCHER_REG_MM_HDR_REGION  10
`define FLETCHER_REG_MM_HDR_CMD     11
`define FLETCHER_REG_MM_HDA_ADDR_LO 12
`define FLETCHER_REG_MM_HDA_ADDR_HI 13
`define FLETCHER_REG_MM_HDA_STATUS  14

`define NUM_REGISTERS       25

// Offset buffer address in host memory
`define HOST_ADDR           64'h0000000000000000

module test_malloc();

import tb_type_defines_pkg::*;

int num_buf_bytes = 1024 * 4 * 10;

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

  // Host data
  `include "data.sv"

  $display("[%t] : Starting tests", $realtime);

  // Set region to 1
  tb.poke_bar1(.addr(4 * `FLETCHER_REG_MM_HDR_REGION), .data(32'h0000_0001));

  // Set size to 12 MB
  tb.poke_bar1(.addr(4 * `FLETCHER_REG_MM_HDR_SIZE_LO), .data(32'h00c0_0000));
  tb.poke_bar1(.addr(4 * `FLETCHER_REG_MM_HDR_SIZE_HI), .data(32'h0000_0000));

  // Allocate
  tb.poke_bar1(.addr(4 * `FLETCHER_REG_MM_HDR_CMD), .data(32'h0000_0003));

  // Wait for completion

  // Poll status at an interval of 1000 nsec
  // For the real thing, you should probably increase this to put 
  // less stress on the PCI interface
  do
    begin
      tb.nsec_delay(1000);
      tb.peek_bar1(.addr(4 * `FLETCHER_REG_MM_HDA_STATUS), .data(read_data));
      $display("[%t] : Status: %H", $realtime, read_data);
    end
  while(read_data[0] !== 1);

  // Get address
  tb.peek_bar1(.addr(4 * `FLETCHER_REG_MM_HDA_ADDR_LO), .data(read_data_lo));
  tb.peek_bar1(.addr(4 * `FLETCHER_REG_MM_HDA_ADDR_HI), .data(read_data_hi));
  $display("[%t] : malloc of size 12MB at %H_%H", $realtime, read_data_hi, read_data_lo);

  // Reset response
  tb.poke_bar1(.addr(4 * `FLETCHER_REG_MM_HDA_STATUS), .data(32'h0000_0000));



  // Try to write to allocated memory.
  $display("[%t] : Starting host to CL DMA transfers ", $realtime);

  host_buffer_address = `HOST_ADDR;
  cl_buffer_address = {read_data_hi, read_data_lo};

  // Queue the data movement
  tb.que_buffer_to_cl(
    .chan(0),
    .src_addr(host_buffer_address),
    .cl_addr(cl_buffer_address),
    .len(num_buf_bytes)
  );

  // Also write into second and third page. Use an offset into the data,
  // so that the data is not identical for each page.
  tb.que_buffer_to_cl(
    .chan(0),
    .src_addr(host_buffer_address+64),
    .cl_addr(cl_buffer_address + 1024*1024*4),
    .len(num_buf_bytes-64)
  );

  tb.que_buffer_to_cl(
    .chan(0),
    .src_addr(host_buffer_address+128),
    .cl_addr(cl_buffer_address + 1024*1024*8),
    .len(num_buf_bytes-128)
  );

  // Start transfers of data to CL DDR
  tb.start_que_to_cl(.chan(0));

  // Wait for dma transfers to complete,
  // increase the timeout if you have to transfer a lot of data
  timeout_count = 0;
  do begin
    status[0] = tb.is_dma_to_cl_done(.chan(0));
    #10ns;
    timeout_count++;
  end while ((status != 4'hf) && (timeout_count < 4000));

  if (timeout_count >= 4000) begin
    $display(
      "[%t] : *** ERROR *** Timeout waiting for dma transfers from cl",
      $realtime
    );
    error_count++;
  end
  $display("[%t] : Write complete", $realtime);
  // Write is reported complete before response. Wait for duration of shell timeout.
  #8000ns;


  // Readback
  $display("[%t] : Starting CL to host DMA transfers ", $realtime);

  // Queue the data movement
  tb.que_cl_to_buffer(
    .chan(0),
    .dst_addr(host_buffer_address + 1024*1024*4),
    .cl_addr(cl_buffer_address),
    .len(num_buf_bytes)
  );
  tb.que_cl_to_buffer(
    .chan(0),
    .dst_addr(host_buffer_address + 1024*1024*8),
    .cl_addr(cl_buffer_address + 1024*1024*4),
    .len(num_buf_bytes-64)
  );
  tb.que_cl_to_buffer(
    .chan(0),
    .dst_addr(host_buffer_address + 1024*1024*12),
    .cl_addr(cl_buffer_address + 1024*1024*8),
    .len(num_buf_bytes-128)
  );

  // Start transfers of data from CL DDR
  tb.start_que_to_buffer(.chan(0));

  // Wait for dma transfers to complete,
  // increase the timeout if you have to transfer a lot of data
  timeout_count = 0;
  do begin
    status[0] = tb.is_dma_to_buffer_done(.chan(0));
    #10ns;
    timeout_count++;
  end while ((status != 4'hf) && (timeout_count < 4000));

  if (timeout_count >= 4000) begin
    $display(
      "[%t] : *** ERROR *** Timeout waiting for dma transfers from cl",
      $realtime
    );
    error_count++;
  end
  $display("[%t] : Read complete", $realtime);

  for (int i=0; i<num_buf_bytes; i++) begin
    if (tb.hm_get_byte(i    ) != tb.hm_get_byte(i + 1024*1024*4)) begin
      error_count++;
    end
    if (tb.hm_get_byte(i+ 64) != tb.hm_get_byte(i + 1024*1024*8)) begin
      error_count++;
    end
    if (tb.hm_get_byte(i+128) != tb.hm_get_byte(i + 1024*1024*12)) begin
      error_count++;
    end
  end

// Skip large allocation
if (0 == 1) begin
  // Set region to 1
  tb.poke_bar1(.addr(4 * `FLETCHER_REG_MM_HDR_REGION), .data(32'h0000_0001));

  // Set size to 34 GB
  tb.poke_bar1(.addr(4 * `FLETCHER_REG_MM_HDR_ADDR_LO), .data(32'h8000_0000));
  tb.poke_bar1(.addr(4 * `FLETCHER_REG_MM_HDR_ADDR_LO), .data(32'h0000_0008));

  // Allocate
  tb.poke_bar1(.addr(4 * `FLETCHER_REG_MM_HDR_CMD), .data(32'h0000_0003));

  // Wait for completion

  // Poll status at an interval of 1000 nsec
  // For the real thing, you should probably increase this to put 
  // less stress on the PCI interface
  do
    begin
      tb.nsec_delay(1000);
      tb.peek_bar1(.addr(4 * `FLETCHER_REG_MM_HDA_STATUS), .data(read_data));
      $display("[%t] : Status: %H", $realtime, read_data);
    end
  while(read_data[0] !== 1);

  // Get address
  tb.peek_bar1(.addr(4 * `FLETCHER_REG_MM_HDA_ADDR_LO), .data(read_data_lo));
  tb.peek_bar1(.addr(4 * `FLETCHER_REG_MM_HDA_ADDR_HI), .data(read_data_hi));
  $display("[%t] : malloc of size 34GB at %H_%H", $realtime, read_data_hi, read_data_lo);

  // Reset response
  tb.poke_bar1(.addr(4 * `FLETCHER_REG_MM_HDA_STATUS), .data(32'h0000_0000));
end

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
