/*
 * The C twins of the bench rows: each loops the same upstream work in C,
 * once calling upstream directly and, where the idiomatic layer crosses
 * src/abi_shim.c, once through that forwarder, so the Zig layer's cost and
 * the forwarding hop's are each a difference of two rows. Floats come first,
 * as the shim spells them, so no row crosses a shape the shim exists for.
 */
#include <stddef.h>

#include "meshoptimizer.h"
#include "../src/abi_shim.h"

size_t zmeshopt_baseline_simplify(float target_error, unsigned int* destination, const unsigned int* indices, size_t index_count, const float* positions, size_t vertex_count, size_t stride, size_t target_index_count, unsigned long long times)
{
	size_t total = 0;
	for (unsigned long long i = 0; i < times; ++i)
		total += meshopt_simplify(destination, indices, index_count, positions, vertex_count, stride, target_index_count, target_error, 0, NULL);
	return total;
}

size_t zmeshopt_baseline_simplify_shim(float target_error, unsigned int* destination, const unsigned int* indices, size_t index_count, const float* positions, size_t vertex_count, size_t stride, size_t target_index_count, unsigned long long times)
{
	size_t total = 0;
	for (unsigned long long i = 0; i < times; ++i)
		total += zmeshopt_shim_simplify(target_error, destination, indices, index_count, positions, vertex_count, stride, target_index_count, 0, NULL);
	return total;
}

size_t zmeshopt_baseline_build_meshlets(float cone_weight, struct meshopt_Meshlet* meshlets, unsigned int* meshlet_vertices, unsigned char* meshlet_triangles, const unsigned int* indices, size_t index_count, const float* positions, size_t vertex_count, size_t stride, size_t max_vertices, size_t max_triangles, unsigned long long times)
{
	size_t total = 0;
	for (unsigned long long i = 0; i < times; ++i)
		total += meshopt_buildMeshlets(meshlets, meshlet_vertices, meshlet_triangles, indices, index_count, positions, vertex_count, stride, max_vertices, max_triangles, cone_weight);
	return total;
}

size_t zmeshopt_baseline_build_meshlets_shim(float cone_weight, struct meshopt_Meshlet* meshlets, unsigned int* meshlet_vertices, unsigned char* meshlet_triangles, const unsigned int* indices, size_t index_count, const float* positions, size_t vertex_count, size_t stride, size_t max_vertices, size_t max_triangles, unsigned long long times)
{
	size_t total = 0;
	for (unsigned long long i = 0; i < times; ++i)
		total += zmeshopt_shim_buildMeshlets(cone_weight, meshlets, meshlet_vertices, meshlet_triangles, indices, index_count, positions, vertex_count, stride, max_vertices, max_triangles);
	return total;
}

float zmeshopt_baseline_analyze_coverage(const unsigned int* indices, size_t index_count, const float* positions, size_t vertex_count, size_t stride, unsigned long long times)
{
	float total = 0;
	for (unsigned long long i = 0; i < times; ++i)
		total += meshopt_analyzeCoverage(indices, index_count, positions, vertex_count, stride).coverage[0];
	return total;
}

float zmeshopt_baseline_analyze_coverage_shim(const unsigned int* indices, size_t index_count, const float* positions, size_t vertex_count, size_t stride, unsigned long long times)
{
	float total = 0;
	for (unsigned long long i = 0; i < times; ++i)
	{
		struct meshopt_CoverageStatistics out;
		zmeshopt_shim_analyzeCoverage(&out, indices, index_count, positions, vertex_count, stride);
		total += out.coverage[0];
	}
	return total;
}

void zmeshopt_baseline_optimize_vertex_cache(unsigned int* destination, const unsigned int* indices, size_t index_count, size_t vertex_count, unsigned long long times)
{
	for (unsigned long long i = 0; i < times; ++i)
		meshopt_optimizeVertexCache(destination, indices, index_count, vertex_count);
}

int zmeshopt_baseline_decode_index_buffer(unsigned int* destination, size_t index_count, const unsigned char* buffer, size_t buffer_size, unsigned long long times)
{
	int total = 0;
	for (unsigned long long i = 0; i < times; ++i)
		total |= meshopt_decodeIndexBuffer(destination, index_count, sizeof(unsigned int), buffer, buffer_size);
	return total;
}

int zmeshopt_baseline_decode_vertex_buffer(void* destination, size_t vertex_count, size_t vertex_size, const unsigned char* buffer, size_t buffer_size, unsigned long long times)
{
	int total = 0;
	for (unsigned long long i = 0; i < times; ++i)
		total |= meshopt_decodeVertexBuffer(destination, vertex_count, vertex_size, buffer, buffer_size);
	return total;
}
