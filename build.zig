const std = @import("std");

/// Sources of the vendored meshoptimizer library: all 20 of upstream's
/// translation units, listed rather than globbed so a re-vendor cannot
/// silently change what compiles. `ci/vendor.zig` holds this list to the
/// vendored tree in both directions.
const meshopt_sources = [_][]const u8{
    "libs/meshoptimizer/src/allocator.cpp",
    "libs/meshoptimizer/src/clusterizer.cpp",
    "libs/meshoptimizer/src/indexanalyzer.cpp",
    "libs/meshoptimizer/src/indexcodec.cpp",
    "libs/meshoptimizer/src/indexgenerator.cpp",
    "libs/meshoptimizer/src/meshletcodec.cpp",
    "libs/meshoptimizer/src/meshletutils.cpp",
    "libs/meshoptimizer/src/opacitymap.cpp",
    "libs/meshoptimizer/src/overdrawoptimizer.cpp",
    "libs/meshoptimizer/src/partition.cpp",
    "libs/meshoptimizer/src/quantization.cpp",
    "libs/meshoptimizer/src/rasterizer.cpp",
    "libs/meshoptimizer/src/simplifier.cpp",
    "libs/meshoptimizer/src/spatialorder.cpp",
    "libs/meshoptimizer/src/stripifier.cpp",
    "libs/meshoptimizer/src/tangentspace.cpp",
    "libs/meshoptimizer/src/vcacheoptimizer.cpp",
    "libs/meshoptimizer/src/vertexcodec.cpp",
    "libs/meshoptimizer/src/vertexfilter.cpp",
    "libs/meshoptimizer/src/vfetchoptimizer.cpp",
};

// Refuses a source listed twice. A duplicate is invisible in a static
// archive (the linker takes one member and never looks at the other), so it
// survives every default build and only surfaces in the shared library.
comptime {
    @setEvalBranchQuota(100_000);
    for (meshopt_sources, 0..) |a, i| {
        for (meshopt_sources[i + 1 ..]) |b| {
            if (std.mem.eql(u8, a, b)) @compileError("build.zig lists `" ++ a ++ "` more than once");
        }
    }
}

/// How the C++ is built. Every field is mirrored into the `zmeshopt_options`
/// module, so the wrapper can never disagree with the library.
const Options = struct {
    shared: bool = false,
    // Off by default, and deliberately NOT tied to `optimize`: Zig's C
    // sanitizer emits calls into a runtime linked only into a compilation
    // that is itself sanitized, so defaulting it on in Debug hands a
    // consumer who forgot to forward `optimize` a link failure naming a
    // __ubsan symbol.
    sanitize_c: bool = false,
    // meshoptimizer's SIMD kernels are codegen-only: no type changes layout
    // with them, so this changes speed and nothing a consumer can observe.
    simd: bool = true,
};

/// What a project that depends on zmeshopt builds: the `zmeshopt` library,
/// the vendored meshoptimizer plus src/abi_shim.c, and the `zmeshopt`
/// module over it.
pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const options: Options = .{
        .shared = b.option(bool, "shared", "Build the C library as a shared object") orelse false,
        .sanitize_c = b.option(bool, "sanitize_c", "Compile the C++ with Zig's undefined-behaviour sanitizer") orelse false,
        .simd = b.option(bool, "simd", "Compile meshoptimizer's SIMD kernels (off = scalar fallbacks, upstream's MESHOPTIMIZER_NO_SIMD)") orelse true,
    };

    //=====================================================================
    // The C library: the vendored translation units, plus src/abi_shim.c,
    // the caller-shape forwarders this package owns (see abi_shim.h).
    //=====================================================================

    const lib = b.addLibrary(.{
        .name = "zmeshopt",
        .linkage = if (options.shared) .dynamic else .static,
        .root_module = b.createModule(.{ .target = target, .optimize = optimize, .link_libc = true }),
    });
    if (target.result.abi != .msvc) lib.root_module.link_libcpp = true;
    // The C++-only template wrappers in the header are dead weight in a
    // library whose whole surface is the extern "C" functions; upstream's
    // macro exists to drop them.
    lib.root_module.addCMacro("MESHOPTIMIZER_NO_WRAPPERS", "");
    if (!options.simd) lib.root_module.addCMacro("MESHOPTIMIZER_NO_SIMD", "");
    if (options.shared and target.result.os.tag == .windows) {
        // The header's MESHOPTIMIZER_API is upstream's export seam
        // (meshoptimizer.h:17-20); consumers link through the import
        // library's thunks. The shim's export macro rides the same switch.
        lib.root_module.addCMacro("MESHOPTIMIZER_API", "__declspec(dllexport)");
        lib.root_module.addCMacro("ZMESHOPT_SHIM_SHARED", "");
    }
    lib.root_module.addCSourceFiles(.{ .files = &meshopt_sources, .flags = cxxFlags(target) });
    // The forwarders' include of "meshoptimizer.h" resolves against the
    // vendored tree; the vendored TUs include it relatively.
    lib.root_module.addIncludePath(b.path("libs/meshoptimizer/src"));
    lib.root_module.addCSourceFile(.{ .file = b.path("src/abi_shim.c"), .flags = &.{"-std=c99"} });
    lib.root_module.sanitize_c = if (options.sanitize_c) .full else .off;
    // C consumers get the vendored header without reaching into the source
    // tree: linking the artifact puts it on the include path.
    lib.installHeader(b.path("libs/meshoptimizer/src/meshoptimizer.h"), "meshoptimizer.h");
    // Registered unconditionally: `std.Build.Dependency.artifact` scans the
    // dependency's install step, so an artifact not installed here is one
    // `dep.artifact("zmeshopt")` cannot find. A dependency's install step runs
    // only when something depends on it, so a consumer's prefix stays clean.
    b.installArtifact(lib);

    //=====================================================================
    // The Zig module. No include path: the wrapper hand-writes its externs
    // rather than translating the header, so nothing Zig-side compiles C.
    //=====================================================================

    const module = b.addModule("zmeshopt", .{
        .root_source_file = b.path("src/zmeshopt.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{.{ .name = "zmeshopt_options", .module = optionsModule(b, options) }},
    });
    module.linkLibrary(lib);
}

/// meshoptimizer throws nothing and uses no RTTI, so both are off where that
/// is reliable; under the MSVC ABI the Microsoft standard library headers
/// assume exceptions, so that ABI keeps the defaults.
fn cxxFlags(target: std.Build.ResolvedTarget) []const []const u8 {
    return if (target.result.abi == .msvc) &.{"-std=c++11"} else &.{ "-std=c++11", "-fno-exceptions", "-fno-rtti" };
}

/// How the C++ was built, plus the package version, as the `zmeshopt_options`
/// module: the wrapper re-exports it, so it can never disagree with the build,
/// and `version()` reports build.zig.zon's field rather than a literal.
fn optionsModule(b: *std.Build, options: Options) *std.Build.Module {
    const step = b.addOptions();
    step.addOption([]const u8, "version", @import("build.zig.zon").version);
    const info = @typeInfo(Options).@"struct";
    inline for (info.field_names, info.field_types) |name, T| step.addOption(T, name, @field(options, name));
    return step.createModule();
}

/// zmeshopt's development: its tests, examples and checks, under preflight's
/// gate. Run through bay. The package is reached as a dependency here, the way
/// a consumer reaches it, so the artifact, its installed header and the
/// module are the ones a consumer gets.
pub fn dev(b: *std.Build, tools: type) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const preflight = tools.preflight;
    const package = b.dependency("zmeshopt", .{ .target = target, .optimize = optimize });
    const p = package.builder;

    const test_step = b.step("test", "Run the zmeshopt tests");
    const check_step = b.step("check", "Compile the zmeshopt tests, examples and build configurations without running them");
    const filters: []const []const u8 = if (b.option([]const u8, "test-filter", "Select tests by name")) |filter| b.allocator.dupe([]const u8, &.{filter}) catch @panic("OOM") else &.{};

    //=====================================================================
    // Tests: against the C++ under Zig's undefined-behaviour sanitizer, as a
    // consumer builds it by default, and with the scalar kernels in place of
    // the SIMD ones. The suite's C++ is the dependency's artifact, so the
    // C++ a consumer links is the C++ tested.
    //=====================================================================

    const arms = [_]struct { name: []const u8, options: Options }{
        .{ .name = "zmeshopt-tests-ubsan", .options = .{ .sanitize_c = true } },
        .{ .name = "zmeshopt-tests", .options = .{} },
        .{ .name = "zmeshopt-tests-scalar", .options = .{ .sanitize_c = true, .simd = false } },
    };
    for (arms) |arm| {
        const tests = suite(b, p, target, optimize, arm.name, arm.options, filters);
        test_step.dependOn(&b.addRunArtifact(tests).step);
        check_step.dependOn(&tests.step);
    }

    // The C boundary on its own, with no Zig in the picture: plain C that
    // includes <meshoptimizer.h> through the artifact's installed header.
    const c_smoke = b.addExecutable(.{
        .name = "zmeshopt-c-smoke",
        .root_module = b.createModule(.{ .target = target, .optimize = optimize, .link_libc = true }),
    });
    c_smoke.root_module.addCSourceFile(.{ .file = p.path("tests/c_smoke.c"), .flags = &.{"-std=c99"} });
    c_smoke.root_module.linkLibrary(package.artifact("zmeshopt"));
    test_step.dependOn(&b.addRunArtifact(c_smoke).step);
    check_step.dependOn(&c_smoke.step);

    // The configuration no arm above links: the shared library, which is
    // what proves the export seam.
    const shared = b.dependency("zmeshopt", .{ .target = target, .optimize = optimize, .shared = true }).artifact("zmeshopt");
    test_step.dependOn(&shared.step);
    check_step.dependOn(&shared.step);

    //=====================================================================
    // Examples, built AND run against the module a consumer gets.
    // examples/usage.zig is also where README.md's Usage block comes from
    // (`bay docs -- usage`), so the snippet a reader copies is code the
    // tests execute.
    //=====================================================================

    const examples_step = b.step("examples", "Build and run the examples");
    for (example_sources) |source| {
        const example = b.addExecutable(.{
            .name = std.Io.Dir.path.stem(source),
            .root_module = b.createModule(.{
                .root_source_file = p.path(source),
                .target = target,
                .optimize = optimize,
                .imports = &.{.{ .name = "zmeshopt", .module = package.module("zmeshopt") }},
            }),
        });
        examples_step.dependOn(&b.addRunArtifact(example).step);
        check_step.dependOn(&example.step);
    }
    test_step.dependOn(examples_step);

    //=====================================================================
    // CI wiring
    //=====================================================================

    for (checks) |c| _ = preflight.addCheck(b, p, c.name, c.source);
    // README.md's numbers block, which the docs check regenerates through
    // this step (ci/preflight.json).
    const measurements = b.addExecutable(.{
        .name = "zmeshopt-measurements",
        .root_module = b.createModule(.{ .root_source_file = p.path("ci/measurements.zig"), .target = b.graph.host, .optimize = .debug }),
    });
    const measure = b.addRunArtifact(measurements);
    measure.setCwd(p.path("."));
    b.step("measurements", "Print README.md's numbers block, recomputed from the tree").dependOn(&measure.step);
    test_step.dependOn(&b.addRunArtifact(b.addTest(.{ .root_module = measurements.root_module })).step);

    // libs/meshoptimizer against upstream at the pinned commit, which the
    // manifest fetches as a dev dependency.
    const vendor = b.addExecutable(.{
        .name = "zmeshopt-vendor",
        .root_module = b.createModule(.{ .root_source_file = p.path("ci/vendor.zig"), .target = b.graph.host, .optimize = .debug }),
    });
    const verify = b.addRunArtifact(vendor);
    verify.addDirectoryArg2(p.path("libs/meshoptimizer"), .{});
    verify.addDirectoryArg2(b.dependency("meshoptimizer", .{}).path("."), .{});
    verify.addFileArg(p.path("build.zig.zon"));
    verify.addFileArg(p.path("UPSTREAM.md"));
    verify.addFileArg(p.path("build.zig"));
    verify.step.dependOn(&b.addRunArtifact(b.addTest(.{ .root_module = vendor.root_module })).step);
    b.step("check-vendor", "Prove libs/meshoptimizer is upstream at the pinned commit").dependOn(&verify.step);

    // The hardened tier runs the suite's properties with runtime safety on;
    // zmeshopt runs no threads of its own.
    preflight.addCi(b, p, .{
        .tests = test_step,
        .hardened = .{},
    });
    // The build a consumer gets: the module and the library, fetching nothing.
    preflight.addConsumerCheck(b, p, .{
        .package = "zmeshopt",
        .program = p.path("ci/consumer.zig"),
    });
}

/// The suite, against the package's library built with `options`.
fn suite(b: *std.Build, p: *std.Build, target: std.Build.ResolvedTarget, optimize: std.lang.Optimize, name: []const u8, options: Options, filters: []const []const u8) *std.Build.Step.Compile {
    const library = b.dependency("zmeshopt", .{
        .target = target,
        .optimize = optimize,
        .sanitize_c = options.sanitize_c,
        .simd = options.simd,
    }).artifact("zmeshopt");
    const tests = b.addTest(.{
        .name = name,
        .filters = filters,
        .root_module = b.createModule(.{
            .root_source_file = p.path("src/zmeshopt.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{.{ .name = "zmeshopt_options", .module = optionsModule(b, options) }},
        }),
    });
    tests.root_module.linkLibrary(library);
    // The canaries' C mirrors are compiled as the library is, so an arm
    // without the sanitizer has no call into its runtime. The sanitized C
    // calls into that runtime, which Zig bundles by itself only into a Debug
    // compilation.
    tests.root_module.sanitize_c = if (options.sanitize_c) .full else .off;
    tests.bundle_ubsan_rt = options.sanitize_c;
    // The ABI cross-check reads the vendored header translated as
    // `meshoptimizer_h`, through src/abi_shim.h, which includes it, so the
    // forwarders' prototypes come with it. On the test module alone, never
    // on the shipped one. No macro goes with it: MESHOPTIMIZER_NO_SIMD is
    // codegen-only and MESHOPTIMIZER_NO_WRAPPERS removes only C++ templates.
    const header = b.addTranslateC(.{ .root_source_file = p.path("src/abi_shim.h"), .target = target, .optimize = optimize });
    header.addIncludePath(p.path("libs/meshoptimizer/src"));
    tests.root_module.addImport("meshoptimizer_h", header.createModule());
    // The ABI canaries' C mirrors (src/testing/canary.zig), test-only.
    tests.root_module.addCSourceFile(.{ .file = p.path("tests/abi_canary.c"), .flags = &.{"-std=c99"} });
    return tests;
}

/// Every example, listed rather than globbed: a build graph that scans a
/// directory is not reproducible from the manifest alone.
const example_sources = [_][]const u8{
    "examples/usage.zig",
};

/// The repository checks: each is built, its tests run, then it runs over the
/// tree from the repository root. ci/preflight.json runs each as an extra check.
const checks = [_]struct { name: []const u8, source: []const u8 }{
    .{ .name = "check-comments", .source = "ci/comments.zig" },
    .{ .name = "check-coverage", .source = "ci/coverage.zig" },
    .{ .name = "check-ignored", .source = "ci/ignored.zig" },
    .{ .name = "check-numbers", .source = "ci/numbers.zig" },
};
