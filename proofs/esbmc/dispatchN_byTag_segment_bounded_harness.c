/* DI_dispatchN_byTag with each segment no longer than its source stream. */
#include <stdint.h>
#include <stdlib.h>

#include "zl_decoder_stubs.h"

#include "openzl/codecs/dispatchN_byTag/decode_dispatchN_byTag_binding.c"
#include "openzl/codecs/dispatchN_byTag/decode_dispatchN_byTag_kernel.c"
#include "openzl/codecs/range_pack/decode_range_pack_kernel.c"
#include "openzl/shared/numeric_operations.c"

#define MAX_SRC 4
#define MAX_SEGMENTS 2

uint8_t nondet_uchar(void);
uint64_t nondet_u64(void);
size_t nondet_size_t(void);

int main(void)
{
    size_t const srcLen = nondet_size_t();
    __ESBMC_assume(srcLen <= MAX_SRC);
    uint8_t* const srcBuf = malloc(srcLen);
    for (size_t i = 0; i < srcLen; i++) {
        srcBuf[i] = nondet_uchar();
    }
    StubStream variable = { srcBuf, srcLen, 1, srcLen, ZL_Type_serial };

    size_t const nbSegments = nondet_size_t();
    __ESBMC_assume(nbSegments >= 1 && nbSegments <= MAX_SEGMENTS);
    uint64_t* const sizes = malloc(nbSegments * sizeof(uint64_t));
    uint8_t* const tags   = malloc(nbSegments);
    for (size_t i = 0; i < nbSegments; i++) {
        sizes[i] = nondet_u64();
        tags[i]  = nondet_uchar();
        __ESBMC_assume(sizes[i] <= srcLen);
    }
    StubStream tagStream = { tags, nbSegments, 1, nbSegments, ZL_Type_numeric };
    StubStream sizeStream = {
        sizes, nbSegments, sizeof(uint64_t), nbSegments, ZL_Type_numeric
    };

    const ZL_Input* inFixed[2];
    inFixed[dnbt_tags]     = (const ZL_Input*)(const void*)&tagStream;
    inFixed[dnbt_segSizes] = (const ZL_Input*)(const void*)&sizeStream;
    const ZL_Input* inVariable[1] = { (const ZL_Input*)(const void*)&variable };

    ZL_Decoder* const dictx = (ZL_Decoder*)(void*)&variable;
    DI_dispatchN_byTag(dictx, inFixed, 2, inVariable, 1);
    return 0;
}
