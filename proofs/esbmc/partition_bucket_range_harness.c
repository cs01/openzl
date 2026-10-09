/* DI_partition: every accepted bucket is below the declared partition count. */
#include <stdint.h>
#include <stdlib.h>

#include "zl_decoder_stubs.h"

#include "openzl/codecs/partition/common_partition.c"
#include "openzl/codecs/partition/decode_partition_binding.c"
#include "openzl/codecs/partition/decode_partition_kernel.c"

#define HEADER_SIZE 3
#define MAX_VALUES 2
#define OFFSET_BYTES 2

uint8_t nondet_uchar(void);
size_t nondet_size_t(void);

int main(void)
{
    uint8_t* const header = malloc(HEADER_SIZE);
    header[0] = ZL_PARTITION_HEADER_IS_FIRST_VALUE_ZERO_BIT;
    header[1] = 1;
    header[2] = 1;
    stub_codecHeader.start = header;
    stub_codecHeader.size  = HEADER_SIZE;

    size_t const nbValues = nondet_size_t();
    __ESBMC_assume(nbValues >= 1 && nbValues <= MAX_VALUES);
    uint8_t* const buckets = malloc(nbValues);
    for (size_t i = 0; i < nbValues; i++) {
        buckets[i] = nondet_uchar();
    }
    uint8_t* const offsets = malloc(OFFSET_BYTES);
    for (size_t i = 0; i < OFFSET_BYTES; i++) {
        offsets[i] = nondet_uchar();
    }

    StubStream bucketStream = { buckets, nbValues, 1, nbValues, ZL_Type_numeric };
    StubStream offsetStream = {
        offsets, OFFSET_BYTES, 1, OFFSET_BYTES, ZL_Type_serial
    };
    const ZL_Input* ins[2] = { (const ZL_Input*)(const void*)&bucketStream,
                               (const ZL_Input*)(const void*)&offsetStream };

    ZL_Report const r =
            DI_partition((ZL_Decoder*)(void*)&bucketStream, ins);
    if (ZL_isError(r)) {
        return 0;
    }

    ZL_PartitionParams params = { 0 };
    size_t eltWidth           = 0;
    uint64_t sizes[ZL_PARTITION_MAX_PARTITIONS];
    ZL_Report const p = ZL_PartitionParams_parseHeader(
            &params, &eltWidth, header, HEADER_SIZE, sizes);
    __ESBMC_assert(!ZL_isError(p), "binding accepted this header");

    for (size_t i = 0; i < nbValues; i++) {
        __ESBMC_assert(
                buckets[i] < params.numPartitions,
                "accepted bucket names a declared partition");
    }
    return 0;
}
