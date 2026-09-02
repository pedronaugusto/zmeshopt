/*
 * zmeshopt — caller-codegen canaries. TEST-ONLY: compiled into the Zig test
 * executable, never into the shipped library.
 *
 * Two sets of echo mirrors, asserted by src/abi_canary_test.zig:
 * the zmeshopt_canary_* set mirrors the RAW upstream shapes Zig 0.16.0's
 * self-hosted backends were measured miscompiling in the caller (a float
 * after more than 6 integer-class arguments; an all-float 16-byte struct
 * return) and feeds the toolchain watch that says when the shim can go;
 * the zmeshopt_canary_shim_* set mirrors src/abi_shim.c's reordered shapes
 * — the path the package actually ships — and must be bit-exact on every
 * backend. src/abi_check.zig pins the raw late-float count at 8; a
 * re-vendor that adds one must extend this file and that count together.
 */
#include <stddef.h>

#include "meshoptimizer.h"

static double slots[20];

double zmeshopt_canary_slot(size_t i) {
    return i < 20 ? slots[i] : -1.0;
}

/* meshopt_simplify: 7 integer-class, then float, then 2 more. */
size_t zmeshopt_canary_simplify(unsigned int* destination, const unsigned int* indices, size_t index_count, const float* vertex_positions, size_t vertex_count, size_t vertex_positions_stride, size_t target_index_count, float target_error, unsigned int options, float* result_error) {
    slots[0] = (double)(size_t)destination;
    slots[1] = (double)(size_t)indices;
    slots[2] = (double)index_count;
    slots[3] = (double)(size_t)vertex_positions;
    slots[4] = (double)vertex_count;
    slots[5] = (double)vertex_positions_stride;
    slots[6] = (double)target_index_count;
    slots[7] = (double)target_error;
    slots[8] = (double)options;
    slots[9] = (double)(size_t)result_error;
    return index_count;
}

/* meshopt_simplifyWithAttributes: 12 integer-class, then float, then 2. */
size_t zmeshopt_canary_simplify_attr(unsigned int* destination, const unsigned int* indices, size_t index_count, const float* vertex_positions, size_t vertex_count, size_t vertex_positions_stride, const float* vertex_attributes, size_t vertex_attributes_stride, const float* attribute_weights, size_t attribute_count, const unsigned char* vertex_lock, size_t target_index_count, float target_error, unsigned int options, float* result_error) {
    slots[0] = (double)(size_t)destination;
    slots[1] = (double)(size_t)indices;
    slots[2] = (double)index_count;
    slots[3] = (double)(size_t)vertex_positions;
    slots[4] = (double)vertex_count;
    slots[5] = (double)vertex_positions_stride;
    slots[6] = (double)(size_t)vertex_attributes;
    slots[7] = (double)vertex_attributes_stride;
    slots[8] = (double)(size_t)attribute_weights;
    slots[9] = (double)attribute_count;
    slots[10] = (double)(size_t)vertex_lock;
    slots[11] = (double)target_index_count;
    slots[12] = (double)target_error;
    slots[13] = (double)options;
    slots[14] = (double)(size_t)result_error;
    return index_count;
}

/* meshopt_simplifyWithUpdate: 11 integer-class, then float, then 2. */
size_t zmeshopt_canary_simplify_update(unsigned int* indices, size_t index_count, float* vertex_positions, size_t vertex_count, size_t vertex_positions_stride, float* vertex_attributes, size_t vertex_attributes_stride, const float* attribute_weights, size_t attribute_count, const unsigned char* vertex_lock, size_t target_index_count, float target_error, unsigned int options, float* result_error) {
    slots[0] = (double)(size_t)indices;
    slots[1] = (double)index_count;
    slots[2] = (double)(size_t)vertex_positions;
    slots[3] = (double)vertex_count;
    slots[4] = (double)vertex_positions_stride;
    slots[5] = (double)(size_t)vertex_attributes;
    slots[6] = (double)vertex_attributes_stride;
    slots[7] = (double)(size_t)attribute_weights;
    slots[8] = (double)attribute_count;
    slots[9] = (double)(size_t)vertex_lock;
    slots[10] = (double)target_index_count;
    slots[11] = (double)target_error;
    slots[12] = (double)options;
    slots[13] = (double)(size_t)result_error;
    return index_count;
}

/* meshopt_simplifySloppy: 8 integer-class, then float, then 1. */
size_t zmeshopt_canary_simplify_sloppy(unsigned int* destination, const unsigned int* indices, size_t index_count, const float* vertex_positions, size_t vertex_count, size_t vertex_positions_stride, const unsigned char* vertex_lock, size_t target_index_count, float target_error, float* result_error) {
    slots[0] = (double)(size_t)destination;
    slots[1] = (double)(size_t)indices;
    slots[2] = (double)index_count;
    slots[3] = (double)(size_t)vertex_positions;
    slots[4] = (double)vertex_count;
    slots[5] = (double)vertex_positions_stride;
    slots[6] = (double)(size_t)vertex_lock;
    slots[7] = (double)target_index_count;
    slots[8] = (double)target_error;
    slots[9] = (double)(size_t)result_error;
    return index_count;
}

/* meshopt_buildMeshlets: 10 integer-class, then float. */
size_t zmeshopt_canary_build_meshlets(struct meshopt_Meshlet* meshlets, unsigned int* meshlet_vertices, unsigned char* meshlet_triangles, const unsigned int* indices, size_t index_count, const float* vertex_positions, size_t vertex_count, size_t vertex_positions_stride, size_t max_vertices, size_t max_triangles, float cone_weight) {
    slots[0] = (double)(size_t)meshlets;
    slots[1] = (double)(size_t)meshlet_vertices;
    slots[2] = (double)(size_t)meshlet_triangles;
    slots[3] = (double)(size_t)indices;
    slots[4] = (double)index_count;
    slots[5] = (double)(size_t)vertex_positions;
    slots[6] = (double)vertex_count;
    slots[7] = (double)vertex_positions_stride;
    slots[8] = (double)max_vertices;
    slots[9] = (double)max_triangles;
    slots[10] = (double)cone_weight;
    return index_count;
}

/* meshopt_buildMeshletsFlex: 11 integer-class, then 2 floats. */
size_t zmeshopt_canary_build_meshlets_flex(struct meshopt_Meshlet* meshlets, unsigned int* meshlet_vertices, unsigned char* meshlet_triangles, const unsigned int* indices, size_t index_count, const float* vertex_positions, size_t vertex_count, size_t vertex_positions_stride, size_t max_vertices, size_t min_triangles, size_t max_triangles, float cone_weight, float split_factor) {
    slots[0] = (double)(size_t)meshlets;
    slots[1] = (double)(size_t)meshlet_vertices;
    slots[2] = (double)(size_t)meshlet_triangles;
    slots[3] = (double)(size_t)indices;
    slots[4] = (double)index_count;
    slots[5] = (double)(size_t)vertex_positions;
    slots[6] = (double)vertex_count;
    slots[7] = (double)vertex_positions_stride;
    slots[8] = (double)max_vertices;
    slots[9] = (double)min_triangles;
    slots[10] = (double)max_triangles;
    slots[11] = (double)cone_weight;
    slots[12] = (double)split_factor;
    return index_count;
}

/* meshopt_buildMeshletsSpatial: 11 integer-class, then float. */
size_t zmeshopt_canary_build_meshlets_spatial(struct meshopt_Meshlet* meshlets, unsigned int* meshlet_vertices, unsigned char* meshlet_triangles, const unsigned int* indices, size_t index_count, const float* vertex_positions, size_t vertex_count, size_t vertex_positions_stride, size_t max_vertices, size_t min_triangles, size_t max_triangles, float fill_weight) {
    slots[0] = (double)(size_t)meshlets;
    slots[1] = (double)(size_t)meshlet_vertices;
    slots[2] = (double)(size_t)meshlet_triangles;
    slots[3] = (double)(size_t)indices;
    slots[4] = (double)index_count;
    slots[5] = (double)(size_t)vertex_positions;
    slots[6] = (double)vertex_count;
    slots[7] = (double)vertex_positions_stride;
    slots[8] = (double)max_vertices;
    slots[9] = (double)min_triangles;
    slots[10] = (double)max_triangles;
    slots[11] = (double)fill_weight;
    return index_count;
}

/* meshopt_opacityMapMeasure: 11 integer-class, then float. */
size_t zmeshopt_canary_opacity_measure(unsigned char* levels, unsigned int* sources, int* omm_indices, const unsigned int* indices, size_t index_count, const float* vertex_uvs, size_t vertex_count, size_t vertex_uvs_stride, unsigned int texture_width, unsigned int texture_height, int max_level, float target_edge) {
    slots[0] = (double)(size_t)levels;
    slots[1] = (double)(size_t)sources;
    slots[2] = (double)(size_t)omm_indices;
    slots[3] = (double)(size_t)indices;
    slots[4] = (double)index_count;
    slots[5] = (double)(size_t)vertex_uvs;
    slots[6] = (double)vertex_count;
    slots[7] = (double)vertex_uvs_stride;
    slots[8] = (double)texture_width;
    slots[9] = (double)texture_height;
    slots[10] = (double)max_level;
    slots[11] = (double)target_edge;
    return index_count;
}

/* The raw all-float 16-byte struct return, for the toolchain watch. */
struct meshopt_CoverageStatistics zmeshopt_canary_coverage_return(void) {
    struct meshopt_CoverageStatistics stats;
    stats.coverage[0] = 1.25f;
    stats.coverage[1] = 2.5f;
    stats.coverage[2] = 3.75f;
    stats.extent = 5.0f;
    return stats;
}

/* Echo mirrors of the shim shapes in src/abi_shim.c, floats first. */
size_t zmeshopt_canary_shim_simplify(float target_error, unsigned int* destination, const unsigned int* indices, size_t index_count, const float* vertex_positions, size_t vertex_count, size_t vertex_positions_stride, size_t target_index_count, unsigned int options, float* result_error) {
    slots[0] = (double)target_error;
    slots[1] = (double)(size_t)destination;
    slots[2] = (double)(size_t)indices;
    slots[3] = (double)index_count;
    slots[4] = (double)(size_t)vertex_positions;
    slots[5] = (double)vertex_count;
    slots[6] = (double)vertex_positions_stride;
    slots[7] = (double)target_index_count;
    slots[8] = (double)options;
    slots[9] = (double)(size_t)result_error;
    return index_count;
}

size_t zmeshopt_canary_shim_simplify_attr(float target_error, unsigned int* destination, const unsigned int* indices, size_t index_count, const float* vertex_positions, size_t vertex_count, size_t vertex_positions_stride, const float* vertex_attributes, size_t vertex_attributes_stride, const float* attribute_weights, size_t attribute_count, const unsigned char* vertex_lock, size_t target_index_count, unsigned int options, float* result_error) {
    slots[0] = (double)target_error;
    slots[1] = (double)(size_t)destination;
    slots[2] = (double)(size_t)indices;
    slots[3] = (double)index_count;
    slots[4] = (double)(size_t)vertex_positions;
    slots[5] = (double)vertex_count;
    slots[6] = (double)vertex_positions_stride;
    slots[7] = (double)(size_t)vertex_attributes;
    slots[8] = (double)vertex_attributes_stride;
    slots[9] = (double)(size_t)attribute_weights;
    slots[10] = (double)attribute_count;
    slots[11] = (double)(size_t)vertex_lock;
    slots[12] = (double)target_index_count;
    slots[13] = (double)options;
    slots[14] = (double)(size_t)result_error;
    return index_count;
}

size_t zmeshopt_canary_shim_simplify_update(float target_error, unsigned int* indices, size_t index_count, float* vertex_positions, size_t vertex_count, size_t vertex_positions_stride, float* vertex_attributes, size_t vertex_attributes_stride, const float* attribute_weights, size_t attribute_count, const unsigned char* vertex_lock, size_t target_index_count, unsigned int options, float* result_error) {
    slots[0] = (double)target_error;
    slots[1] = (double)(size_t)indices;
    slots[2] = (double)index_count;
    slots[3] = (double)(size_t)vertex_positions;
    slots[4] = (double)vertex_count;
    slots[5] = (double)vertex_positions_stride;
    slots[6] = (double)(size_t)vertex_attributes;
    slots[7] = (double)vertex_attributes_stride;
    slots[8] = (double)(size_t)attribute_weights;
    slots[9] = (double)attribute_count;
    slots[10] = (double)(size_t)vertex_lock;
    slots[11] = (double)target_index_count;
    slots[12] = (double)options;
    slots[13] = (double)(size_t)result_error;
    return index_count;
}

size_t zmeshopt_canary_shim_simplify_sloppy(float target_error, unsigned int* destination, const unsigned int* indices, size_t index_count, const float* vertex_positions, size_t vertex_count, size_t vertex_positions_stride, const unsigned char* vertex_lock, size_t target_index_count, float* result_error) {
    slots[0] = (double)target_error;
    slots[1] = (double)(size_t)destination;
    slots[2] = (double)(size_t)indices;
    slots[3] = (double)index_count;
    slots[4] = (double)(size_t)vertex_positions;
    slots[5] = (double)vertex_count;
    slots[6] = (double)vertex_positions_stride;
    slots[7] = (double)(size_t)vertex_lock;
    slots[8] = (double)target_index_count;
    slots[9] = (double)(size_t)result_error;
    return index_count;
}

size_t zmeshopt_canary_shim_build_meshlets(float cone_weight, struct meshopt_Meshlet* meshlets, unsigned int* meshlet_vertices, unsigned char* meshlet_triangles, const unsigned int* indices, size_t index_count, const float* vertex_positions, size_t vertex_count, size_t vertex_positions_stride, size_t max_vertices, size_t max_triangles) {
    slots[0] = (double)cone_weight;
    slots[1] = (double)(size_t)meshlets;
    slots[2] = (double)(size_t)meshlet_vertices;
    slots[3] = (double)(size_t)meshlet_triangles;
    slots[4] = (double)(size_t)indices;
    slots[5] = (double)index_count;
    slots[6] = (double)(size_t)vertex_positions;
    slots[7] = (double)vertex_count;
    slots[8] = (double)vertex_positions_stride;
    slots[9] = (double)max_vertices;
    slots[10] = (double)max_triangles;
    return index_count;
}

size_t zmeshopt_canary_shim_build_meshlets_flex(float cone_weight, float split_factor, struct meshopt_Meshlet* meshlets, unsigned int* meshlet_vertices, unsigned char* meshlet_triangles, const unsigned int* indices, size_t index_count, const float* vertex_positions, size_t vertex_count, size_t vertex_positions_stride, size_t max_vertices, size_t min_triangles, size_t max_triangles) {
    slots[0] = (double)cone_weight;
    slots[1] = (double)split_factor;
    slots[2] = (double)(size_t)meshlets;
    slots[3] = (double)(size_t)meshlet_vertices;
    slots[4] = (double)(size_t)meshlet_triangles;
    slots[5] = (double)(size_t)indices;
    slots[6] = (double)index_count;
    slots[7] = (double)(size_t)vertex_positions;
    slots[8] = (double)vertex_count;
    slots[9] = (double)vertex_positions_stride;
    slots[10] = (double)max_vertices;
    slots[11] = (double)min_triangles;
    slots[12] = (double)max_triangles;
    return index_count;
}

size_t zmeshopt_canary_shim_build_meshlets_spatial(float fill_weight, struct meshopt_Meshlet* meshlets, unsigned int* meshlet_vertices, unsigned char* meshlet_triangles, const unsigned int* indices, size_t index_count, const float* vertex_positions, size_t vertex_count, size_t vertex_positions_stride, size_t max_vertices, size_t min_triangles, size_t max_triangles) {
    slots[0] = (double)fill_weight;
    slots[1] = (double)(size_t)meshlets;
    slots[2] = (double)(size_t)meshlet_vertices;
    slots[3] = (double)(size_t)meshlet_triangles;
    slots[4] = (double)(size_t)indices;
    slots[5] = (double)index_count;
    slots[6] = (double)(size_t)vertex_positions;
    slots[7] = (double)vertex_count;
    slots[8] = (double)vertex_positions_stride;
    slots[9] = (double)max_vertices;
    slots[10] = (double)min_triangles;
    slots[11] = (double)max_triangles;
    return index_count;
}

size_t zmeshopt_canary_shim_opacity_measure(float target_edge, unsigned char* levels, unsigned int* sources, int* omm_indices, const unsigned int* indices, size_t index_count, const float* vertex_uvs, size_t vertex_count, size_t vertex_uvs_stride, unsigned int texture_width, unsigned int texture_height, int max_level) {
    slots[0] = (double)target_edge;
    slots[1] = (double)(size_t)levels;
    slots[2] = (double)(size_t)sources;
    slots[3] = (double)(size_t)omm_indices;
    slots[4] = (double)(size_t)indices;
    slots[5] = (double)index_count;
    slots[6] = (double)(size_t)vertex_uvs;
    slots[7] = (double)vertex_count;
    slots[8] = (double)vertex_uvs_stride;
    slots[9] = (double)texture_width;
    slots[10] = (double)texture_height;
    slots[11] = (double)max_level;
    return index_count;
}

void zmeshopt_canary_shim_coverage(struct meshopt_CoverageStatistics* out, const unsigned int* indices, size_t index_count, const float* vertex_positions, size_t vertex_count, size_t vertex_positions_stride) {
    slots[0] = (double)(size_t)out;
    slots[1] = (double)(size_t)indices;
    slots[2] = (double)index_count;
    slots[3] = (double)(size_t)vertex_positions;
    slots[4] = (double)vertex_count;
    slots[5] = (double)vertex_positions_stride;
    out->coverage[0] = 1.25f;
    out->coverage[1] = 2.5f;
    out->coverage[2] = 3.75f;
    out->extent = 5.0f;
}
