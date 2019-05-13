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

using fletcher::Timer;

double calc_sum(const std::vector<double> &values) {
  return accumulate(values.begin(), values.end(), 0.0);
}

uint32_t calc_sum(const std::vector<uint32_t> &values) {
  return static_cast<uint32_t>(accumulate(values.begin(), values.end(), 0.0));
}

/**
 * Main function for the example.
 * Generates list of numbers, runs k-means on CPU and on FPGA.
 * Finally compares the results.
 */
int main(int argc, char ** argv) {
  int status = EXIT_SUCCESS;

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
//  malloc_sizes.push_back(1024L*1024*1024* 512);
//  malloc_sizes.push_back(1024L*1024*1024* 1024); //  1 TB
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
    std::cerr << "running device benchmarker...";
    int bench_reg_offset = 26;
    const int BUS_DATA_BYTES = 512/8;
    const double PERIOD = 0.000000004;
    uint32_t control = 0;
    uint32_t status;
    uint32_t burst_len = 64;
    uint32_t max_bursts = 10000;
    uint32_t base_addr_lo = (uint32_t) maddr.at(benchmark_buffer);
    uint32_t base_addr_hi = (uint32_t) (maddr.at(benchmark_buffer) >> 32);
    uint64_t addr_mask;
    for (int i=0; i<64; i++) {
      if ( (malloc_sizes.at(benchmark_buffer) >> i) == 0) {
        addr_mask = (~0) >> (64-i);
        break;
      }
    }
    for (int i=0; i<64; i++) {
      if ( (burst_len >> i) == 0) {
        addr_mask &= (~0) << (64-i+9); // 64-i+log2(BUS_DATA_BYTES)
        break;
      }
    }
    uint32_t addr_mask_lo = (uint32_t) addr_mask;
    uint32_t addr_mask_hi = (uint32_t) (addr_mask >> 32);
    uint32_t cycles_per_word = 0;
    uint32_t cycles;
    platform->writeMMIO(bench_reg_offset+2, burst_len);
    platform->writeMMIO(bench_reg_offset+3, max_bursts);
    platform->writeMMIO(bench_reg_offset+4, base_addr_lo);
    platform->writeMMIO(bench_reg_offset+5, base_addr_hi);
    platform->writeMMIO(bench_reg_offset+6, addr_mask_lo);
    platform->writeMMIO(bench_reg_offset+7, addr_mask_hi);
    platform->writeMMIO(bench_reg_offset+8, cycles_per_word);
    // Reset
    control = 4;
    platform->writeMMIO(bench_reg_offset+0, control);
    // Start
    control = 1;
    platform->writeMMIO(bench_reg_offset+0, control);
    // Deassert start
    control = 0;
    platform->writeMMIO(bench_reg_offset+0, control);
    // Wait until done
    do {
      usleep(2000);
      platform->readMMIO(bench_reg_offset+1, &status);
    } while (status == 2);
    if (status != 4) {
      std::cerr << "ERROR\n";
    } else {
      std::cerr << "finished\n";
      platform->readMMIO(bench_reg_offset+9, &cycles);
      uint64_t num_bytes =  BUS_DATA_BYTES * burst_len * max_bursts;
      int throughput = (num_bytes/(cycles*PERIOD))/1000/1000;
      std::cout << cycles << " cycles for " << max_bursts << " bursts of length "
          << burst_len << " (" << (num_bytes/1024) << " KiB)\n";
      std::cout << "D_R[0]: " << throughput << " MB/s\n";
    }

    std::cerr << "running device benchmarker...";
    bench_reg_offset = 26 + 12;
    // Reset
    control = 4;
    platform->writeMMIO(bench_reg_offset+0, control);
    // Start
    control = 1;
    platform->writeMMIO(bench_reg_offset+0, control);
    // Deassert start
    control = 0;
    platform->writeMMIO(bench_reg_offset+0, control);
    // Wait until done
    do {
      usleep(2000);
      platform->readMMIO(bench_reg_offset+1, &status);
    } while (status == 2);
    if (status != 4) {
      std::cerr << "ERROR\n";
    } else {
      std::cerr << "finished\n";
      platform->readMMIO(bench_reg_offset+9, &cycles);
      uint64_t num_bytes =  BUS_DATA_BYTES * burst_len * max_bursts;
      int throughput = (num_bytes/(cycles*PERIOD))/1000/1000;
      std::cout << cycles << " cycles for " << max_bursts << " bursts of length "
          << burst_len << " (" << (num_bytes/1024) << " KiB)\n";
      std::cout << "D_R[0]: " << throughput << " MB/s\n";
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

