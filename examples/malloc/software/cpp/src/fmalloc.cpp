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
#include "fletcher/api.h"


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
    uint64_t base_addr, uint64_t addr_mask) {
  std::cerr << "running device benchmarker...";
  uint32_t control = 0;
  uint32_t status;
  uint32_t base_addr_lo = (uint32_t) base_addr;
  uint32_t base_addr_hi = (uint32_t) (base_addr >> 32);
  uint32_t addr_mask_lo = (uint32_t) addr_mask;
  uint32_t addr_mask_hi = (uint32_t) (addr_mask >> 32);
  uint32_t cycles_per_word = 0;
  uint32_t cycles;
  platform->writeMMIO(reg_offset+2, burst_len);
  platform->writeMMIO(reg_offset+3, bursts);
  platform->writeMMIO(reg_offset+4, base_addr_lo);
  platform->writeMMIO(reg_offset+5, base_addr_hi);
  platform->writeMMIO(reg_offset+6, addr_mask_lo);
  platform->writeMMIO(reg_offset+7, addr_mask_hi);
  platform->writeMMIO(reg_offset+8, cycles_per_word);
  // Reset
  control = 4;
  platform->writeMMIO(reg_offset+0, control);
  // Start
  control = 1;
  platform->writeMMIO(reg_offset+0, control);
  // Deassert start
  control = 0;
  platform->writeMMIO(reg_offset+0, control);
  // Wait until done
  do {
    usleep(2000);
    platform->readMMIO(reg_offset+1, &status);
  } while (status == 2);
  if (status != 4) {
    std::cerr << "ERROR\n";
    std::cerr << std::flush;
  } else {
    std::cerr << "finished\n";
    std::cerr << std::flush;
    platform->readMMIO(reg_offset+9, &cycles);
    uint64_t num_bytes =  BUS_DATA_BYTES * burst_len * bursts;
    int throughput = (num_bytes/(cycles*PERIOD))/1000/1000;
    std::cout << cycles << " cycles for " << bursts << " bursts of length "
        << burst_len << " (" << (num_bytes/1024) << " KiB)\n";
    std::cout << "D_R: " << throughput << " MB/s\n";
  }
}

/**
 * Main function for the example.
 * Generates list of numbers, runs k-means on CPU and on FPGA.
 * Finally compares the results.
 */
int main(int argc, char ** argv) {
  int status = EXIT_SUCCESS;

  // Maximum for page size 2^18 and 2^13 page table entries. (16TiB)
  const int64_t alloc_max = 1024L*1024*1024* 16384;

  std::vector<uint64_t> malloc_sizes;
  malloc_sizes.push_back(1024L*1024 *1);         //  1 MB, sub-page
  malloc_sizes.push_back(1024L*1024 *4);         //  4 MB, page
  malloc_sizes.push_back(1024L*1024 *64);        // 64 MB
  malloc_sizes.push_back(1024L*1024*1024);       //  1 GB
  malloc_sizes.push_back(1024L*1024*1024);       //  1 GB
  malloc_sizes.push_back(1024L*1024*1024);       //  1 GB
  malloc_sizes.push_back(1024L*1024*1024);       //  1 GB
  malloc_sizes.push_back(1024L*1024*1024* 32-1); // 32 GB, full L2 page table, one less
  malloc_sizes.push_back(1024L*1024*1024* 32);   // 32 GB, full L2 page table, exact
  malloc_sizes.push_back(1024L*1024*1024* 32+1); // 32 GB, full L2 page table, one more
  malloc_sizes.push_back(1024L*1024*1024* 64);
  malloc_sizes.push_back(1024L*1024*1024* 128);
  malloc_sizes.push_back(1024L*1024*1024* 256);
  malloc_sizes.push_back(1024L*1024*1024* 512);
  malloc_sizes.push_back(1024L*1024*1024* 1024); //  1 TB

  int n_mallocs = malloc_sizes.size();

  int benchmark_buffer = 4;

  // Initialize FPGA
  std::shared_ptr<fletcher::Platform> platform;
  std::shared_ptr<fletcher::Context> context;

  fletcher::Platform::Make(&platform);
  fletcher::Context::Make(&context, platform);

  platform->init();

  Timer t;
  std::vector<double> t_alloc(n_mallocs);
  std::vector<double> t_write(n_mallocs);
  std::vector<double> t_read(n_mallocs);
  std::vector<uint64_t> maddr(n_mallocs);

  // Allocate memory on device
  for (int i = 0; i < n_mallocs; i++) {
    t.start();
    platform->deviceMalloc(&maddr[i], malloc_sizes[i]);
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
  const int max_data_size = 1024L*1024*1024; // Max 1GB for data copies.
  std::ifstream file("/dev/urandom");
  std::vector<uint8_t*> source_buffers;
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
        platform->copyHostToDevice(source_buffers.back(), maddr[i], malloc_sizes[i]);
        t.stop();
        t_write[i] = t.seconds();
        std::cerr << "done" << std::endl;
        int throughput = malloc_sizes[i] / t.seconds() / 1000/1000;
        std::cout << "H2D[" << i << "]: " << throughput << " MB/s";
        std::cout << " (" << malloc_sizes[i] << " B)" << std::endl;
      }
    } else {
      source_buffers.push_back((unsigned char*) nullptr);
      t_write[i] = 0;
    }
  }

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
        platform->copyDeviceToHost(maddr[i], check_buffers.back(), malloc_sizes[i]);
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

  // Use hardware benchmarker
  if (benchmark_buffer >= 0) {

    uint64_t dev_raw = 1024L*1024L*1024L; // 1 GiB offset into device memory
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

  // Free device buffers
  std::cerr << "Freeing device buffers." << std::endl;
  for (int i = 0; i < n_mallocs; i++) {
    platform->deviceFree(maddr.at(i));
  }

  // Test allocation speed
  std::cerr << "Measuring allocation latency." << std::endl;
  int64_t alloc_addr;
  int32_t cycles;
  int64_t alloc_size = 1024*1024;
  while(alloc_size <= alloc_max) {
    platform->deviceMalloc(alloc_addr, alloc_size);
    platform->readMMIO(50, &cycles);
    std::cout << "Alloc of " << alloc_size << " bytes took " << cycles << " cycles." << std::endl;
    platform->deviceFree(alloc_addr);
    if (alloc_size < 1024*1024*128) { // 128 MiB
      alloc_size += 1024*1024; // 1 MiB
    } else if (alloc_size < 1024L*1024L*1024L) { // 1 GiB
      alloc_size += 1024*1024*128; // 128 MiB
    } else if (alloc_size < 1024L*1024L*1024L*128L) { // 128 GiB
      alloc_size += 1024*1024*128; // 1 GiB
    } else {
      alloc_size *= 2;
    }
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

