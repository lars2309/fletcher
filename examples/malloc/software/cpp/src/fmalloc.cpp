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

  // Set size to 3 GB
  uint32_t rv = size;
  platform->writeMMIO(2, rv);
  rv = size >> 32;
  platform->writeMMIO(3, rv);

  // Allocate
  platform->writeMMIO(5, 3);

  // Wait for completion
  do {
//    usleep(1);
    platform()->readMMIO(8, &rv);
  } while ((rv & 1) != 1);

  uint64_t address;
  platform()->readMMIO64(6, &address);
  return address;
}

/**
 * Main function for the example.
 * Generates list of numbers, runs k-means on CPU and on FPGA.
 * Finally compares the results.
 */
int main(int argc, char ** argv) {
  int status = EXIT_SUCCESS;

  // Initialize FPGA
  std::shared_ptr<fletcher::Platform> platform;
  std::shared_ptr<fletcher::Context> context;

  fletcher::Platform::Make(&platform);
  fletcher::Context::Make(&context, platform);

  platform->init();

  Timer t;
  std::vector<double> t_alloc();

  t.start();
  fmalloc(platform, 300*1024*1024);
  t.stop();
  t_alloc[0] = t.seconds();

  // Report the run times:
  PRINT_TIME(calc_sum(t_alloc), "allocation");

  if (status == EXIT_SUCCESS) {
    std::cout << "PASS" << std::endl;
  } else {
    std::cout << "ERROR" << std::endl;
  }
  return status;
}

