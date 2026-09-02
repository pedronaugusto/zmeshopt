/*
 * zmeshopt — caller-shape forwarders. See abi_shim.h for why they exist and
 * what retires them. Each forwards to upstream verbatim, argument for
 * argument; nothing here may add behaviour.
 */
#include "abi_shim.h"

size_t zmeshopt_shim_simplify(float target_error, unsigned int* destination, const unsigned int* indices, size_t index_count, const float* vertex_positions, size_t vertex_count, size_t vertex_positions_stride, size_t target_index_count, unsigned int options, float* result_error) {
    return meshopt_simplify(destination, indices, index_count, vertex_positions, vertex_count, vertex_positions_stride, target_index_count, target_error, options, result_error);
}

size_t zmeshopt_shim_simplifyWithAttributes(float target_error, unsigned int* destination, const unsigned int* indices, size_t index_count, const float* vertex_positions, size_t vertex_count, size_t vertex_positions_stride, const float* vertex_attributes, size_t vertex_attributes_stride, const float* attribute_weights, size_t attribute_count, const unsigned char* vertex_lock, size_t target_index_count, unsigned int options, float* result_error) {
    return meshopt_simplifyWithAttributes(destination, indices, index_count, vertex_positions, vertex_count, vertex_positions_stride, vertex_attributes, vertex_attributes_stride, attribute_weights, attribute_count, vertex_lock, target_index_count, target_error, options, result_error);
}

size_t zmeshopt_shim_simplifyWithUpdate(float target_error, unsigned int* indices, size_t index_count, float* vertex_positions, size_t vertex_count, size_t vertex_positions_stride, float* vertex_attributes, size_t vertex_attributes_stride, const float* attribute_weights, size_t attribute_count, const unsigned char* vertex_lock, size_t target_index_count, unsigned int options, float* result_error) {
    return meshopt_simplifyWithUpdate(indices, index_count, vertex_positions, vertex_count, vertex_positions_stride, vertex_attributes, vertex_attributes_stride, attribute_weights, attribute_count, vertex_lock, target_index_count, target_error, options, result_error);
}

size_t zmeshopt_shim_simplifySloppy(float target_error, unsigned int* destination, const unsigned int* indices, size_t index_count, const float* vertex_positions, size_t vertex_count, size_t vertex_positions_stride, const unsigned char* vertex_lock, size_t target_index_count, float* result_error) {
    return meshopt_simplifySloppy(destination, indices, index_count, vertex_positions, vertex_count, vertex_positions_stride, vertex_lock, target_index_count, target_error, result_error);
}

size_t zmeshopt_shim_buildMeshlets(float cone_weight, struct meshopt_Meshlet* meshlets, unsigned int* meshlet_vertices, unsigned char* meshlet_triangles, const unsigned int* indices, size_t index_count, const float* vertex_positions, size_t vertex_count, size_t vertex_positions_stride, size_t max_vertices, size_t max_triangles) {
    return meshopt_buildMeshlets(meshlets, meshlet_vertices, meshlet_triangles, indices, index_count, vertex_positions, vertex_count, vertex_positions_stride, max_vertices, max_triangles, cone_weight);
}

size_t zmeshopt_shim_buildMeshletsFlex(float cone_weight, float split_factor, struct meshopt_Meshlet* meshlets, unsigned int* meshlet_vertices, unsigned char* meshlet_triangles, const unsigned int* indices, size_t index_count, const float* vertex_positions, size_t vertex_count, size_t vertex_positions_stride, size_t max_vertices, size_t min_triangles, size_t max_triangles) {
    return meshopt_buildMeshletsFlex(meshlets, meshlet_vertices, meshlet_triangles, indices, index_count, vertex_positions, vertex_count, vertex_positions_stride, max_vertices, min_triangles, max_triangles, cone_weight, split_factor);
}

size_t zmeshopt_shim_buildMeshletsSpatial(float fill_weight, struct meshopt_Meshlet* meshlets, unsigned int* meshlet_vertices, unsigned char* meshlet_triangles, const unsigned int* indices, size_t index_count, const float* vertex_positions, size_t vertex_count, size_t vertex_positions_stride, size_t max_vertices, size_t min_triangles, size_t max_triangles) {
    return meshopt_buildMeshletsSpatial(meshlets, meshlet_vertices, meshlet_triangles, indices, index_count, vertex_positions, vertex_count, vertex_positions_stride, max_vertices, min_triangles, max_triangles, fill_weight);
}

size_t zmeshopt_shim_opacityMapMeasure(float target_edge, unsigned char* levels, unsigned int* sources, int* omm_indices, const unsigned int* indices, size_t index_count, const float* vertex_uvs, size_t vertex_count, size_t vertex_uvs_stride, unsigned int texture_width, unsigned int texture_height, int max_level) {
    return meshopt_opacityMapMeasure(levels, sources, omm_indices, indices, index_count, vertex_uvs, vertex_count, vertex_uvs_stride, texture_width, texture_height, max_level, target_edge);
}

void zmeshopt_shim_analyzeCoverage(struct meshopt_CoverageStatistics* out, const unsigned int* indices, size_t index_count, const float* vertex_positions, size_t vertex_count, size_t vertex_positions_stride) {
    *out = meshopt_analyzeCoverage(indices, index_count, vertex_positions, vertex_count, vertex_positions_stride);
}
