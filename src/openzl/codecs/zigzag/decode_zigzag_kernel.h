// Copyright (c) Meta Platforms, Inc. and affiliates.

/**
 * \file
 *
 * This file defines the internal implementation for a zigzag
 * transformation.
 */

#ifndef ZSTRONG_TRANSFORMS_ZIGZAG_DECODE_ZIGZAG_KERNEL_H
#define ZSTRONG_TRANSFORMS_ZIGZAG_DECODE_ZIGZAG_KERNEL_H

#include <limits.h> // SIZE_MAX
#include <stddef.h> // size_t
#include <stdint.h> // xintXX_t

#include "openzl/shared/c_contracts.h"

#if defined(__cplusplus)
extern "C" {
#endif

/* raw transforms (transportable).
 * Required conditions :
 * dst & src must be valid (already allocated, aligned and sized accordingly)
 * if (nbElts>0), dst and src must be non-NULL
 **/
// clang-format off
void ZL_zigzagDecode8(int8_t* dst, const uint8_t* src, size_t nbElts)
        contract_pre(nbElts <= SIZE_MAX / sizeof(*src))
        contract_reads_n(src, nbElts)
        contract_writes_n(dst, nbElts)
        contract_pre(contract_disjoint(dst, src));
void ZL_zigzagDecode16(int16_t* dst, const uint16_t* src, size_t nbElts)
        contract_pre(nbElts <= SIZE_MAX / sizeof(*src))
        contract_reads_n(src, nbElts)
        contract_writes_n(dst, nbElts)
        contract_pre(contract_disjoint(dst, src));
void ZL_zigzagDecode32(int32_t* dst, const uint32_t* src, size_t nbElts)
        contract_pre(nbElts <= SIZE_MAX / sizeof(*src))
        contract_reads_n(src, nbElts)
        contract_writes_n(dst, nbElts)
        contract_pre(contract_disjoint(dst, src));
void ZL_zigzagDecode64(int64_t* dst, const uint64_t* src, size_t nbElts)
        contract_pre(nbElts <= SIZE_MAX / sizeof(*src))
        contract_reads_n(src, nbElts)
        contract_writes_n(dst, nbElts)
        contract_pre(contract_disjoint(dst, src));
void ZL_zigzagDecode(void* dst, const void* src, size_t nbElts, size_t eltWidth)
        contract_pre(eltWidth == 1 || eltWidth == 2 || eltWidth == 4 || eltWidth == 8)
        contract_pre(nbElts <= SIZE_MAX / eltWidth)
        contract_reads(src, nbElts * eltWidth)
        contract_writes(dst, nbElts * eltWidth)
        contract_pre(contract_disjoint(dst, src));
// clang-format on

#if defined(__cplusplus)
} // extern "C"
#endif

#endif
