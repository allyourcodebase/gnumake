const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const make_dep = b.dependency("make", .{});
    const make_root = make_dep.path(".");

    const make_exe= blk: {
        const exe = b.addExecutable(.{
            .name = "make",
            .target = target,
            .optimize = optimize,
        });

        exe.addIncludePath(b.path("inc"));
        exe.addIncludePath(make_dep.path("src"));
        if (target.result.os.tag == .windows) {
            exe.addIncludePath(make_dep.path("src/w32/include"));
        }
        const config_header = b.addConfigHeader(.{
            .style = .{ .autoconf = make_dep.path("src/config.h.in") },
            .include_path = "config.h",
        }, make_config);
        switch (target.result.os.tag) {
            .windows => config_header.addValues(.{
                .PATH_SEPARATOR_CHAR = .@"';'",
                .HAVE_DOS_PATHS = 1,
                .HAVE_UNISTD_H = null,
                .HAVE_FCNTL_H = null,
                .HAVE_STPCPY = 0,
            }),
            else => config_header.addValues(.{
                .PATH_SEPARATOR_CHAR = .@"':'",
                .HAVE_DOS_PATHS = null,
                .HAVE_UNISTD_H = 1,
                .HAVE_FCNTL_H = 1,
                .HAVE_STPCPY = 1,
            }),
        }
        if (target_has_sys_siglist(target)) {
            config_header.addValues(.{
                .HAVE_DECL_SYS_SIGLIST = 1,
            });
            exe.defineCMacro("SYS_SIGLIST_DECLARED", "1");
        } else {
            config_header.addValues(.{
                .HAVE_DECL_SYS_SIGLIST = 0,
            });
        }

        if (target.result.os.tag == .windows) {
            exe.defineCMacro("_POSIX_", "1");
            exe.defineCMacro("putenv", "_putenv");
            exe.defineCMacro("getpid", "_getpid");
            exe.defineCMacro("fdopen", "_fdopen");
            exe.defineCMacro("environ", "(*__p__environ())");
        } else {
            // !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
            exe.defineCMacro("LOCALEDIR", "\".\"");
            // !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
            exe.defineCMacro("LIBDIR", "\"lib\"");
        }
        if (target.result.isGnuLibC()) {
            // TODO: only do this if we are compiling against gnu
            //exe.defineCMacro("__USE_GNU", "1");
            exe.defineCMacro("_GNU_SOURCE", "1");
        }
        const write_files = b.addWriteFiles();
        _ = write_files.addCopyFile(b.path("mkcustom.h"), "src/mkcustom.h");
        if (target.result.os.tag == .windows) {
            _ = write_files.addCopyFile(make_dep.path("src/config.h.W32"), "src/config.h");
        } else {
            _ = write_files.addCopyFile(config_header.getOutput(), "src/config.h");
        }

        exe.addIncludePath(write_files.getDirectory().path(b, "src"));

        exe.addCSourceFiles(.{
            .root = make_root,
            .files = switch (target.result.os.tag) {
                .windows => &make_files_windows,
                else => &make_files_generic,
            },
            .flags = &.{
                "-std=gnu99",
                "-Wno-format-security",
                "-Wno-string-compare",
                "-Werror=implicit-function-declaration",
            },
        });
        switch (target.result.os.tag) {
            .macos => {
                // ????????????????????????????????????????????????????????????????????????????????
                //exe.linkFramework("Foundation");
            },
            else => {},
        }
        exe.linkLibC();
        linkGlob(b, target, optimize, make_dep, exe);

        b.installArtifact(exe);
        break :blk exe;
    };

    {
        const run = b.addRunArtifact(make_exe);
        if (b.args) |args| {
            run.addArgs(args);
        }
        b.step("run", "run the make executable").dependOn(&run.step);
    }

    {
        const run_test = b.addSystemCommand(&.{"perl"});
        run_test.addArg("run_make_tests.pl");
        run_test.addArg("-make_path");
        run_test.addArtifactArg(make_exe);
        run_test.setCwd(make_dep.path("tests"));
        b.step("test", "").dependOn(&run_test.step);
    }
}

fn target_has_sys_siglist(t: std.Build.ResolvedTarget) bool {
    if (t.result.isDarwin()) return true;
    if (t.result.isGnuLibC()) {
        const vr = t.result.os.getVersionRange();
        // newer glibc does not allow linking with sys_siglist
        // https://lists.gnu.org/archive/html/info-gnu/2020-08/msg00002.html
        if (vr == .linux and vr.linux.glibc.major >= 2 and vr.linux.glibc.minor >= 32)
            return false;
        return true;
    }
    return false;
}

fn linkGlob(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    make_dep: *std.Build.Dependency,
    make_exe: *std.Build.Step.Compile
) void {
    if (target.result.os.tag != .windows)
        return;

    const lib = b.addStaticLibrary(.{
        .name = "glob",
        .target = target,
        .optimize = optimize,
    });
    const config_header = b.addConfigHeader(.{
        .style = .{ .autoconf = make_dep.path("lib/glob.in.h") },
        .include_path = "glob.h",
    }, .{});
    lib.addConfigHeader(config_header);
    lib.installConfigHeader(config_header);

    const fnmatch_header = b.addConfigHeader(.{
        .style = .{ .autoconf = make_dep.path("lib/fnmatch.in.h") },
        .include_path = "fnmatch.h",
        }, .{
	.FNM_PATHNAME = null,
	.FNM_NOESCAPE = null,
	.FNM_PERIOD = null,
    });
    lib.addConfigHeader(fnmatch_header);
    make_exe.addConfigHeader(fnmatch_header);

    const write_files = b.addWriteFiles();
    _ = write_files.addCopyFile(make_dep.path("src/config.h.W32"), "src/config.h");
    lib.defineCMacro("HAVE_CONFIG_H", "1");
    lib.addIncludePath(make_dep.path("src"));
    lib.addIncludePath(make_dep.path("lib"));
    lib.addIncludePath(write_files.getDirectory().path(b, "src"));

    lib.addCSourceFiles(.{
        .root = make_dep.path("."),
        .files = &.{
            "lib/fnmatch.c",
            "lib/glob.c",
        },
    });
    lib.linkLibC();

    make_exe.linkLibrary(lib);
}

const make_files_common = [_][]const u8{
    "src/ar.c", "src/arscan.c", "src/commands.c",
    "src/default.c", "src/dir.c", "src/expand.c",
    "src/file.c", "src/function.c", "src/getopt.c",
    "src/getopt1.c", "src/guile.c",
    "src/hash.c", "src/implicit.c", "src/job.c",
    "src/load.c", "src/loadapi.c", "src/main.c", "src/misc.c",
    "src/output.c", "src/read.c",
    "src/remake.c", "src/rule.c", "src/shuffle.c",
    "src/signame.c", "src/strcache.c", "src/variable.c",
    "src/version.c", "src/vpath.c",
    // ????????????????????????????????????????????????????????????????????????????????
    "src/remote-stub.c",
};
const make_files_generic = make_files_common ++ [_][]const u8 {
    "src/posixos.c",
};
const make_files_windows = make_files_common ++ [_][]const u8 {
    "src/w32/pathstuff.c", "src/w32/w32os.c", "src/w32/compat/dirent.c",
    "src/w32/compat/posixfcn.c",
    "src/w32/subproc/misc.c",
    "src/w32/subproc/sub_proc.c", "src/w32/subproc/w32err.c",
    "lib/getloadavg.c",
};

const make_config = .{
    .__i386__ = null,
    .__x86_64_x32__ = null,
    .__x86_64__ = null,
    .__alpha__ = null,
    .__arm__ = null,
    .__armhf__ = null,
    .__arm64_ilp32__ = null,
    .__arm64__ = null,
    .__hppa__ = null,
    .__hppa64__ = null,
    .__ia64_ilp32__ = null,
    .__ia64__ = null,
    .__loongarch64__ = null,
    .__m68k__ = null,
    .__mips__ = null,
    .__mipsn32__ = null,
    .__mips64__ = null,
    .__powerpc__ = null,
    .__powerpc64__ = null,
    .__powerpc64_elfv2__ = null,
    .__riscv32__ = null,
    .__riscv64__ = null,
    .__riscv32_ilp32__ = null,
    .__riscv32_ilp32f__ = null,
    .__riscv32_ilp32d__ = null,
    .__riscv64_ilp32__ = null,
    .__riscv64_ilp32f__ = null,
    .__riscv64_ilp32d__ = null,
    .__riscv64_lp64__ = null,
    .__riscv64_lp64f__ = null,
    .__riscv64_lp64d__ = null,
    .__s390__ = null,
    .__s390x__ = null,
    .__sh__ = null,
    .__sparc__ = null,
    .__sparc64__ = null,
    .AC_APPLE_UNIVERSAL_BUILD = null,
    .CLOSEDIR_VOID = null,
    .C_ALLOCA = null,
    .DGUX = null,
    .ENABLE_NLS = null,
    // ????????????????????????????????????????????????????????????????????????????????
    //.FILE_TIMESTAMP_HI_RES = 1,
    .FILE_TIMESTAMP_HI_RES = 0,
    .GNULIB_TEST_GETLOADAVG = null,
    .HAVE_ALLOCA = null,
    .HAVE_ALLOCA_H = null,
    .HAVE_ATEXIT = null,
    .HAVE_CASE_INSENSITIVE_FS = null,
    .HAVE_CFLOCALECOPYCURRENT = null,
    .HAVE_CFPREFERENCESCOPYAPPVALUE = null,
    .HAVE_CLOCK_GETTIME = null,
    .HAVE_C_BOOL = 1,
    .HAVE_DCGETTEXT = null,
    .HAVE_DECL_BSD_SIGNAL = null,
    .HAVE_DECL_DLERROR = null,
    .HAVE_DECL_DLOPEN = null,
    .HAVE_DECL_DLSYM = null,
    .HAVE_DECL_GETLOADAVG = null,
    .HAVE_DECL__SYS_SIGLIST = 0,
    .HAVE_DECL___SYS_SIGLIST = 0,
    .HAVE_DIRENT_H = 1,
    .HAVE_DUP = null,
    .HAVE_DUP2 = null,
    .HAVE_FDOPEN = 1,
    .HAVE_FORK = null,
    .HAVE_GETCWD = null,
    .HAVE_GETGROUPS = null,
    .HAVE_GETHOSTBYNAME = null,
    .HAVE_GETHOSTNAME = null,
    .HAVE_GETRLIMIT = null,
    .HAVE_GETTEXT = null,
    .HAVE_GETTIMEOFDAY = null,
    .HAVE_GUILE = null,
    .HAVE_ICONV = null,
    .HAVE_INTMAX_T = null,
    .HAVE_INTTYPES_H = 1,
    .HAVE_ISATTY = null,
    .HAVE_LIBDGC = null,
    .HAVE_LIBKSTAT = null,
    .HAVE_LIBPERFSTAT = null,
    .HAVE_LIMITS_H = 1,
    .HAVE_LOCALE_H = 1,
    .HAVE_LONG_LONG_INT = null,
    .HAVE_LSTAT = null,
    .HAVE_MACH_MACH_H = null,
    .HAVE_MEMORY_H = 1,
    .HAVE_MEMPCPY = 1,
    .HAVE_MEMRCHR = null,
    .HAVE_MINIX_CONFIG_H = null,
    .HAVE_MKFIFO = null,
    .HAVE_MKSTEMP = 1,
    .HAVE_MKTEMP = null,
    .HAVE_NDIR_H = null,
    .HAVE_NLIST_H = null,
    .HAVE_PIPE = null,
    .HAVE_POSIX_SPAWN = null,
    .HAVE_POSIX_SPAWNATTR_SETSIGMASK = null,
    .HAVE_PSELECT = null,
    .HAVE_PSTAT_GETDYNAMIC = null,
    .HAVE_READLINK = null,
    .HAVE_REALPATH = null,
    .HAVE_SA_RESTART = 1,
    .HAVE_SETEGID = null,
    .HAVE_SETEUID = null,
    .HAVE_SETLINEBUF = null,
    .HAVE_SETREGID = null,
    .HAVE_SETREUID = null,
    .HAVE_SETRLIMIT = null,
    .HAVE_SETVBUF = null,
    .HAVE_SIGACTION = null,
    .HAVE_SIGSETMASK = null,
    .HAVE_SIG_ATOMIC_T = null,
    .HAVE_SOCKET = null,
    .HAVE_SPAWN_H = null,
    .HAVE_STDBOOL_H = 1,
    .HAVE_STDINT_H = 1,
    .HAVE_STDIO_H = 1,
    .HAVE_STDLIB_H = 1,
    .HAVE_STRCASECMP = null,
    .HAVE_STRCMPI = null,
    .HAVE_STRCOLL = null,
    .HAVE_STRDUP = null,
    .HAVE_STRERROR = null,
    .HAVE_STRICMP = null,
    .HAVE_STRINGS_H = null,
    .HAVE_STRING_H = 1,
    .HAVE_STRNCASECMP = null,
    .HAVE_STRNCMPI = null,
    .HAVE_STRNDUP = null,
    .HAVE_STRNICMP = null,
    .HAVE_STRSIGNAL = 1,
    // ????????????????????????????????????????????????????????????????????????????????
    .HAVE_STRTOLL = 1,
    .HAVE_STRUCT_DIRENT_D_TYPE = null,
    .HAVE_STRUCT_NLIST_N_UN_N_NAME = null,
    .HAVE_SYS_DIR_H = null,
    .HAVE_SYS_FILE_H = null,
    .HAVE_SYS_LOADAVG_H = null,
    .HAVE_SYS_NDIR_H = null,
    .HAVE_SYS_PARAM_H = null,
    .HAVE_SYS_RESOURCE_H = null,
    .HAVE_SYS_SELECT_H = null,
    .HAVE_SYS_STAT_H = null,
    .HAVE_SYS_TIMEB_H = null,
    .HAVE_SYS_TIME_H = 1,
    .HAVE_SYS_TYPES_H = 1,
    .HAVE_SYS_WAIT_H = 1,
    .HAVE_TTYNAME = null,
    .HAVE_UINTMAX_T = null,
    .HAVE_UMASK = 1,
    .HAVE_UNION_WAIT = null,
    .HAVE_UNSIGNED_LONG_LONG_INT = null,
    .HAVE_VFORK = null,
    .HAVE_VFORK_H = null,
    .HAVE_WAIT3 = null,
    .HAVE_WAITPID = null,
    .HAVE_WCHAR_H = 1,
    .HAVE_WORKING_FORK = null,
    .HAVE_WORKING_VFORK = null,
    .MAKE_CXX = null,
    .MAKE_HOST = null,
    .MAKE_JOBSERVER = null,
    .MAKE_LOAD = null,
    .MAKE_SYMLINKS = null,
    .MK_CONFIGURE = null,
    .N_NAME_POINTER = null,
    .PACKAGE = "make",
    .PACKAGE_BUGREPORT = "bug-make@gnu.org",
    .PACKAGE_NAME = "GNU Make",
    .PACKAGE_STRING = "GNU Make 4.4.1",
    .PACKAGE_TARNAME = "make",
    .PACKAGE_URL = "https://www.gnu.org/software/make/",
    .PACKAGE_VERSION = "4.4.1",
    // ????????????????????????????????????????????????????????????????????????????????
    .SCCS_GET = "get",
    .SCCS_GET_MINUS_G = 1,
    .STACK_DIRECTION = null,
    .STAT_MACROS_BROKEN = null,
    .STDC_HEADERS = 1,
    .ST_MTIM_NSEC = null,
    .SVR4 = null,
    .UMAX = null,
    .UMAX4_3 = null,
    .USE_POSIX_SPAWN = null,
    ._ALL_SOURCE = null,
    ._DARWIN_C_SOURCE = null,
    .__EXTENSIONS__ = null,
    ._GNU_SOURCE = null,
    ._HPUX_ALT_XOPEN_SOCKET_API = null,
    ._MINIX = null,
    ._NETBSD_SOURCE = null,
    ._OPENBSD_SOURCE = null,
    ._POSIX_SOURCE = null,
    ._POSIX_1_SOURCE = null,
    ._POSIX_PTHREAD_SEMANTICS = null,
    .__STDC_WANT_IEC_60559_ATTRIBS_EXT__ = null,
    .__STDC_WANT_IEC_60559_BFP_EXT__ = null,
    .__STDC_WANT_IEC_60559_DFP_EXT__ = null,
    .__STDC_WANT_IEC_60559_EXT__ = null,
    .__STDC_WANT_IEC_60559_FUNCS_EXT__ = null,
    .__STDC_WANT_IEC_60559_TYPES_EXT__ = null,
    .__STDC_WANT_LIB_EXT2__ = null,
    .__STDC_WANT_MATH_SPEC_FUNCS__ = null,
    ._TANDEM_SOURCE = null,
    ._XOPEN_SOURCE = null,
    .VERSION = null,
    .WINDOWS32 = null,
    .WITH_DMALLOC = null,
    .WORDS_BIGENDIAN = null,
    ._FILE_OFFSET_BITS = null,
    ._ISOC11_SOURCE = null,
    ._LARGE_FILES = null,
    ._TIME_BITS = null,
    .__MINGW_USE_VC2005_COMPAT = null,
    .@"const" = .@"const",
    .eaccess = null ,
    .gid_t = null,
    .off_t = null,
    .pid_t = null,
    .sig_atomic_t = null,
    .size_t = null,
    .ssize_t = null,
    .uid_t = null,
    //.intmax_t = .@"long long",
    //.uintmax_t = .@"unsigned long long",
    .intmax_t = null,
    .uintmax_t = null,
    .vfork = null,
};
