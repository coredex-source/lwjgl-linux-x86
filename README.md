# lwjgl-linux-x86

32-bit Linux (x86) natives for **LWJGL 3.4.1**, the version Minecraft 26.1.2 uses. LWJGL stopped publishing linux-x86
natives, so on a 32-bit JVM the game dies loading `liblwjgl.so`. 

## Using them

Download the tarball for your CPU from Releases:

| Tarball                              | CPU                                                                   |
|--------------------------------------|-----------------------------------------------------------------------|
| `lwjgl-3.4.1-linux-x86.tar.gz`       | SSE2 (Pentium 4, Athlon 64 and newer)                                 |
| `lwjgl-3.4.1-linux-x86-i686.tar.gz`  | i686 without SSE2 (Pentium Pro/II/III, Athlon/Athlon XP)              |
| `lwjgl-3.4.1-linux-x86-i586.tar.gz`  | i586, no CMOV (Pentium/MMX, K6, VIA C3, Vortex86, Geode, Quark)       |

Unpack it and add one JVM argument (the directory is `linux-x86`, `linux-x86-i686` or `linux-x86-i586`)

```
-Dorg.lwjgl.librarypath=/path/to/linux-x86
```

The target machine needs:
- glibc 2.36 or newer.
- libGL, libX11 with libXrandr/Xinerama/Xcursor/Xi/Xext.
- X11 (or XWayland): GLFW is built without its Wayland backend.
- A 32-bit JVM can't use much more than 2 GB of heap: keep `-Xmx` at 2048M or less.

## Building

Needs git, curl, python3 and podman (or docker: `CONTAINER_ENGINE=docker`).

```sh
./fetch.sh
./build.sh
LWJGL_X86_FLAVOUR=i686 ./build.sh    # For i686/No SSE builds
LWJGL_X86_FLAVOUR=i586 ./build.sh    # For i586/No CMOV builds
```

Note: The i586 build compiles GCC from source in `build-x86-i586/toolchain`, with an i586 runtime and no CET, and builds everything with that.

Output goes to `out`

## Licenses

The natives are under their projects' licenses, copied into `out/licenses/` and the jar's
`META-INF/licenses/lwjgl-linux-x86/`: LWJGL (BSD-3), GLFW (zlib), OpenAL Soft (**LGPL-2.0+**; this repo is its
corresponding source), FreeType (FTL), HarfBuzz (MIT), libpng, zlib, jemalloc (BSD-2), shaderc, glslang,
SPIRV-Tools, SPIRV-Cross (Apache-2.0 / BSD), libffi (MIT).
