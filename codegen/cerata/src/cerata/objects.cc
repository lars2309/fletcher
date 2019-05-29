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

#include "cerata/objects.h"

#include <string>
#include <memory>

#include "cerata/nodes.h"
#include "cerata/arrays.h"
#include "cerata/utils.h"

namespace cerata {

void Object::SetParent(const Graph *parent) {
  if (parent != nullptr) { parent_ = parent; }
  else { throw std::runtime_error("Parent cannot be nullptr."); }
}

std::optional<const Graph *> Object::parent() const { return parent_; }

}  // cerata;