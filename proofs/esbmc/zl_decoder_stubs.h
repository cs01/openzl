/* Minimal decoder-framework stubs so harnesses can include unmodified decode bindings. */
#ifndef OPENZL_PROOFS_ESBMC_ZL_DECODER_STUBS_H
#define OPENZL_PROOFS_ESBMC_ZL_DECODER_STUBS_H

#include <stdlib.h>
#include <string.h>

#define __builtin_add_overflow(x, y, r) (*(r) = (x) + (y), *(r) < (x))
#define __builtin_mul_overflow(x, y, r) \
    (*(r) = (x) * (y), (x) != 0 && *(r) / (x) != (y))

#include "openzl/zl_data.h"
#include "openzl/zl_dtransform.h"
#include "openzl/zl_errors.h"

#define ZSTRONG_DICTX_H
unsigned DI_getFrameFormatVersion(const ZL_Decoder* dictx);

typedef struct {
    void* ptr;
    size_t numElts;
    size_t eltWidth;
    size_t capacity;
    ZL_Type type;
} StubStream;

static unsigned stub_formatVersion = 21;
static StubStream stub_out;
static ZL_RBuffer stub_codecHeader;

ZL_Type ZL_Data_type(const ZL_Data* data)
{
    return ((const StubStream*)(const void*)data)->type;
}
size_t ZL_Data_numElts(const ZL_Data* data)
{
    return ((const StubStream*)(const void*)data)->numElts;
}
size_t ZL_Data_eltWidth(const ZL_Data* data)
{
    return ((const StubStream*)(const void*)data)->eltWidth;
}
const void* ZL_Data_rPtr(const ZL_Data* data)
{
    return ((const StubStream*)(const void*)data)->ptr;
}
void* ZL_Data_wPtr(ZL_Data* data)
{
    return ((StubStream*)(void*)data)->ptr;
}
ZL_Report ZL_Data_commit(ZL_Data* data, size_t nbElts)
{
    StubStream* const s = (StubStream*)(void*)data;
    __ESBMC_assert(nbElts <= s->capacity, "commit within reserved capacity");
    s->numElts = nbElts;
    return ZL_returnSuccess();
}

ZL_Output* ZL_Decoder_create1OutStream(
        ZL_Decoder* dictx,
        size_t eltsCapacity,
        size_t eltWidth)
{
    (void)dictx;
    stub_out.ptr      = malloc(eltsCapacity * eltWidth);
    stub_out.capacity = eltsCapacity;
    stub_out.eltWidth = eltWidth;
    stub_out.numElts  = 0;
    stub_out.type     = ZL_Type_serial;
    return (ZL_Output*)(void*)&stub_out;
}

void* ZL_Decoder_getScratchSpace(ZL_Decoder* dictx, size_t size)
{
    (void)dictx;
    return malloc(size);
}

ZL_RBuffer ZL_Decoder_getCodecHeader(const ZL_Decoder* dictx)
{
    (void)dictx;
    return stub_codecHeader;
}

unsigned DI_getFrameFormatVersion(const ZL_Decoder* dictx)
{
    (void)dictx;
    return stub_formatVersion;
}

void ZL_zeroes(void* ptr, size_t size)
{
    memset(ptr, 0, size);
}

ZL_OperationContext* ZL_Decoder_getOperationContext(ZL_Decoder* dictx)
{
    (void)dictx;
    return NULL;
}

ZL_Error ZL_E_create(
        ZL_StaticErrorInfo const* st,
        ZL_ErrorContext const* ctx,
        const char* file,
        const char* func,
        int line,
        ZL_ErrorCode code,
        const char* fmt,
        ...)
{
    (void)st, (void)ctx, (void)file, (void)func, (void)line, (void)fmt;
    __ESBMC_assert(code != ZL_ErrorCode_no_error, "errors carry an error code");
    ZL_Error e;
    memset(&e, 0, sizeof(e));
    e._code = code;
    return e;
}

ZL_Error ZL_E_addFrame(
        ZL_ErrorContext const* ctx,
        ZL_Error error,
        ZL_ErrorInfo backup,
        const char* file,
        const char* func,
        int line,
        const char* fmt,
        ...)
{
    (void)ctx, (void)backup, (void)file, (void)func, (void)line, (void)fmt;
    return error;
}

void ZL_E_appendToMessage(ZL_Error err, char const* fmt, ...)
{
    (void)err, (void)fmt;
}

void ZL_LOG_func(const char* file, const char* func, int line, const char* fmt, ...)
{
    (void)file, (void)func, (void)line, (void)fmt;
}

void ZL_LOG_func_if_nonempty(
        const char* file,
        const char* func,
        int line,
        const char* prefix,
        const char* fmt,
        ...)
{
    (void)file, (void)func, (void)line, (void)prefix, (void)fmt;
}

#endif
