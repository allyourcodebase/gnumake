# `build.zig` for GNU's make program

Provides a package to build/run GNU's make program.

# Status

## Hermetic Cross Targets

These Cross Targets should only depend on components that Zig provides so should "build the same" on any system.

| Target              | Status                                     |
|---------------------|--------------------------------------------|
| x86_64-linux-musl   | Does not build                             |
| x86_64-windows-gnu  | Builds, 358 test failures in 78 categories |
| aarch64-macos       | Builds,  6 test failures in 3 categories |

## Non-Hermetic Cross Targets

The following "Cross Targets" depend on components provided by the host so your results will vary:

| Target              | Status                |
|---------------------|-----------------------|
| x86_64-windows-msvc | Does not build        |
| x86_64-linux-gnu    | *might build* ???     |

## Host Targets

Note that compling to your host target is likely to depend on components provided by the host
and therefore will generate different results  depending on the host system.  This
project has succesfully been built natively on at least one linux, windows, macos system
each with varying test results.
