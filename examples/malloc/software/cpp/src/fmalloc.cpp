// Copyright 2018 Delft University of Technology
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

/**
 * Fletcher device malloc test software
 *
 */
#include <stdlib.h>
#include <stdint.h>
#include <unistd.h>
#include <limits>
#include <chrono>
#include <cstdint>
#include <memory>
#include <vector>
#include <utility>
#include <numeric>
#include <iostream>
#include <iomanip>
#include <fstream>
#include <random>
#include <sys/mman.h>

// Apache Arrow
#include <arrow/api.h>

// Fletcher
#include <fletcher/api.h>


#define PRINT_TIME(X, S) std::cout << std::setprecision(10) << (X) << " " << (S) << std::endl << std::flush
#define PRINT_INT(X, S) std::cout << std::dec << (X) << " " << (S) << std::endl << std::flush

#define FLETCHER_ALIGNMENT 4096
#define BUS_DATA_BYTES 64
#define PERIOD 0.000000004

using fletcher::Timer;

double calc_sum(const std::vector<double> &values) {
  return accumulate(values.begin(), values.end(), 0.0);
}

uint32_t calc_sum(const std::vector<uint32_t> &values) {
  return static_cast<uint32_t>(accumulate(values.begin(), values.end(), 0.0));
}

uint64_t get_addr_mask(uint64_t buffer_size, int burst_len) {
  uint64_t addr_mask = ~ 0L;
  for (int i=0; i<64; i++) {
    if ( ((buffer_size-1) >> i) == 0 ) {
      addr_mask >>= (64-i);
      break;
    }
  }
  for (int i=0; i<64; i++) {
    if ( ((burst_len*BUS_DATA_BYTES-1) >> i) == 0) {
      addr_mask &= (~ 0L) << i;
      break;
    }
  }
  return addr_mask;
}

void device_bench(std::shared_ptr<fletcher::Platform> platform, 
    int reg_offset, uint32_t burst_len, uint32_t bursts,
    da_t base_addr, uint64_t addr_mask) {
  std::cerr << "running device benchmarker...";
  uint32_t control = 0;
  uint32_t status;
  uint32_t base_addr_lo = (uint32_t) base_addr;
  uint32_t base_addr_hi = (uint32_t) (base_addr >> 32);
  uint32_t addr_mask_lo = (uint32_t) addr_mask;
  uint32_t addr_mask_hi = (uint32_t) (addr_mask >> 32);
  uint32_t cycles_per_word = 0;
  uint32_t cycles;
  platform->WriteMMIO(reg_offset+2, burst_len);
  platform->WriteMMIO(reg_offset+3, bursts);
  platform->WriteMMIO(reg_offset+4, base_addr_lo);
  platform->WriteMMIO(reg_offset+5, base_addr_hi);
  platform->WriteMMIO(reg_offset+6, addr_mask_lo);
  platform->WriteMMIO(reg_offset+7, addr_mask_hi);
  platform->WriteMMIO(reg_offset+8, cycles_per_word);
  // Reset
  control = 4;
  platform->WriteMMIO(reg_offset+0, control);
  // Start
  control = 1;
  platform->WriteMMIO(reg_offset+0, control);
  // Deassert start
  control = 0;
  platform->WriteMMIO(reg_offset+0, control);
  // Wait until done
  do {
    usleep(2000);
    platform->ReadMMIO(reg_offset+1, &status);
  } while (status == 2);
  if (status != 4) {
    std::cerr << "ERROR" << std::endl;
    std::cerr << std::flush;
  } else {
    std::cerr << "finished" << std::endl;
    std::cerr << std::flush;
    platform->ReadMMIO(reg_offset+9, &cycles);
    uint64_t num_bytes =  BUS_DATA_BYTES * burst_len * bursts;
    int throughput = (num_bytes/(cycles*PERIOD))/1000/1000;
    std::cout << cycles << " cycles for " << bursts << " bursts of length "
        << burst_len << " (" << (num_bytes/1024) << " KiB)" << std::endl;
    std::cout << "D_R: " << throughput << " MB/s" << std::endl << std::flush;
  }
}

/**
 * Main function for the example.
 * Generates list of numbers, runs k-means on CPU and on FPGA.
 * Finally compares the results.
 */
int main(int argc, char ** argv) {
  int status = EXIT_SUCCESS;

  bool bench_HD = true;
  bool bench_device = true;
  bool bench_alloc = true;
  bool bench_dealloc = true;
  bool bench_realloc = true;

  for (int i = 1; i < argc; i++) {
    if (argv[i][0] == '0') {
      switch (i) {
      case 1:
        bench_HD = false; break;
      case 2:
        bench_device = false; break;
      case 3:
        bench_alloc = false; break;
      case 4:
        bench_dealloc = false; break;
      case 5:
        bench_realloc = false; break;
      }
    }
  }

  // Maximum for page size 2^18 and 2^13 page table entries. (16TiB)
  //const int64_t alloc_max = 1024L*1024*1024* 16384;
  // 1/3rd of maximum size, for realloc to be possible.
  const int64_t alloc_max = 1024L*1024*1024* 5461;
  //const int64_t alloc_max = 1024L*1024*1024* 32;
  const uint64_t max_data_size = 1024L*1024*1024*4; // Max 4GB for data copies.

  std::vector<uint64_t> malloc_sizes;
  malloc_sizes.push_back(1024L*1024 *1);         //  1 MB, sub-page
  malloc_sizes.push_back(1024L*1024 *4);         //  4 MB, page
  malloc_sizes.push_back(1024L*1024 *64);        // 64 MB
  malloc_sizes.push_back(1024L*1024*1024*2);       //  2 GB
//  malloc_sizes.push_back(1024L*1024*1024);       //  1 GB
//  malloc_sizes.push_back(1024L*1024*1024);       //  1 GB
//  malloc_sizes.push_back(1024L*1024*1024);       //  1 GB
  malloc_sizes.push_back(1024L*1024*1024* 32-1); // 32 GB, full L2 page table, one less
  malloc_sizes.push_back(1024L*1024*1024* 32);   // 32 GB, full L2 page table, exact
  malloc_sizes.push_back(1024L*1024*1024* 32+1); // 32 GB, full L2 page table, one more
  malloc_sizes.push_back(1024L*1024*1024* 64);
  malloc_sizes.push_back(1024L*1024*1024* 128);
  malloc_sizes.push_back(1024L*1024*1024* 256);
  malloc_sizes.push_back(1024L*1024*1024* 512);
  malloc_sizes.push_back(1024L*1024*1024* 1024); //  1 TB

  int n_mallocs = malloc_sizes.size();

  int benchmark_buffer = 3;

  // Initialize FPGA
  std::shared_ptr<fletcher::Platform> platform;
  std::shared_ptr<fletcher::Context> context;

  fletcher::Platform::Make(&platform);
  fletcher::Context::Make(&context, platform);

  platform->Init();

  Timer t;
  std::vector<double> t_alloc(n_mallocs);
  std::vector<double> t_write(n_mallocs);
  std::vector<double> t_read(n_mallocs);
  std::vector<da_t> maddr(n_mallocs);


  std::vector<uint8_t*> source_buffers;

  if (bench_HD || bench_device) {
    // Allocate memory on device
    for (int i = 0; i < n_mallocs; i++) {
      t.start();
      platform->DeviceMalloc(&maddr[i], malloc_sizes[i]);
      t.stop();
      t_alloc[i] = t.seconds();
      int throughput = malloc_sizes[i] / t.seconds() / 1000/1000/1000;
      std::cout << "Alloc[" << i << "]: " << throughput << " GB/s";
      std::cout << " (" << malloc_sizes[i] << " B)" << std::endl;
    }

    // Check allocations
    for (int i = 0; i < n_mallocs; i++) {
      std::cout << "device malloc of " << std::setw(12) << std::hex << malloc_sizes[i] << " bytes at " << maddr[i] << " " << std::dec;
      PRINT_TIME(t_alloc[i], "");
      if (i > 0 && maddr[i-1] + malloc_sizes[i-1] > maddr[i]) {
        std::cout << "ERROR: overlapping allocation" << std::endl;
        status = EXIT_FAILURE;
      }
    }

    // Put some data on the device.
    std::ifstream file("/dev/urandom");
    for (int i = 0; i < n_mallocs; i++) {
      if (malloc_sizes[i] <= max_data_size) {
        void* map = mmap(NULL,
            malloc_sizes[i],
            PROT_READ|PROT_WRITE, MAP_PRIVATE|MAP_ANONYMOUS|MAP_POPULATE|MAP_HUGETLB,
            -1, 0);
        source_buffers.push_back((unsigned char *) map);
        if (source_buffers.back() == nullptr) {
          std::cerr << "Could not allocate " << malloc_sizes[i] << " bytes" << std::endl;
          status = EXIT_FAILURE;
          break;
        } else {
          file.read((char *) source_buffers.back(), malloc_sizes[i]);
          std::cerr << "copying buffer to device...";
          // Copy data
          t.start();
          platform->CopyHostToDevice(source_buffers.back(), maddr[i], malloc_sizes[i]);
          t.stop();
          t_write[i] = t.seconds();
          std::cerr << "done" << std::endl;
          if (bench_HD) {
            int throughput = malloc_sizes[i] / t.seconds() / 1000/1000;
            std::cout << "H2D[" << i << "]: " << throughput << " MB/s";
            std::cout << " (" << malloc_sizes[i] << " B)" << std::endl;
          }
        }
      } else {
        source_buffers.push_back((unsigned char*) nullptr);
        t_write[i] = 0;
      }
    }
  }

  if (bench_HD) {
    // Read back written data.
    std::vector<uint8_t*> check_buffers;
    for (int i = 0; i < n_mallocs; i++) {
      if (malloc_sizes[i] <= max_data_size) {
        t.start();
        void* map = mmap(NULL,
            malloc_sizes[i],
            PROT_READ|PROT_WRITE, MAP_PRIVATE|MAP_ANONYMOUS|MAP_POPULATE|MAP_HUGETLB,
            -1, 0);
        t.stop();
        PRINT_TIME(t.seconds(), "mmap");
        check_buffers.push_back((unsigned char *) map);
        if (check_buffers.back() == nullptr) {
          std::cerr << "Could not allocate " << malloc_sizes[i] << " bytes." << std::endl;
          status = EXIT_FAILURE;
          break;
        } else {
          // Copy data
          std::cerr << "copying buffer from device...";
          t.start();
          platform->CopyDeviceToHost(maddr[i], check_buffers.back(), malloc_sizes[i]);
          t.stop();
          t_read[i] = t.seconds();
          std::cerr << "done" << std::endl;
          int throughput = malloc_sizes[i] / t.seconds() / 1000/1000;
          std::cout << "D2H[" << i << "]: " << throughput << " MB/s";
          std::cout << " (" << malloc_sizes[i] << " B)" << std::endl;
          if (memcmp(check_buffers.back(), source_buffers.at(i), malloc_sizes[i])) {
            std::cerr << "ERROR: Data does not match for buffer " << i << "." << std::endl;
            status = EXIT_FAILURE;
          }
        }
      } else {
        t_read[i] = 0;
      }
    }
  }

  if (bench_device) {
    // Use hardware benchmarker
    if (benchmark_buffer >= 0) {

      da_t dev_raw = 1024L*1024L*1024L; // 1 GiB offset into device memory
      int test_size = 1024*1024*512; // 512 MiB

      int bench_reg_offset = 26;

      std::cerr << "Performing latency measurement" << std::endl;

      uint32_t burst_len = 1;
      uint32_t bursts = 1;
      uint64_t addr_mask = get_addr_mask(malloc_sizes.at(benchmark_buffer), burst_len);
      device_bench(platform, bench_reg_offset, burst_len, bursts, dev_raw, addr_mask);
      device_bench(platform, bench_reg_offset, burst_len, bursts, maddr.at(benchmark_buffer), addr_mask);

      std::cerr << "Performing sequential reads with decrementing burst sizes." << std::endl;

      burst_len = 64;
      bursts = test_size/BUS_DATA_BYTES/burst_len;
      addr_mask = get_addr_mask(malloc_sizes.at(benchmark_buffer), burst_len);
      device_bench(platform, bench_reg_offset, burst_len, bursts, dev_raw, addr_mask);
      device_bench(platform, bench_reg_offset, burst_len, bursts, maddr.at(benchmark_buffer), addr_mask);

      burst_len = 32;
      bursts = test_size/BUS_DATA_BYTES/burst_len;
      addr_mask = get_addr_mask(malloc_sizes.at(benchmark_buffer), burst_len);
      device_bench(platform, bench_reg_offset, burst_len, bursts, dev_raw, addr_mask);
      device_bench(platform, bench_reg_offset, burst_len, bursts, maddr.at(benchmark_buffer), addr_mask);

      burst_len = 16;
      bursts = test_size/BUS_DATA_BYTES/burst_len;
      addr_mask = get_addr_mask(malloc_sizes.at(benchmark_buffer), burst_len);
      device_bench(platform, bench_reg_offset, burst_len, bursts, dev_raw, addr_mask);
      device_bench(platform, bench_reg_offset, burst_len, bursts, maddr.at(benchmark_buffer), addr_mask);

      burst_len = 8;
      bursts = test_size/BUS_DATA_BYTES/burst_len;
      addr_mask = get_addr_mask(malloc_sizes.at(benchmark_buffer), burst_len);
      device_bench(platform, bench_reg_offset, burst_len, bursts, dev_raw, addr_mask);
      device_bench(platform, bench_reg_offset, burst_len, bursts, maddr.at(benchmark_buffer), addr_mask);

      burst_len = 4;
      bursts = test_size/BUS_DATA_BYTES/burst_len;
      addr_mask = get_addr_mask(malloc_sizes.at(benchmark_buffer), burst_len);
      device_bench(platform, bench_reg_offset, burst_len, bursts, dev_raw, addr_mask);
      device_bench(platform, bench_reg_offset, burst_len, bursts, maddr.at(benchmark_buffer), addr_mask);

      burst_len = 2;
      bursts = test_size/BUS_DATA_BYTES/burst_len;
      addr_mask = get_addr_mask(malloc_sizes.at(benchmark_buffer), burst_len);
      device_bench(platform, bench_reg_offset, burst_len, bursts, dev_raw, addr_mask);
      device_bench(platform, bench_reg_offset, burst_len, bursts, maddr.at(benchmark_buffer), addr_mask);

      burst_len = 1;
      bursts = test_size/BUS_DATA_BYTES/burst_len;
      addr_mask = get_addr_mask(malloc_sizes.at(benchmark_buffer), burst_len);
      device_bench(platform, bench_reg_offset, burst_len, bursts, dev_raw, addr_mask);
      device_bench(platform, bench_reg_offset, burst_len, bursts, maddr.at(benchmark_buffer), addr_mask);

      std::cerr << "Performing random reads with decrementing burst sizes." << std::endl;
      bench_reg_offset = 26 + 12;

      burst_len = 64;
      bursts = test_size/BUS_DATA_BYTES/burst_len;
      addr_mask = get_addr_mask(malloc_sizes.at(benchmark_buffer), burst_len);
      device_bench(platform, bench_reg_offset, burst_len, bursts, dev_raw, addr_mask);
      device_bench(platform, bench_reg_offset, burst_len, bursts, maddr.at(benchmark_buffer), addr_mask);

      burst_len = 32;
      bursts = test_size/BUS_DATA_BYTES/burst_len;
      addr_mask = get_addr_mask(malloc_sizes.at(benchmark_buffer), burst_len);
      device_bench(platform, bench_reg_offset, burst_len, bursts, dev_raw, addr_mask);
      device_bench(platform, bench_reg_offset, burst_len, bursts, maddr.at(benchmark_buffer), addr_mask);

      burst_len = 16;
      bursts = test_size/BUS_DATA_BYTES/burst_len;
      addr_mask = get_addr_mask(malloc_sizes.at(benchmark_buffer), burst_len);
      device_bench(platform, bench_reg_offset, burst_len, bursts, dev_raw, addr_mask);
      device_bench(platform, bench_reg_offset, burst_len, bursts, maddr.at(benchmark_buffer), addr_mask);

      burst_len = 8;
      bursts = test_size/BUS_DATA_BYTES/burst_len;
      addr_mask = get_addr_mask(malloc_sizes.at(benchmark_buffer), burst_len);
      device_bench(platform, bench_reg_offset, burst_len, bursts, dev_raw, addr_mask);
      device_bench(platform, bench_reg_offset, burst_len, bursts, maddr.at(benchmark_buffer), addr_mask);

      burst_len = 4;
      bursts = test_size/BUS_DATA_BYTES/burst_len;
      addr_mask = get_addr_mask(malloc_sizes.at(benchmark_buffer), burst_len);
      device_bench(platform, bench_reg_offset, burst_len, bursts, dev_raw, addr_mask);
      device_bench(platform, bench_reg_offset, burst_len, bursts, maddr.at(benchmark_buffer), addr_mask);

      burst_len = 2;
      bursts = test_size/BUS_DATA_BYTES/burst_len;
      addr_mask = get_addr_mask(malloc_sizes.at(benchmark_buffer), burst_len);
      device_bench(platform, bench_reg_offset, burst_len, bursts, dev_raw, addr_mask);
      device_bench(platform, bench_reg_offset, burst_len, bursts, maddr.at(benchmark_buffer), addr_mask);

      burst_len = 1;
      bursts = test_size/BUS_DATA_BYTES/burst_len;
      addr_mask = get_addr_mask(malloc_sizes.at(benchmark_buffer), burst_len);
      device_bench(platform, bench_reg_offset, burst_len, bursts, dev_raw, addr_mask);
      device_bench(platform, bench_reg_offset, burst_len, bursts, maddr.at(benchmark_buffer), addr_mask);
    }
  }

  if (bench_HD || bench_device) {
    // Free device buffers
    std::cerr << "Freeing device buffers." << std::endl;
    for (int i = 0; i < n_mallocs; i++) {
      platform->DeviceFree(maddr.at(i));
    }
  }

  if (bench_alloc || bench_dealloc) {
    // Test allocation speed
    std::cerr << "Measuring allocation latency." << std::endl;
    da_t alloc_addr;
    uint32_t cycles;
    uint64_t alloc_size = 1024*1024;

    while(alloc_size <= alloc_max) {

      if (!platform->DeviceMalloc(&alloc_addr, alloc_size).ok()) {
        std::cerr << "ERROR while allocating " << alloc_size << " bytes." << std::endl << std::flush;
        status = EXIT_FAILURE;
        break;
      }
      platform->ReadMMIO(50, &cycles);
      if (bench_alloc) {
        std::cout << "Alloc of " << alloc_size << " bytes took " << cycles << " cycles." << std::endl << std::flush;
      }

      if (bench_dealloc) {
        if (!platform->DeviceFree(alloc_addr).ok()) {
          std::cerr << "ERROR while freeing " << alloc_size << " bytes." << std::endl << std::flush;
          uint32_t regval = 0;
          platform->ReadMMIO(26+12*2+1, &regval);
          std::cerr << "State: " << regval << std::endl;
          status = EXIT_FAILURE;
          break;
        }
        platform->ReadMMIO(50, &cycles);
        std::cout << "Free of " << alloc_size << " bytes took " << cycles << " cycles." << std::endl << std::flush;
      }

      if (alloc_size < 1024L*1024*128) { // 128 MiB
        alloc_size += 1024L*1024; // 1 MiB
      } else if (alloc_size < 1024L*1024*1024) { // 1 GiB
        alloc_size += 1024L*1024*128; // 128 MiB
      } else if (alloc_size < 1024L*1024*1024*128) { // 128 GiB
        alloc_size += 1024L*1024*1024; // 1 GiB
      } else if (alloc_size < 1024L*1024*1024*1024*8) { // 8 TiB
        alloc_size += 1024L*1024*1024*32; // 32 GiB
      } else {
        alloc_size += 1024L*1024*1024*1024; // 1 TiB
      }
    }
  }

  if (bench_realloc) {
    // Test reallocation speed
    std::cerr << "Measuring reallocation latency." << std::endl;
    da_t alloc_addr;
    uint32_t cycles;
    uint64_t alloc_size = 1024*1024/2;

    if (!platform->DeviceMalloc(&alloc_addr, alloc_size).ok()) {
      std::cerr << "ERROR while allocating " << alloc_size << " bytes." << std::endl << std::flush;
      status = EXIT_FAILURE;
    }
    platform->ReadMMIO(50, &cycles);
    std::cout << "-Alloc of " << alloc_size << " bytes took " << cycles << " cycles." << std::endl << std::flush;

    alloc_size = 1024*1024;
    while(alloc_size <= alloc_max) {

      {
        // Set source address
        platform->WriteMMIO(FLETCHER_REG_MM_HDR_ADDR_LO, alloc_addr);
        platform->WriteMMIO(FLETCHER_REG_MM_HDR_ADDR_HI, alloc_addr >> 32);

        // Set size
        platform->WriteMMIO(FLETCHER_REG_MM_HDR_SIZE_LO, alloc_size);
        platform->WriteMMIO(FLETCHER_REG_MM_HDR_SIZE_HI, alloc_size >> 32);

        // Reallocate
        platform->WriteMMIO(FLETCHER_REG_MM_HDR_CMD, FLETCHER_REG_MM_CMD_REALLOC);

        // Wait for completion
        uint32_t regval = 0;
        do {
          platform->ReadMMIO(FLETCHER_REG_MM_HDA_STATUS, &regval);
        } while ((regval & FLETCHER_REG_MM_STATUS_DONE) == 0);

        // Check status of returned allocation
        if ((regval & FLETCHER_REG_MM_STATUS_OK) == 0) {
          // Allocation failed
          alloc_addr = D_NULLPTR;

          // Acknowledge that response was read
          platform->WriteMMIO(FLETCHER_REG_MM_HDA_STATUS, FLETCHER_REG_MM_HDA_STATUS_ACK);

        } else {
          // Get address from device
          platform->ReadMMIO(FLETCHER_REG_MM_HDA_ADDR_HI, &regval);
          alloc_addr = regval;
          platform->ReadMMIO(FLETCHER_REG_MM_HDA_ADDR_LO, &regval);
          alloc_addr = (alloc_addr << 32) | regval;

          // Acknowledge that response was read
          platform->WriteMMIO(FLETCHER_REG_MM_HDA_STATUS, FLETCHER_REG_MM_HDA_STATUS_ACK);
        }
      }

      if (alloc_addr == D_NULLPTR) {
        std::cerr << "ERROR while reallocating to " << alloc_size << " bytes." << std::endl << std::flush;
        status = EXIT_FAILURE;
        break;
      }
      platform->ReadMMIO(50, &cycles);
      std::cout << "Realloc to " << alloc_size << " bytes took " << cycles << " cycles." << std::endl << std::flush;

      std::cerr << "Device malloc at " << std::setw(12) << std::hex << alloc_addr << std::dec << "." << std::endl << std::flush;

      if (alloc_size < 1024L*1024*128) { // 128 MiB
        alloc_size += 1024L*1024; // 1 MiB
      } else if (alloc_size < 1024L*1024*1024) { // 1 GiB
        alloc_size += 1024L*1024*128; // 128 MiB
      } else if (alloc_size < 1024L*1024*1024*128) { // 128 GiB
        alloc_size += 1024L*1024*1024; // 1 GiB
      } else if (alloc_size < 1024L*1024*1024*1024*8) { // 8 TiB
        alloc_size += 1024L*1024*1024*32; // 32 GiB
      } else {
        alloc_size += 1024L*1024*1024*1024; // 1 TiB
      }
    }

    if (!platform->DeviceFree(alloc_addr).ok()) {
      std::cerr << "ERROR while freeing " << alloc_size << " bytes." << std::endl;
      status = EXIT_FAILURE;
    }
    platform->ReadMMIO(50, &cycles);
    std::cout << "-Free of " << alloc_size << " bytes took " << cycles << " cycles." << std::endl << std::flush;
  }

  // Report the run times:
  PRINT_TIME(calc_sum(t_alloc), "allocation");
  PRINT_TIME(calc_sum(t_write), "H2D");
  PRINT_TIME(calc_sum(t_read), "D2H");

  if (status == EXIT_SUCCESS) {
    std::cout << "PASS" << std::endl;
  } else {
    std::cout << "ERROR" << std::endl;
  }
  return status;
}

