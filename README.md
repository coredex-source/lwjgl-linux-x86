# lwjgl-linux-x86

32-bit Linux (x86) natives for **LWJGL 3.4.1** (Minecraft 26.1.x and 26.2) and **LWJGL 3.4.3** (Minecraft 26.3). LWJGL
stopped publishing linux-x86 natives, so on a 32-bit JVM the game dies loading `liblwjgl.so`.

| LWJGL | Libraries |
|-------|-----------|
| 3.4.1 | lwjgl, lwjgl_opengl, lwjgl_stb, lwjgl_tinyfd, lwjgl_vma, GLFW, OpenAL Soft, FreeType (+ HarfBuzz), jemalloc, shaderc, SPIRV-Cross |
| 3.4.3 | lwjgl, lwjgl_opengl, lwjgl_stb, lwjgl_tinyfd, lwjgl_vma, SDL3, OpenAL Soft, FreeType (+ HarfBuzz), jemalloc, shaderc, SPIRV-Cross (no GLFW: Minecraft 26.3 uses SDL3) |


## Using them

Download the tarball for your CPU from Releases:

| Tarball                              | CPU                                                                   |
|--------------------------------------|-----------------------------------------------------------------------|
| `lwjgl-<version>-linux-x86.tar.gz`       | SSE2 (Pentium 4, Athlon 64 and newer)                             |
| `lwjgl-<version>-linux-x86-i686.tar.gz`  | i686 without SSE2 (Pentium Pro/II/III, Athlon/Athlon XP)          |
| `lwjgl-<version>-linux-x86-i586.tar.gz`  | i586, no CMOV (Pentium/MMX, K6, VIA C3, Vortex86, Geode, Quark)   |

Unpack it and add one JVM argument (the directory is `linux-x86`, `linux-x86-i686` or `linux-x86-i586`)

```
-Dorg.lwjgl.librarypath=/path/to/linux-x86
```

The target machine needs:
- glibc 2.36 or newer.
- libGL, libX11 with libXrandr/Xinerama/Xcursor/Xi/Xext.
- 3.4.1: X11 (or XWayland): GLFW is built without its Wayland backend. 3.4.3: X11 or Wayland (SDL3 loads them, and
  libdecor if present, at runtime).
- A 32-bit JVM can't use much more than 2 GB of heap: keep `-Xmx` at 2048M or less.

## Building

Needs git, curl, python3 and podman (or docker: `CONTAINER_ENGINE=docker`).

```sh
./fetch.sh
./build.sh
LWJGL_X86_FLAVOUR=i686 ./build.sh    # For i686/No SSE builds
LWJGL_X86_FLAVOUR=i586 ./build.sh    # For i586/No CMOV builds

LWJGL_VERSION=3.4.3 ./fetch.sh       # LWJGL 3.4.3
LWJGL_VERSION=3.4.3 ./build.sh
```

Note: The i586 build compiles GCC from source in `build-x86-i586/toolchain`, with an i586 runtime and no CET, and builds everything with that.

Output goes to `out` (3.4.1) and `out/3.4.3` plus `out/lwjgl-3.4.3-linux-x86*.tar.gz` (3.4.3). The patched core jar is
`out/lwjgl-3.4.1.jar` and `out/3.4.3/lwjgl-3.4.3.jar` (`./build.sh corejar` after the `lwjgl` step).

## Licenses

The natives are under their projects' licenses, copied into `out/licenses/` and the jar's
`META-INF/licenses/lwjgl-linux-x86/`: LWJGL (BSD-3; also VMA, MIT), GLFW or SDL3 (zlib), OpenAL Soft (**LGPL-2.0+**; this repo is its
corresponding source), FreeType (FTL), HarfBuzz (MIT), libpng, zlib, jemalloc (BSD-2), shaderc, glslang,
SPIRV-Tools, SPIRV-Cross (Apache-2.0 / BSD), libffi (MIT).
