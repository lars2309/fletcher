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

/**
 * This file contains the Fletcher run-time global C header.
 */

#include <stdint.h>

#define FLETCHER_AUTODETECT_PLATFORMS "snap", "aws", "echo"

#define FLETCHER_STATUS_OK 0
#define FLETCHER_STATUS_ERROR 1
#define FLETCHER_STATUS_NO_PLATFORM 2
#define FLETCHER_STATUS_DEVICE_OUT_OF_MEMORY 3

/// Status for function return values
typedef uint64_t fstatus_t;

/// Device Address type
typedef uint64_t da_t;

/// Register type
typedef uint32_t freg_t;

/// Convenience union to convert addresses to a high and low part
typedef union {
  struct {
    uint32_t lo;
    uint32_t hi;
  };
  da_t full;
} dau_t;

/// Device nullptr
#define D_NULLPTR (da_t) 0x0

/// Hardware default registers
#define FLETCHER_REG_CONTROL        0
#define FLETCHER_REG_STATUS         1
#define FLETCHER_REG_RETURN0        2
#define FLETCHER_REG_RETURN1        3

/// Offset for schema derived registers
#define FLETCHER_REG_SCHEMA         4

#define FLETCHER_REG_CONTROL_START  0x0u
#define FLETCHER_REG_CONTROL_STOP   0x1u
#define FLETCHER_REG_CONTROL_RESET  0x2u

#define FLETCHER_REG_STATUS_IDLE    0x0u
#define FLETCHER_REG_STATUS_BUSY    0x1u
#define FLETCHER_REG_STATUS_DONE    0x2u

// Memory management interface (H2D, request and answer)
#define FLETCHER_REG_MM_HDR_ADDR_LO  6
#define FLETCHER_REG_MM_HDR_ADDR_HI  7
#define FLETCHER_REG_MM_HDR_SIZE_LO  8
#define FLETCHER_REG_MM_HDR_SIZE_HI  9
#define FLETCHER_REG_MM_HDR_REGION  10
#define FLETCHER_REG_MM_HDR_CMD     11
#define FLETCHER_REG_MM_HDA_ADDR_LO 12
#define FLETCHER_REG_MM_HDA_ADDR_HI 13
#define FLETCHER_REG_MM_HDA_STATUS  14

// Memory management interface (D2H, request and answer)
#define FLETCHER_REG_MM_DHR_ADDR_LO 16
#define FLETCHER_REG_MM_DHR_ADDR_HI 17
#define FLETCHER_REG_MM_DHR_SIZE_LO 18
#define FLETCHER_REG_MM_DHR_SIZE_HI 19
#define FLETCHER_REG_MM_DHR_REGION  20
#define FLETCHER_REG_MM_DHR_CMD     21
#define FLETCHER_REG_MM_DHA_ADDR_LO 22
#define FLETCHER_REG_MM_DHA_ADDR_HI 23
#define FLETCHER_REG_MM_DHA_STATUS  24

#define FLETCHER_REG_BUFFER_OFFSET  26


#define FLETCHER_REG_CONTROL_START  0x0
#define FLETCHER_REG_CONTROL_STOP   0x1
#define FLETCHER_REG_CONTROL_RESET  0x2

#define FLETCHER_REG_STATUS_IDLE    0x0
#define FLETCHER_REG_STATUS_BUSY    0x1
#define FLETCHER_REG_STATUS_DONE    0x2

#define FLETCHER_REG_MM_DEFAULT_REGION 1

#define FLETCHER_REG_MM_CMD_ALLOC   (1|(1<<1))
#define FLETCHER_REG_MM_CMD_FREE    (1|(1<<2))
#define FLETCHER_REG_MM_CMD_REALLOC (1|(1<<3))
#define FLETCHER_REG_MM_STATUS_DONE (1<<0)
#define FLETCHER_REG_MM_STATUS_OK   (1<<1)
#define FLETCHER_REG_MM_HDA_STATUS_ACK 0

