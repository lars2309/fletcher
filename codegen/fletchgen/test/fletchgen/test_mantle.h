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

#pragma once

#include <gtest/gtest.h>
#include <deque>
#include <memory>
#include <vector>
#include <arrow/api.h>
#include <cerata/api.h>

#include "fletchgen/mantle.h"
#include "fletchgen/test_utils.h"

namespace fletchgen {

static void TestReadMantle(const std::shared_ptr<arrow::Schema>& schema) {
  cerata::default_component_pool()->Clear();
  auto set = SchemaSet::Make("test");
  set->AppendSchema(schema);
  auto mantle = Mantle::Make(set);
  auto design = cerata::vhdl::Design(mantle);
  auto code = design.Generate().ToString();
  std::cerr.flush();
  std::cout << code << std::endl;
  VHDL_DUMP_TEST(code);
}

TEST(Mantle, StringRead) {
  TestReadMantle(fletcher::GetStringReadSchema());
}


}
