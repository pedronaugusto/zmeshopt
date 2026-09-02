/*
 * zmeshopt — C-level smoke test.
 *
 * Proves the installed header and static library stand on their own as a C
 * contract, independent of anything Zig-side: includes <meshoptimizer.h> the
 * way a C consumer would, drives a small mesh through the core entry points,
 * and checks values, not just linkage.
 */
#include <assert.h>
#include <stdio.h>
#include <string.h>

#include "meshoptimizer.h"

int main(void) {
    /* Two triangles sharing an edge, with one duplicate vertex (index 3
     * duplicates index 1), so the remap has something to merge. */
    float vertices[] = {
        0.0f, 0.0f, 0.0f,
        1.0f, 0.0f, 0.0f,
        0.0f, 1.0f, 0.0f,
        1.0f, 0.0f, 0.0f, /* duplicate of vertex 1 */
        1.0f, 1.0f, 0.0f,
    };
    unsigned int indices[6] = {0, 1, 2, 3, 4, 2};

    unsigned int remap[5];
    size_t unique = meshopt_generateVertexRemap(remap, indices, 6, vertices, 5, 12);
    assert(unique == 4);

    float remapped_vertices[12];
    unsigned int remapped_indices[6];
    meshopt_remapVertexBuffer(remapped_vertices, vertices, 5, 12, remap);
    meshopt_remapIndexBuffer(remapped_indices, indices, 6, remap);
    assert(remapped_indices[3] == remapped_indices[1]);

    unsigned int optimized[6];
    meshopt_optimizeVertexCache(optimized, remapped_indices, 6, unique);

    struct meshopt_VertexCacheStatistics stats =
        meshopt_analyzeVertexCache(optimized, 6, unique, 16, 0, 0);
    assert(stats.vertices_transformed == 4);

    /* Index codec round trip. */
    unsigned char buffer[256];
    size_t bound = meshopt_encodeIndexBufferBound(6, unique);
    assert(bound <= sizeof(buffer));
    size_t encoded = meshopt_encodeIndexBuffer(buffer, sizeof(buffer), optimized, 6);
    assert(encoded > 0);
    unsigned int decoded[6];
    int rc = meshopt_decodeIndexBuffer(decoded, 6, sizeof(unsigned int), buffer, encoded);
    assert(rc == 0);
    /* The codec preserves each triangle up to corner rotation
     * (indexcodec.cpp:245), so compare rotation-normalized. */
    for (int t = 0; t < 2; ++t) {
        const unsigned int* want = optimized + t * 3;
        const unsigned int* got = decoded + t * 3;
        int rotated = 0;
        for (int r = 0; r < 3; ++r) {
            rotated |= want[0] == got[r] && want[1] == got[(r + 1) % 3] &&
                want[2] == got[(r + 2) % 3];
        }
        assert(rotated);
    }

    /* Quantization: fp16 round trip of an exactly-representable value. */
    unsigned short half = meshopt_quantizeHalf(0.5f);
    assert(meshopt_dequantizeHalf(half) == 0.5f);

    printf("zmeshopt c smoke: ok (unique=%u acmr=%f encoded=%u)\n",
        (unsigned)unique, stats.acmr, (unsigned)encoded);
    return 0;
}
