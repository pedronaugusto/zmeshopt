//! zmeshopt — complete Zig bindings for meshoptimizer v1.2.
//!
//! Three layers, thinnest first:
//!
//!   * `c` — the raw externs, one module per header region, mirroring the
//!     vendored `meshoptimizer.h` exactly; `src/abi_check.zig`'s reverse
//!     sweep fails the build if a header function is ever missing.
//!   * The idiomatic layer — slice-based wrappers in the per-area files
//!     (`src/remap.zig`, `src/simplify.zig`, …), re-exported flat below
//!     under upstream's names minus the `meshopt_` prefix, plus the
//!     Zig-allocator adapter (`src/memory.zig`) and the C++-only quantize
//!     helpers reimplemented in Zig (`src/quantize.zig`).
//!   * The type re-exports — the same types under their Zig names, so a
//!     caller never has to spell `c.simplify.…`.

const std = @import("std");

/// How the C++ half was built (`shared`, `sanitize_c`, `simd`) plus the
/// package version — the build options module, re-exported so a consumer
/// can branch on it without plumbing a second module import.
pub const options = @import("zmeshopt_options");

pub const c = @import("c.zig");

const remap_area = @import("remap.zig");
const cache_area = @import("cache.zig");
const index_codec_area = @import("index_codec.zig");
const meshlet_codec_area = @import("meshlet_codec.zig");
const vertex_codec_area = @import("vertex_codec.zig");
const decode_filters_area = @import("decode_filters.zig");
const encode_filters_area = @import("encode_filters.zig");
const simplify_area = @import("simplify.zig");
const stripify_area = @import("stripify.zig");
const analyze_area = @import("analyze.zig");
const clusterize_area = @import("clusterize.zig");
const partition_area = @import("partition.zig");
const spatial_area = @import("spatial.zig");
const opacity_area = @import("opacity.zig");
const tangents_area = @import("tangents.zig");
const quantize_area = @import("quantize.zig");
const memory_area = @import("memory.zig");

// Shared value types, re-exported from their declaring modules.
pub const Stream = c.remap.Stream;
pub const RemapCallback = c.remap.RemapCallback;
pub const EncodeExpMode = c.encode_filters.EncodeExpMode;
pub const SimplifyOptions = c.simplify.SimplifyOptions;
pub const SimplifyVertexFlags = c.simplify.SimplifyVertexFlags;
pub const TangentOptions = c.tangents.TangentOptions;
pub const Meshlet = c.clusterize.Meshlet;
pub const Bounds = c.clusterize.Bounds;
pub const VertexCacheStatistics = c.analyze.VertexCacheStatistics;
pub const VertexFetchStatistics = c.analyze.VertexFetchStatistics;
pub const OverdrawStatistics = c.analyze.OverdrawStatistics;
pub const CoverageStatistics = c.analyze.CoverageStatistics;

// Idiomatic-layer types.
pub const IndexCodecVersion = index_codec_area.IndexCodecVersion;
pub const VertexCodecVersion = vertex_codec_area.VertexCodecVersion;
pub const SimplifyResult = simplify_area.Result;
pub const SimplifyAttributes = simplify_area.Attributes;
pub const SimplifyMutableAttributes = simplify_area.MutableAttributes;
pub const SimplifyColors = simplify_area.Colors;
pub const OpacityStates = opacity_area.OpacityStates;
pub const AlphaTexture = opacity_area.AlphaTexture;
pub const AllocateFn = memory_area.AllocateFn;
pub const DeallocateFn = memory_area.DeallocateFn;

// Indexing and remapping.
pub const generateVertexRemap = remap_area.generateVertexRemap;
pub const generateVertexRemapMulti = remap_area.generateVertexRemapMulti;
pub const generateVertexRemapCustom = remap_area.generateVertexRemapCustom;
pub const remapVertexBuffer = remap_area.remapVertexBuffer;
pub const remapIndexBuffer = remap_area.remapIndexBuffer;
pub const filterIndexBuffer = remap_area.filterIndexBuffer;
pub const filterIndexBufferMulti = remap_area.filterIndexBufferMulti;
pub const generateShadowIndexBuffer = remap_area.generateShadowIndexBuffer;
pub const generateShadowIndexBufferMulti = remap_area.generateShadowIndexBufferMulti;
pub const generatePositionRemap = remap_area.generatePositionRemap;
pub const generateAdjacencyIndexBuffer = remap_area.generateAdjacencyIndexBuffer;
pub const generateTessellationIndexBuffer = remap_area.generateTessellationIndexBuffer;
pub const generateProvokingIndexBuffer = remap_area.generateProvokingIndexBuffer;

// Vertex cache, overdraw and vertex fetch optimizers.
pub const optimizeVertexCache = cache_area.optimizeVertexCache;
pub const optimizeVertexCacheStrip = cache_area.optimizeVertexCacheStrip;
pub const optimizeVertexCacheFifo = cache_area.optimizeVertexCacheFifo;
pub const optimizeOverdraw = cache_area.optimizeOverdraw;
pub const optimizeVertexFetch = cache_area.optimizeVertexFetch;
pub const optimizeVertexFetchRemap = cache_area.optimizeVertexFetchRemap;

// Index codec.
pub const encodeIndexBuffer = index_codec_area.encodeIndexBuffer;
pub const encodeIndexBufferBound = index_codec_area.encodeIndexBufferBound;
pub const encodeIndexVersion = index_codec_area.encodeIndexVersion;
pub const decodeIndexBuffer = index_codec_area.decodeIndexBuffer;
pub const decodeIndexVersion = index_codec_area.decodeIndexVersion;
pub const encodeIndexSequence = index_codec_area.encodeIndexSequence;
pub const encodeIndexSequenceBound = index_codec_area.encodeIndexSequenceBound;
pub const decodeIndexSequence = index_codec_area.decodeIndexSequence;

// Meshlet codec.
pub const encodeMeshlet = meshlet_codec_area.encodeMeshlet;
pub const encodeMeshletBound = meshlet_codec_area.encodeMeshletBound;
pub const decodeMeshlet = meshlet_codec_area.decodeMeshlet;
pub const decodeMeshletRaw = meshlet_codec_area.decodeMeshletRaw;

// Vertex codec.
pub const encodeVertexBuffer = vertex_codec_area.encodeVertexBuffer;
pub const encodeVertexBufferBound = vertex_codec_area.encodeVertexBufferBound;
pub const encodeVertexBufferLevel = vertex_codec_area.encodeVertexBufferLevel;
pub const encodeVertexVersion = vertex_codec_area.encodeVertexVersion;
pub const decodeVertexBuffer = vertex_codec_area.decodeVertexBuffer;
pub const decodeVertexVersion = vertex_codec_area.decodeVertexVersion;

// Vertex filters.
pub const decodeFilterOct = decode_filters_area.decodeFilterOct;
pub const decodeFilterQuat = decode_filters_area.decodeFilterQuat;
pub const decodeFilterExp = decode_filters_area.decodeFilterExp;
pub const decodeFilterColor = decode_filters_area.decodeFilterColor;
pub const encodeFilterOct = encode_filters_area.encodeFilterOct;
pub const encodeFilterQuat = encode_filters_area.encodeFilterQuat;
pub const encodeFilterExp = encode_filters_area.encodeFilterExp;
pub const encodeFilterColor = encode_filters_area.encodeFilterColor;

// Simplifiers.
pub const simplify = simplify_area.simplify;
pub const simplifyWithAttributes = simplify_area.simplifyWithAttributes;
pub const simplifyWithUpdate = simplify_area.simplifyWithUpdate;
pub const simplifySloppy = simplify_area.simplifySloppy;
pub const simplifyPrune = simplify_area.simplifyPrune;
pub const simplifyPoints = simplify_area.simplifyPoints;
pub const simplifyScale = simplify_area.scale;

// Triangle strips.
pub const stripify = stripify_area.stripify;
pub const stripifyBound = stripify_area.stripifyBound;
pub const unstripify = stripify_area.unstripify;
pub const unstripifyBound = stripify_area.unstripifyBound;

// Analyzers.
pub const analyzeVertexCache = analyze_area.analyzeVertexCache;
pub const analyzeVertexFetch = analyze_area.analyzeVertexFetch;
pub const analyzeOverdraw = analyze_area.analyzeOverdraw;
pub const analyzeCoverage = analyze_area.analyzeCoverage;

// Meshlets and cluster bounds.
pub const buildMeshlets = clusterize_area.buildMeshlets;
pub const buildMeshletsScan = clusterize_area.buildMeshletsScan;
pub const buildMeshletsBound = clusterize_area.buildMeshletsBound;
pub const buildMeshletsFlex = clusterize_area.buildMeshletsFlex;
pub const buildMeshletsSpatial = clusterize_area.buildMeshletsSpatial;
pub const optimizeMeshlet = clusterize_area.optimizeMeshlet;
pub const optimizeMeshletLevel = clusterize_area.optimizeMeshletLevel;
pub const computeClusterBounds = clusterize_area.computeClusterBounds;
pub const computeMeshletBounds = clusterize_area.computeMeshletBounds;
pub const computeSphereBounds = clusterize_area.computeSphereBounds;
pub const extractMeshletIndices = clusterize_area.extractMeshletIndices;
pub const meshletVertexSlice = clusterize_area.vertexSlice;
pub const meshletTriangleSlice = clusterize_area.triangleSlice;

// Cluster partitioning and spatial sorting.
pub const partitionClusters = partition_area.partitionClusters;
pub const partitionClustersBySharing = partition_area.partitionClustersBySharing;
pub const spatialSortRemap = spatial_area.spatialSortRemap;
pub const spatialSortTriangles = spatial_area.spatialSortTriangles;
pub const spatialClusterPoints = spatial_area.spatialClusterPoints;

// Opacity micromaps (all experimental upstream).
pub const opacityMapMeasure = opacity_area.opacityMapMeasure;
pub const opacityMapRasterize = opacity_area.opacityMapRasterize;
pub const opacityMapEntrySize = opacity_area.opacityMapEntrySize;
pub const opacityMapCompact = opacity_area.opacityMapCompact;

// Tangents.
pub const generateTangents = tangents_area.generateTangents;

// Scalar quantization (`quantizeUnorm`/`quantizeSnorm` are Zig
// reimplementations of upstream's C++-only inline helpers).
pub const quantizeHalf = quantize_area.quantizeHalf;
pub const quantizeFloat = quantize_area.quantizeFloat;
pub const dequantizeHalf = quantize_area.dequantizeHalf;
pub const quantizeUnorm = quantize_area.quantizeUnorm;
pub const quantizeSnorm = quantize_area.quantizeSnorm;
pub const computePositionExponent = quantize_area.computePositionExponent;

// Memory.
pub const setAllocator = memory_area.setAllocator;
pub const installZigAllocator = memory_area.installZigAllocator;

/// The package version, from `build.zig.zon` — the version's one home —
/// carried through the `zmeshopt_options` module by `build.zig`.
pub fn version() []const u8 {
    return options.version;
}

test version {
    // A malformed version here means build.zig.zon's is malformed: this is
    // the same string, injected at build time.
    const v = version();
    var it = std.mem.splitScalar(u8, v, '.');
    var parts: usize = 0;
    while (it.next()) |part| : (parts += 1) {
        _ = try std.fmt.parseInt(u32, part, 10);
    }
    try std.testing.expectEqual(@as(usize, 3), parts);
}

test {
    _ = @import("abi_check.zig");
    _ = @import("abi_canary_test.zig");
    _ = remap_area;
    _ = cache_area;
    _ = index_codec_area;
    _ = meshlet_codec_area;
    _ = vertex_codec_area;
    _ = decode_filters_area;
    _ = encode_filters_area;
    _ = simplify_area;
    _ = stripify_area;
    _ = analyze_area;
    _ = clusterize_area;
    _ = partition_area;
    _ = spatial_area;
    _ = opacity_area;
    _ = tangents_area;
    _ = quantize_area;
    _ = memory_area;
}
