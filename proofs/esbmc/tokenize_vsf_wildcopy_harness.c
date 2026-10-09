/* DI_tokenizeVSF: every copy stays inside its source and destination. */
#include <stdint.h>
#include <stdlib.h>
#include <string.h>

#include "bounds_memcpy_model.h"

#include "openzl/codecs/tokenize/decode_tokenize_kernel.c"

#define MAX_ALPHABET 3
#define MAX_ELTS 4
#define MAX_TOKEN 40

uint8_t nondet_uchar(void);
uint32_t nondet_uint(void);
size_t nondet_size_t(void);

int main(void)
{
    size_t const alphabetSize = nondet_size_t();
    __ESBMC_assume(alphabetSize >= 1 && alphabetSize <= MAX_ALPHABET);

    uint32_t fieldSizes[MAX_ALPHABET];
    size_t fieldSizesSum = 0;
    for (size_t i = 0; i < alphabetSize; i++) {
        fieldSizes[i] = nondet_uint();
        __ESBMC_assume(fieldSizes[i] <= MAX_TOKEN);
        fieldSizesSum += fieldSizes[i];
    }

    size_t const dstNbElts = nondet_size_t();
    __ESBMC_assume(dstNbElts <= MAX_ELTS);
    uint8_t* const indices = malloc(dstNbElts);
    for (size_t i = 0; i < dstNbElts; i++) {
        indices[i] = nondet_uchar();
    }
    uint8_t* const alphabet = malloc(fieldSizesSum);

    if (!ZS_tokenizeValidateIndices(alphabetSize, indices, dstNbElts, 1)) {
        return 0;
    }
    size_t const dstNbBytes = ZS_tokenizeComputeVSFContentSize(
            indices, 1, dstNbElts, fieldSizes, alphabetSize);
    if (dstNbElts < alphabetSize) {
        return 0;
    }

    uint8_t* const out          = malloc(dstNbBytes);
    uint32_t* const dstFieldLen = malloc(dstNbElts * sizeof(uint32_t));
    void* const workspace       = malloc(
            ZS_tokenizeVSFDecodeWorkspaceSize(alphabetSize, fieldSizesSum));

    ZS_tokenizeVSFDecode(
            alphabet,
            alphabetSize,
            indices,
            fieldSizes,
            fieldSizesSum,
            out,
            dstFieldLen,
            dstNbElts,
            dstNbBytes,
            1,
            workspace);

    for (size_t i = 0; i < dstNbElts; i++) {
        __ESBMC_assert(
                dstFieldLen[i] == fieldSizes[indices[i]],
                "token length preserved");
    }
    return 0;
}
