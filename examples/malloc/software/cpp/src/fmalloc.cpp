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

// Apache Arrow
#include <arrow/api.h>

// Fletcher
#include <fletcher/fletcher.h>
#include <fletcher/platform.h>
#include <fletcher/context.h>
#include <fletcher/usercore.h>
#include <fletcher/common/timer.h>


#define PRINT_TIME(X, S) std::cout << std::setprecision(10) << (X) << " " << (S) << std::endl << std::flush
#define PRINT_INT(X, S) std::cout << std::dec << (X) << " " << (S) << std::endl << std::flush

using fletcher::Timer;


uint64_t fmalloc(std::shared_ptr<fletcher::Platform> platform, uint64_t size) {
  // Set region to 1
  platform->writeMMIO(4, 1);

  // Set size
  uint32_t rv = size;
  platform->writeMMIO(2, rv);
  rv = size >> 32;
  platform->writeMMIO(3, rv);

  // Allocate
  platform->writeMMIO(5, 3);

  // Wait for completion
  do {
//    usleep(1);
    platform->readMMIO(8, &rv);
  } while ((rv & 1) != 1);

  uint64_t address;
  platform->readMMIO64(6, &address);
  rv = 0;
  platform->writeMMIO(8, rv);
  return address;
}

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
  malloc_sizes.push_back(1024L*1024*1024* 32-1); // 32 GB, full L2 page table, one less
  malloc_sizes.push_back(1024L*1024*1024* 32);   // 32 GB, full L2 page table, exact
  malloc_sizes.push_back(1024L*1024*1024* 32+1); // 32 GB, full L2 page table, one more
//  malloc_sizes.push_back(1024L*1024*1024* 64);
//  malloc_sizes.push_back(1024L*1024*1024* 128);
//  malloc_sizes.push_back(1024L*1024*1024* 256);
//  malloc_sizes.push_back(1024L*1024*1024* 512);
//  malloc_sizes.push_back(1024L*1024*1024* 1024); //  1 TB
  int n_mallocs = malloc_sizes.size();

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

  for (int i = 0; i < n_mallocs; i++) {
    t.start();
    maddr[i] = fmalloc(platform, malloc_sizes[i]);
    t.stop();
    t_alloc[i] = t.seconds();
  }
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
      source_buffers.push_back((unsigned char *) malloc(malloc_sizes[i]));
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
      check_buffers.push_back((unsigned char *) malloc(malloc_sizes[i]));
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
        if (!memcmp(check_buffers.back(), source_buffers.at(i), malloc_sizes[i])) {
          std::cerr << "ERROR: Data does not match for buffer " << i << "." << std::endl;
        }
      }
    } else {
      t_read[i] = 0;
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

