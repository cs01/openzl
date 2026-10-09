/* Bounds-only memcpy: checks both ranges are in bounds, copies nothing. */
#ifndef OPENZL_PROOFS_ESBMC_BOUNDS_MEMCPY_MODEL_H
#define OPENZL_PROOFS_ESBMC_BOUNDS_MEMCPY_MODEL_H

#include <stddef.h>
#include <string.h>

static void* bounds_memcpy(void* dst, const void* src, size_t n)
{
    if (n != 0) {
        __ESBMC_assert(
                __ESBMC_POINTER_OFFSET(dst) >= 0
                        && (size_t)__ESBMC_POINTER_OFFSET(dst) + n
                                <= __ESBMC_get_object_size(dst),
                "memcpy destination in bounds");
        __ESBMC_assert(
                __ESBMC_POINTER_OFFSET(src) >= 0
                        && (size_t)__ESBMC_POINTER_OFFSET(src) + n
                                <= __ESBMC_get_object_size(src),
                "memcpy source in bounds");
    }
    return dst;
}

#define memcpy bounds_memcpy

#endif
