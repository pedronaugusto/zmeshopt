/*
 * zmeshopt — the late-float caller-codegen canary. TEST-ONLY: compiled into
 * the Zig test executable, never into the shipped library.
 *
 * Eight meshoptimizer functions pass a float after more than 6 integer-class
 * parameters, a shape Zig 0.16.0's self-hosted x86-64 backend was measured
 * (zjolt, 2026-09-01) misallocating in the CALLER on x86_64-linux. This
 * binding cannot forbid the shape — it is upstream's ABI — so it measures it
 * instead: each function below mirrors one affected signature's parameter
 * list exactly, echoes every argument into a slot array, and
 * src/late_float_canary_test.zig asserts each one arrives bit-exact. A
 * toolchain that miscompiles these callers turns the suite red with a named
 * canary instead of shipping silently wrong meshes.
 *
 * src/abi_check.zig pins the affected-signature count at 8; a re-vendor that
 * adds one must extend this file and that count together.
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
