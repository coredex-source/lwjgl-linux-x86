#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd "$(dirname "$0")" && pwd)
IMAGE=lwjgl-x86-build

if [[ -z "${LWJGL_X86_CONTAINER:-}" ]]; then
    ENGINE=${CONTAINER_ENGINE:-podman}
    if ! $ENGINE image inspect "$IMAGE" >/dev/null 2>&1; then
        $ENGINE build -t "$IMAGE" -f "$ROOT/Containerfile" "$ROOT"
    fi
    user=()
    [[ "$ENGINE" == docker ]] && user=(--user "$(id -u):$(id -g)") # rootless podman already maps root to us
    exec $ENGINE run --rm "${user[@]}" -v "$ROOT:/work:Z" -w /work -e HOME=/work/.home \
        -e LWJGL_X86_FLAVOUR="${LWJGL_X86_FLAVOUR:-sse2}" "$IMAGE" /work/build.sh "$@"
fi

FLAVOUR=${LWJGL_X86_FLAVOUR:-sse2}
case "$FLAVOUR" in
    sse2) SUFFIX=""; SIMD_FLAGS="-msse2 -mfpmath=sse" ;;
    i686) SUFFIX="-i686"; SIMD_FLAGS="-march=i686 -mtune=generic -mno-sse -mno-sse2 -mfpmath=387" ;;
    *) echo "unknown LWJGL_X86_FLAVOUR '$FLAVOUR' (sse2, i686)" >&2; exit 1 ;;
esac
SRC=/work/src
OUT=/work/out/linux-x86$SUFFIX
STAGE=/work/out/jar$SUFFIX
BUILD=/work/build-x86$SUFFIX
[[ -d "$SRC/lwjgl3" ]] || { echo "src/ is missing: run ./fetch.sh first" >&2; exit 1; }
mkdir -p "$OUT" "$BUILD" "$HOME"
JOBS=$(nproc)

ARCH_FLAGS="-m32 $SIMD_FLAGS"
NOFORTIFY="-U_FORTIFY_SOURCE -D_FORTIFY_SOURCE=0"
HIDE="libstdc++.a:libgcc.a:libgcc_eh.a:libsupc++.a"
CXX_LINK="-static-libstdc++ -static-libgcc -Wl,--exclude-libs,$HIDE"
export PKG_CONFIG_LIBDIR=/usr/lib/i386-linux-gnu/pkgconfig:/usr/share/pkgconfig

cat > "$BUILD/toolchain.cmake" <<EOF
set(CMAKE_SYSTEM_NAME Linux)
set(CMAKE_SYSTEM_PROCESSOR i686)
set(CMAKE_C_COMPILER gcc)
set(CMAKE_CXX_COMPILER g++)
set(CMAKE_C_FLAGS_INIT "$ARCH_FLAGS $NOFORTIFY")
set(CMAKE_CXX_FLAGS_INIT "$ARCH_FLAGS $NOFORTIFY")
set(CMAKE_SHARED_LINKER_FLAGS_INIT "-m32 $CXX_LINK")
set(CMAKE_MODULE_LINKER_FLAGS_INIT "-m32 $CXX_LINK")
set(CMAKE_EXE_LINKER_FLAGS_INIT "-m32")
set(CMAKE_LIBRARY_ARCHITECTURE i386-linux-gnu)
EOF

cat > "$BUILD/cross.meson" <<EOF
[binaries]
c = ['gcc', '-m32']
cpp = ['g++', '-m32']
ar = 'ar'
strip = 'strip'
pkg-config = 'pkg-config'

[built-in options]
c_args = [$(printf "'%s', " $SIMD_FLAGS)'-U_FORTIFY_SOURCE', '-D_FORTIFY_SOURCE=0']
cpp_args = [$(printf "'%s', " $SIMD_FLAGS)'-U_FORTIFY_SOURCE', '-D_FORTIFY_SOURCE=0']
c_link_args = ['-static-libgcc']
cpp_link_args = ['-static-libstdc++', '-static-libgcc', '-Wl,--exclude-libs,$HIDE']

[properties]
pkg_config_libdir = '$PKG_CONFIG_LIBDIR'

[host_machine]
system = 'linux'
cpu_family = 'x86'
cpu = 'i686'
endian = 'little'
EOF

CMAKE=(cmake -G Ninja -DCMAKE_TOOLCHAIN_FILE="$BUILD/toolchain.cmake" -DCMAKE_BUILD_TYPE=Release)

install_lib() {
    strip "$1" -o "$OUT/$2"
    mkdir -p "$STAGE/linux/x86/org/lwjgl/$3"
    cp "$OUT/$2" "$STAGE/linux/x86/org/lwjgl/$3/$2"
    echo ">>> $2: $(file -b "$OUT/$2" | cut -d, -f1-2)"
}

step_glfw() {
    "${CMAKE[@]}" -S "$SRC/glfw" -B "$BUILD/glfw" -DGLFW_BUILD_WAYLAND=OFF -DGLFW_LIBRARY_TYPE=SHARED \
        -DGLFW_BUILD_EXAMPLES=OFF -DGLFW_BUILD_TESTS=OFF -DGLFW_BUILD_DOCS=OFF
    cmake --build "$BUILD/glfw" -j "$JOBS"
    install_lib "$BUILD/glfw/src/libglfw.so" libglfw.so glfw
}

step_openal() {
    "${CMAKE[@]}" -S "$SRC/openal-soft" -B "$BUILD/openal" -DALSOFT_REQUIRE_RTKIT=ON -DALSOFT_REQUIRE_ALSA=ON \
        -DALSOFT_REQUIRE_OSS=ON -DALSOFT_REQUIRE_PORTAUDIO=ON -DALSOFT_REQUIRE_PULSEAUDIO=ON -DALSOFT_REQUIRE_JACK=ON \
        -DALSOFT_REQUIRE_PIPEWIRE=ON -DALSOFT_EMBED_HRTF_DATA=YES -DALSOFT_UTILS=OFF -DALSOFT_EXAMPLES=OFF \
        -DALSOFT_TESTS=OFF -DALSOFT_INSTALL=OFF \
        $([[ $FLAVOUR == sse2 ]] && echo -DALSOFT_ENABLE_SSE2_CODEGEN=ON || echo -DALSOFT_ENABLE_SSE2_CODEGEN=OFF \
            -DALSOFT_CPUEXT_SSE=OFF -DALSOFT_CPUEXT_SSE2=OFF -DALSOFT_CPUEXT_SSE3=OFF -DALSOFT_CPUEXT_SSE4_1=OFF)
    cmake --build "$BUILD/openal" -j "$JOBS"
    install_lib "$BUILD/openal/libopenal.so" libopenal.so openal
}

step_freetype() {
    rm -rf "$BUILD/freetype"
    (cd "$SRC/freetype" && meson setup "$BUILD/freetype" --cross-file "$BUILD/cross.meson" --wrap-mode=default \
        --force-fallback-for=harfbuzz,libpng,zlib -Dbrotli=disabled -Dbzip2=disabled -Dharfbuzz=enabled -Dpng=enabled \
        -Dzlib=system -Dtests=disabled -Dbuildtype=release -Dfreetype2:zlib=disabled -Dfreetype2:png=disabled \
        -Dharfbuzz:experimental_api=true -Dharfbuzz:subset=disabled -Dharfbuzz:raster=disabled \
        -Dharfbuzz:vector=disabled -Db_lto=true -Db_ndebug=true -Derror_strings=true)
    meson compile -C "$BUILD/freetype"
    install_lib "$BUILD/freetype/libfreetype.so" libfreetype.so freetype
}

step_jemalloc() {
    rm -rf "$BUILD/jemalloc" && cp -a "$SRC/jemalloc" "$BUILD/jemalloc"
    (cd "$BUILD/jemalloc" && CC="gcc $ARCH_FLAGS" CFLAGS="$NOFORTIFY" ./autogen.sh --with-jemalloc-prefix=je_ \
        --disable-stats --disable-fill --disable-cxx --enable-doc=no --disable-initial-exec-tls \
        --host=i686-linux-gnu --build=x86_64-linux-gnu && make -j "$JOBS" build_lib_shared)
    install_lib "$BUILD/jemalloc/lib/libjemalloc.so" libjemalloc.so jemalloc
}

step_spvc() {
    "${CMAKE[@]}" -S "$SRC/SPIRV-Cross" -B "$BUILD/spvc" -DSPIRV_CROSS_STATIC=OFF -DSPIRV_CROSS_SHARED=ON \
        -DSPIRV_CROSS_CLI=OFF -DSPIRV_CROSS_ENABLE_TESTS=OFF -DSPIRV_CROSS_SKIP_INSTALL=ON -DSPIRV_CROSS_WERROR=ON \
        -DSPIRV_CROSS_FORCE_PIC=ON
    cmake --build "$BUILD/spvc" -j "$JOBS"
    install_lib "$BUILD/spvc/libspirv-cross-c-shared.so" libspirv-cross.so spvc
}

step_shaderc() {
    "${CMAKE[@]}" -S "$SRC/shaderc" -B "$BUILD/shaderc" -DSHADERC_SKIP_INSTALL=ON -DSHADERC_SKIP_TESTS=ON \
        -DSHADERC_SKIP_EXAMPLES=ON
    cmake --build "$BUILD/shaderc" -j "$JOBS" --target shaderc_shared
    install_lib "$BUILD/shaderc/libshaderc/libshaderc_shared.so" libshaderc.so shaderc
}

step_libffi() {
    rm -rf "$BUILD/libffi" && mkdir "$BUILD/libffi"
    tar -xzf "$SRC/libffi-3.5.0.tar.gz" -C "$BUILD/libffi" --strip-components=1
    (cd "$BUILD/libffi" && CC="gcc $ARCH_FLAGS" CFLAGS="-O3 $NOFORTIFY" ./configure --disable-shared \
        --with-pic --disable-docs --host=i686-linux-gnu --build=x86_64-linux-gnu && make -j "$JOBS")
    cp "$BUILD"/libffi/i686-*-linux-gnu/.libs/libffi.a "$BUILD/libffi.a"
    echo ">>> libffi.a"
}

step_lwjgl() {
    [[ -f "$BUILD/libffi.a" ]] || step_libffi
    export LWJGL_BUILD_ARCH=x86
    local off=""
    for b in assimp fmod harfbuzz hwloc ktx llvm lmdb lz4 meshoptimizer msdfgen nanovg nfd nuklear odbc opencl \
             opengles openxr opus par remotery renderdoc rpmalloc sdl spng tinyexr vma xxhash yoga zstd; do
        off+=" -Dbinding.$b=false"
    done
    cd "$SRC/lwjgl3"
    mkdir -p bin/libs/native/linux/x86/org/lwjgl
    cp "$BUILD/libffi.a" bin/libs/native/linux/x86/org/lwjgl/libffi.a
    rm -f bin/classes/templates/touch.txt bin/classes/generator/generated-touch.txt
    ant compile-templates generate
    rm -rf bin/linux/x86
    find bin/libs/native/linux/x86/org/lwjgl -name '*.so' -delete 2>/dev/null || true
    if [[ $FLAVOUR != sse2 ]]; then
        sed -i "s/-m32 -mfpmath=sse -msse -msse2/-m32 $SIMD_FLAGS/" config/linux/build.xml
    fi
    ant -Dbuild.offline=true $off compile-native || { git checkout -- config/linux/build.xml; return 1; }
    git checkout -- config/linux/build.xml
    local m n
    for m in "" opengl stb tinyfd; do
        n=lwjgl${m:+_$m}
        install_lib "bin/libs/native/linux/x86/org/lwjgl/${m:+$m/}lib$n.so" "lib$n.so" "$m"
    done
}

step_package() {
    local lic=/work/out/licenses
    rm -rf "$lic" && mkdir -p "$lic"
    cp "$SRC/lwjgl3/LICENSE.md"                         "$lic/lwjgl.md"
    cp "$SRC/glfw/LICENSE.md"                           "$lic/glfw.md"
    cp "$SRC/openal-soft/COPYING"                       "$lic/openal-soft-LGPL-2.0.txt"
    cp "$SRC/freetype/LICENSE.TXT"                      "$lic/freetype.txt"
    cp "$SRC/freetype/docs/FTL.TXT"                     "$lic/freetype-FTL.txt"
    cp "$SRC/freetype/subprojects/harfbuzz/COPYING"     "$lic/harfbuzz.txt"
    cp "$SRC"/freetype/subprojects/libpng-*/LICENSE     "$lic/libpng.txt"
    cp "$SRC"/freetype/subprojects/zlib-*/LICENSE       "$lic/zlib.txt"
    cp "$SRC/jemalloc/COPYING"                          "$lic/jemalloc.txt"
    cp "$SRC/shaderc/LICENSE"                           "$lic/shaderc.txt"
    cp "$SRC/shaderc/third_party/glslang/LICENSE.txt"   "$lic/glslang.txt"
    cp "$SRC/shaderc/third_party/spirv-tools/LICENSE"   "$lic/spirv-tools.txt"
    cp "$SRC/SPIRV-Cross/LICENSE"                       "$lic/spirv-cross.txt"
    tar -xzOf "$SRC/libffi-3.5.0.tar.gz" libffi-3.5.0/LICENSE > "$lic/libffi.txt"
    cp /work/README.md "$lic/SOURCES.md"
    rm -rf "$STAGE/META-INF" && mkdir -p "$STAGE/META-INF/licenses/lwjgl-linux-x86" && cp "$lic"/* "$STAGE/META-INF/licenses/lwjgl-linux-x86/"
    rm -f /work/out/lwjgl-natives-linux-x86$SUFFIX.jar
    (cd "$STAGE" && jar --create --file /work/out/lwjgl-natives-linux-x86$SUFFIX.jar --no-manifest linux META-INF)
    tar -czf /work/out/lwjgl-3.4.1-linux-x86$SUFFIX.tar.gz -C /work/out "linux-x86$SUFFIX" licenses
    echo ">>> out/lwjgl-natives-linux-x86$SUFFIX.jar, out/lwjgl-3.4.1-linux-x86$SUFFIX.tar.gz"
}

steps=("$@")
if [[ ${#steps[@]} -eq 0 ]]; then
    steps=(glfw openal freetype jemalloc spvc shaderc lwjgl package)
    [[ $FLAVOUR == i686 ]] && steps=(glfw openal freetype jemalloc lwjgl package)
fi
for s in "${steps[@]}"; do
    echo "=================== $s"
    "step_$s"
done
