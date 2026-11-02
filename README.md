# lwjgl-linux-x86

32-bit Linux (x86) natives for **LWJGL 3.4.1**, the version Minecraft 26.1.2 uses. LWJGL stopped publishing linux-x86
natives, so on a 32-bit JVM the game dies loading `liblwjgl.so`. 

## Using them

Download `lwjgl-3.4.1-linux-x86.tar.gz or lwjgl-3.4.1-linux-x86-i686.tar.gz depending on if your CPU supports SSE or not.` from Releases, unpack it, and add one JVM argument

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
```

Output goes to `out`

## Licenses

The natives are under their projects' licenses, copied into `out/licenses/` and the jar's
`META-INF/licenses/lwjgl-linux-x86/`: LWJGL (BSD-3), GLFW (zlib), OpenAL Soft (**LGPL-2.0+**; this repo is its
corresponding source), FreeType (FTL), HarfBuzz (MIT), libpng, zlib, jemalloc (BSD-2), shaderc, glslang,
SPIRV-Tools, SPIRV-Cross (Apache-2.0 / BSD), libffi (MIT).
