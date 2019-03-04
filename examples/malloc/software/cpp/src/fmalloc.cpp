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

  int n_mallocs = 10;
  uint64_t malloc_sizes[] = {
      1024L*1024*300,
      1024L*1024*1024*32,
      1024L*1024*1024*32+1,
      1024L*1024*1024*32-1,
      1024L*1024*1024*64,
      1024L*1024*1024*128,
      1024L*1024*1024*256,
      1024L*1024*1024*512,
      1024L*1024*1024*1024,
      1024L*1024*1024*2048};

  // Initialize FPGA
  std::shared_ptr<fletcher::Platform> platform;
  std::shared_ptr<fletcher::Context> context;

  fletcher::Platform::Make(&platform);
  fletcher::Context::Make(&context, platform);

  platform->init();

  Timer t;
  std::vector<double> t_alloc(n_mallocs);
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
  }

  // Report the run times:
  PRINT_TIME(calc_sum(t_alloc), "allocation");

  if (status == EXIT_SUCCESS) {
    std::cout << "PASS" << std::endl;
  } else {
    std::cout << "ERROR" << std::endl;
  }
  return status;
}

