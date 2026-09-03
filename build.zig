const std = @import("std");

/// Sources of the vendored meshoptimizer library — all 20 of upstream's
/// translation units.
///
/// This list is explicit rather than a directory glob: a glob would silently
/// start compiling whatever a future re-vendor drops in, and
/// `ci/verify-vendor.sh` checks every entry here still exists, so a re-vendor
/// that removes a translation unit is a build failure rather than a quietly
/// smaller library.
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
// archive — the linker takes one member and never looks at the other — so it
// survives every default build and only surfaces in the shared-library
// configuration, a long way from the edit that caused it.
comptime {
    @setEvalBranchQuota(100_000);
    for (meshopt_sources, 0..) |a, i| {
        for (meshopt_sources[i + 1 ..]) |b| {
            if (std.mem.eql(u8, a, b)) {
                @compileError("build.zig lists `" ++ a ++ "` more than once. " ++
                    "A duplicate source is a duplicate symbol, which a static " ++
                    "archive hides and a shared library refuses.");
            }
        }
    }
}

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const options = .{
        .shared = b.option(
            bool,
            "shared",
            "Build the C library as a shared object",
        ) orelse false,
        // Off by default, and deliberately NOT tied to `optimize`: Zig's C
        // sanitizer emits calls into a runtime linked only into a compilation
        // that is itself sanitized, so defaulting it on in Debug hands a
        // consumer who forgot to forward `optimize` a link failure naming a
        // __ubsan symbol. The suite turns it on explicitly instead.
        .sanitize_c = b.option(
            bool,
            "sanitize_c",
            "Compile the C++ with Zig's undefined-behaviour sanitizer",
        ) orelse false,
        // meshoptimizer's SIMD paths (SSE/AVX/NEON/WASM in the codecs and the
        // rasterizer) are codegen-only: no type changes layout with them, so
        // this option affects speed and nothing a consumer can observe.
        // Upstream compiles them in by default; so does this.
        .simd = b.option(
            bool,
            "simd",
            "Compile meshoptimizer's SIMD kernels (off = scalar fallbacks, " ++
                "upstream's MESHOPTIMIZER_NO_SIMD)",
        ) orelse true,
    };

    // Every behaviour-affecting option is mirrored into a Zig module so the
    // wrapper can never disagree with how the C++ was compiled; the version
    // rides along so a test can compare what the library REPORTS against
    // build.zig.zon rather than against a literal of its own.
    const options_step = b.addOptions();
    options_step.addOption([]const u8, "version", @import("build.zig.zon").version);
    inline for (std.meta.fields(@TypeOf(options))) |field| {
        options_step.addOption(field.type, field.name, @field(options, field.name));
    }
    const options_module = options_step.createModule();

    //=====================================================================
    // The C library: the vendored translation units, plus src/abi_shim.c —
    // the caller-shape forwarders this repo owns (see abi_shim.h).
    //=====================================================================

    const lib = b.addLibrary(.{
        .name = "zmeshopt",
        .linkage = if (options.shared) .dynamic else .static,
        .root_module = b.createModule(.{
            .target = target,
            .optimize = optimize,
        }),
    });

    lib.root_module.link_libc = true;
    if (target.result.abi != .msvc) lib.root_module.link_libcpp = true;

    // The C++-only template wrappers in the header are dead weight in a
    // library whose whole surface is the extern "C" functions; upstream's
    // macro exists to drop them.
    lib.root_module.addCMacro("MESHOPTIMIZER_NO_WRAPPERS", "");
    if (!options.simd) lib.root_module.addCMacro("MESHOPTIMIZER_NO_SIMD", "");
    if (options.shared and target.result.os.tag == .windows) {
        // The header's MESHOPTIMIZER_API is the export seam upstream provides
        // (meshoptimizer.h:17-20). Consumers do not need a dllimport
        // counterpart: they link through the import library's thunks. The
        // shim's own export macro rides the same switch.
        lib.root_module.addCMacro("MESHOPTIMIZER_API", "__declspec(dllexport)");
        lib.root_module.addCMacro("ZMESHOPT_SHIM_SHARED", "");
    }

    // meshoptimizer throws nothing and uses no RTTI, so both are disabled
    // where doing so is reliable; under the MSVC ABI the Microsoft standard
    // library headers assume exceptions, so that ABI keeps the defaults.
    const cxx_flags: []const []const u8 = if (target.result.abi == .msvc)
        &.{"-std=c++11"}
    else
        &.{ "-std=c++11", "-fno-exceptions", "-fno-rtti" };

    lib.root_module.addCSourceFiles(.{
        .files = &meshopt_sources,
        .flags = cxx_flags,
    });
    // The forwarders' include of "meshoptimizer.h" resolves against the
    // vendored tree; the vendored TUs include it relatively and need no path.
    lib.root_module.addIncludePath(b.path("libs/meshoptimizer/src"));
    lib.root_module.addCSourceFile(.{
        .file = b.path("src/abi_shim.c"),
        .flags = &.{"-std=c99"},
    });
    lib.root_module.sanitize_c = if (options.sanitize_c) .full else .off;

    // C consumers get the vendored header without reaching into the source
    // tree; tests/consumer proves an installed prefix resolves it.
    lib.installHeader(b.path("libs/meshoptimizer/src/meshoptimizer.h"), "meshoptimizer.h");

    //=====================================================================
    // The Zig module.
    //=====================================================================

    const module = b.addModule("zmeshopt", .{
        .root_source_file = b.path("src/zmeshopt.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "zmeshopt_options", .module = options_module },
        },
    });
    // No include path: the wrapper hand-writes its externs rather than
    // @cImport-ing the header, so nothing Zig-side compiles C.
    module.linkLibrary(lib);

    // Registered unconditionally: `std.Build.Dependency.artifact` scans the
    // dependency's install step, so an artifact not installed here is one
    // `dep.artifact("zmeshopt")` cannot find. This does not pollute a
    // consumer's prefix — a dependency's install step only runs when
    // something actually depends on it.
    b.installArtifact(lib);

    //=====================================================================
    // Tests.
    //=====================================================================

    const tests = b.addTest(.{
        .name = "zmeshopt-tests",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/zmeshopt.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "zmeshopt_options", .module = options_module },
            },
        }),
    });
    tests.root_module.linkLibrary(lib);
    // The ABI cross-check @cImports the vendored header. Wired here, on the
    // test module, and deliberately not on the shipped module above. No build
    // macros go with it: nothing in the header changes shape with a define —
    // MESHOPTIMIZER_NO_SIMD is codegen-only and MESHOPTIMIZER_NO_WRAPPERS
    // only removes C++-side inline templates translate-c never sees.
    tests.root_module.addIncludePath(b.path("libs/meshoptimizer/src"));
    // src/ so the same @cImport reaches abi_shim.h — the oracle holds
    // src/shim.zig's externs to the shim's prototypes the same way.
    tests.root_module.addIncludePath(b.path("src"));
    // The ABI canaries (see src/abi_canary_test.zig): test-only C mirrors of
    // the raw shapes Zig 0.16.0 was measured miscompiling and of the shim
    // shapes the bindings ship instead. Test module only — never in the
    // shipped library.
    tests.root_module.addCSourceFile(.{
        .file = b.path("tests/abi_canary.c"),
        .flags = &.{"-std=c99"},
    });

    const test_step = b.step("test", "Run zmeshopt tests");
    test_step.dependOn(&b.addRunArtifact(tests).step);

    // A C-only smoke test proves the installed header and library stand on
    // their own, independent of anything Zig-side.
    const c_smoke = b.addExecutable(.{
        .name = "zmeshopt-c-smoke",
        .root_module = b.createModule(.{
            .target = target,
            .optimize = optimize,
        }),
    });
    c_smoke.root_module.link_libc = true;
    c_smoke.root_module.addCSourceFile(.{
        .file = b.path("tests/c_smoke.c"),
        .flags = &.{"-std=c99"},
    });
    c_smoke.root_module.linkLibrary(lib);

    const c_test_step = b.step("test-c", "Run the C-level smoke test");
    c_test_step.dependOn(&b.addRunArtifact(c_smoke).step);
    test_step.dependOn(c_test_step);

    //=====================================================================
    // Examples
    //
    // Built AND run, against the module a consumer gets. An example that is
    // only compiled proves the names still resolve; running it is what
    // proves the pipeline still works. examples/usage.zig is also where
    // README.md's Usage block comes from — see ci/readme_usage.sh — so a
    // snippet a reader copies cannot drift from code CI executes.
    //=====================================================================

    const examples_step = b.step("examples", "Build and run the examples");
    for (example_sources) |source| {
        const example = b.addExecutable(.{
            .name = std.fs.path.stem(source),
            .root_module = b.createModule(.{
                .root_source_file = b.path(source),
                .target = target,
                .optimize = optimize,
                .imports = &.{.{ .name = "zmeshopt", .module = module }},
            }),
        });
        const run = b.addRunArtifact(example);
        run.step.dependOn(b.getInstallStep());
        run.setCwd(b.path("zig-out"));
        examples_step.dependOn(&run.step);
    }
    test_step.dependOn(examples_step);
}

/// Every example, listed rather than globbed: a build graph that scans a
/// directory is not reproducible from the manifest alone.
const example_sources = [_][]const u8{
    "examples/usage.zig",
};
