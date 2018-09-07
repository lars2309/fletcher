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

#include <stdexcept>	

#include "RegExUserCore.h"

using namespace fletcher;

RegExUserCore::RegExUserCore(std::shared_ptr<fletcher::FPGAPlatform> platform)
    : UserCore(platform)
{
  // Some settings that are different from standard implementation
  // concerning start, reset and status register.
  // Generate a bit for every unit
  fletcher::fr_t unit_bits = pow(2, REUC_ACTIVE_UNITS)-1;
  // `start' bits are the LSBs on the control register
  ctrl_start = unit_bits;
  // `reset' bits follow `start' bits
  ctrl_reset = unit_bits << REUC_ACTIVE_UNITS;
  // `done' bits follow the `busy' bits
  done_status = unit_bits << REUC_ACTIVE_UNITS;
  // Take `done' bits and `busy' bits into consideration
  done_status_mask = (unit_bits << REUC_ACTIVE_UNITS) | unit_bits;
}

std::vector<fr_t> RegExUserCore::generate_unit_arguments(uint32_t first_index,
                                                         uint32_t last_index)
{
  /*
   * Generate arguments for the regular expression matching units.
   * First concatenate all `first' indices, followed by all `last' indices.
   */

  if (first_index >= last_index) {
    throw std::runtime_error("First index cannot be larger than "
                             "or equal to last index.");
  }

  // Every unit needs two 32 bit arguments
  std::vector<fr_t> arguments(REUC_TOTAL_UNITS * 2);

  // Obtain first and last indices
  uint32_t match_rows = last_index - first_index;
  for (int i = 0; i < REUC_ACTIVE_UNITS; i++) {
    // First and last index for unit i
    uint32_t first = first_index + i * match_rows / REUC_ACTIVE_UNITS;
    uint32_t last = first + match_rows / REUC_ACTIVE_UNITS;
    arguments[i] = first;
    arguments[i + REUC_TOTAL_UNITS] = last;
  }

  return arguments;
}

void RegExUserCore::set_arguments(uint32_t first_index, uint32_t last_index)
{
  std::vector<fr_t> arguments = this->generate_unit_arguments(first_index, last_index);
  UserCore::set_arguments(arguments);
}

void RegExUserCore::get_matches(std::vector<uint32_t>& matches)
{
  int np = matches.size();

  for (int p = 0; p < np; p++) {
    this->platform()->read_mmio(REUC_RESULT_OFFSET + p, &matches[p]);
  }
}
