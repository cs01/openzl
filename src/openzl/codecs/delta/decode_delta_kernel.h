// Copyright (c) Meta Platforms, Inc. and affiliates.

#ifndef ZSTRONG_TRANSFORMS_DELTA_DECODE_DELTA_KERNEL_H
#define ZSTRONG_TRANSFORMS_DELTA_DECODE_DELTA_KERNEL_H

#include <limits.h> // SIZE_MAX
#include <stddef.h> // size_t
#include <stdint.h> // uintX_t

#include "openzl/shared/c_contracts.h"

#if defined(__cplusplus)
extern "C" {
#endif

/**
 * Delta decodes the @p first element and the @p deltas and stores the
 * regenerated values in @p dst.
 *
 * @param dst The destination array with capacity for @p nbElts elements.
 * @param first The first value to be decoded, not used when @p nbElts == 0.
 * @param deltas The @p nbElts - 1 deltas to apply to @p first to regenerate
 * the original values.
 * @param nbElts The number of elements to regenerate. There will
 * be @p nbElts - 1 @p deltas, because the first value is stored in @p first.
 *
 * NOTE: Presuming all assumptions above are correctly verified,
 * these functions are always successful.
 */
// clang-format off
void ZS_deltaDecode8(
        uint8_t* dst,
        uint8_t first,
        uint8_t const* deltas,
        size_t nelts)
        contract_pre(nelts <= SIZE_MAX / sizeof(*dst))
        contract_writes_n(dst, nelts)
        contract_pre(nelts == 0
                     || contract_readable(deltas, (nelts - 1) * sizeof(*deltas)))
        contract_pre(contract_disjoint(dst, deltas));
void ZS_deltaDecode16(
        uint16_t* dst,
        uint16_t first,
        uint16_t const* deltas,
        size_t nelts)
        contract_pre(nelts <= SIZE_MAX / sizeof(*dst))
        contract_writes_n(dst, nelts)
        contract_pre(nelts == 0
                     || contract_readable(deltas, (nelts - 1) * sizeof(*deltas)))
        contract_pre(contract_disjoint(dst, deltas));
void ZS_deltaDecode32(
        uint32_t* dst,
        uint32_t first,
        uint32_t const* deltas,
        size_t nelts)
        contract_pre(nelts <= SIZE_MAX / sizeof(*dst))
        contract_writes_n(dst, nelts)
        contract_pre(nelts == 0
                     || contract_readable(deltas, (nelts - 1) * sizeof(*deltas)))
        contract_pre(contract_disjoint(dst, deltas));
void ZS_deltaDecode64(
        uint64_t* dst,
        uint64_t first,
        uint64_t const* deltas,
        size_t nelts)
        contract_pre(nelts <= SIZE_MAX / sizeof(*dst))
        contract_writes_n(dst, nelts)
        contract_pre(nelts == 0
                     || contract_readable(deltas, (nelts - 1) * sizeof(*deltas)))
        contract_pre(contract_disjoint(dst, deltas));
void ZS_deltaDecode(
        void* dst,
        void const* first,
        void const* deltas,
        size_t nelts,
        size_t eltWidth)
        contract_pre(eltWidth == 1 || eltWidth == 2 || eltWidth == 4 || eltWidth == 8)
        contract_pre(nelts <= SIZE_MAX / eltWidth)
        contract_writes(dst, nelts * eltWidth)
        contract_pre(nelts == 0 || contract_readable(first, eltWidth))
        contract_pre(nelts == 0
                     || contract_readable(deltas, (nelts - 1) * eltWidth))
        contract_pre(contract_disjoint(dst, deltas));
// clang-format on

#if defined(__cplusplus)
} // extern "C"
#endif

#endif // ZSTRONG_TRANSFORMS_DELTA_DECODE_DELTA_KERNEL_H
