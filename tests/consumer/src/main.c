/*
 * A downstream C consumer: proves the artifact links and the header installs
 * under its published name, through b.dependency + linkLibrary alone.
 */
#include <stdio.h>

#include <meshoptimizer.h>

int main(void) {
    unsigned int indices[6] = {0, 1, 2, 2, 1, 3};
    unsigned int optimized[6];
    meshopt_optimizeVertexCache(optimized, indices, 6, 4);

    struct meshopt_VertexCacheStatistics stats =
        meshopt_analyzeVertexCache(optimized, 6, 4, 16, 0, 0);
    if (stats.vertices_transformed != 4) {
        fprintf(stderr, "c consumer: expected 4 transformed vertices, got %u\n",
            stats.vertices_transformed);
        return 1;
    }

    unsigned short half = meshopt_quantizeHalf(0.25f);
    if (meshopt_dequantizeHalf(half) != 0.25f) {
        fprintf(stderr, "c consumer: fp16 round trip failed\n");
        return 1;
    }

    printf("c consumer ok: acmr %f\n", stats.acmr);
    return 0;
}
