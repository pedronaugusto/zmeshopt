/*
 * zmeshopt — prototypes for the caller-shape forwarders in abi_shim.c.
 *
 * Zig 0.16.0 was measured (CI, 2026-09-02) miscompiling two caller shapes
 * upstream's ABI requires: an f32 argument after more than 6 integer-class
 * arguments (self-hosted backend, x86_64-linux) and an all-float 16-byte
 * struct return (both backends on x86_64-linux, the LLVM backend on
 * aarch64-macos). Each forwarder re-spells one affected function with its
 * floats FIRST, or its struct return as an out-parameter, and tail-calls
 * upstream. Compiled by clang regardless of the Zig backend, and called by
 * the idiomatic layer on every backend: one code path, tested everywhere.
 * src/abi_check.zig holds src/shim.zig's externs to these prototypes; the
 * toolchain watch in src/abi_canary_test.zig says when the shim can go.
 */
#ifndef ZMESHOPT_ABI_SHIM_H
#define ZMESHOPT_ABI_SHIM_H

#include <stddef.h>

#include "meshoptimizer.h"

#if defined(_WIN32) && defined(ZMESHOPT_SHIM_SHARED)
#define ZMESHOPT_SHIM_API __declspec(dllexport)
#else
#define ZMESHOPT_SHIM_API
#endif

#ifdef __cplusplus
extern "C" {
#endif

ZMESHOPT_SHIM_API size_t zmeshopt_shim_simplify(float target_error, unsigned int* destination, const unsigned int* indices, size_t index_count, const float* vertex_positions, size_t vertex_count, size_t vertex_positions_stride, size_t target_index_count, unsigned int options, float* result_error);
ZMESHOPT_SHIM_API size_t zmeshopt_shim_simplifyWithAttributes(float target_error, unsigned int* destination, const unsigned int* indices, size_t index_count, const float* vertex_positions, size_t vertex_count, size_t vertex_positions_stride, const float* vertex_attributes, size_t vertex_attributes_stride, const float* attribute_weights, size_t attribute_count, const unsigned char* vertex_lock, size_t target_index_count, unsigned int options, float* result_error);
ZMESHOPT_SHIM_API size_t zmeshopt_shim_simplifyWithUpdate(float target_error, unsigned int* indices, size_t index_count, float* vertex_positions, size_t vertex_count, size_t vertex_positions_stride, float* vertex_attributes, size_t vertex_attributes_stride, const float* attribute_weights, size_t attribute_count, const unsigned char* vertex_lock, size_t target_index_count, unsigned int options, float* result_error);
ZMESHOPT_SHIM_API size_t zmeshopt_shim_simplifySloppy(float target_error, unsigned int* destination, const unsigned int* indices, size_t index_count, const float* vertex_positions, size_t vertex_count, size_t vertex_positions_stride, const unsigned char* vertex_lock, size_t target_index_count, float* result_error);
ZMESHOPT_SHIM_API size_t zmeshopt_shim_buildMeshlets(float cone_weight, struct meshopt_Meshlet* meshlets, unsigned int* meshlet_vertices, unsigned char* meshlet_triangles, const unsigned int* indices, size_t index_count, const float* vertex_positions, size_t vertex_count, size_t vertex_positions_stride, size_t max_vertices, size_t max_triangles);
ZMESHOPT_SHIM_API size_t zmeshopt_shim_buildMeshletsFlex(float cone_weight, float split_factor, struct meshopt_Meshlet* meshlets, unsigned int* meshlet_vertices, unsigned char* meshlet_triangles, const unsigned int* indices, size_t index_count, const float* vertex_positions, size_t vertex_count, size_t vertex_positions_stride, size_t max_vertices, size_t min_triangles, size_t max_triangles);
ZMESHOPT_SHIM_API size_t zmeshopt_shim_buildMeshletsSpatial(float fill_weight, struct meshopt_Meshlet* meshlets, unsigned int* meshlet_vertices, unsigned char* meshlet_triangles, const unsigned int* indices, size_t index_count, const float* vertex_positions, size_t vertex_count, size_t vertex_positions_stride, size_t max_vertices, size_t min_triangles, size_t max_triangles);
ZMESHOPT_SHIM_API size_t zmeshopt_shim_opacityMapMeasure(float target_edge, unsigned char* levels, unsigned int* sources, int* omm_indices, const unsigned int* indices, size_t index_count, const float* vertex_uvs, size_t vertex_count, size_t vertex_uvs_stride, unsigned int texture_width, unsigned int texture_height, int max_level);
ZMESHOPT_SHIM_API void zmeshopt_shim_analyzeCoverage(struct meshopt_CoverageStatistics* out, const unsigned int* indices, size_t index_count, const float* vertex_positions, size_t vertex_count, size_t vertex_positions_stride);

#ifdef __cplusplus
}
#endif

#endif
