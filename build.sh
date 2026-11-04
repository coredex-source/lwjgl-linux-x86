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
        -e LWJGL_X86_FLAVOUR="${LWJGL_X86_FLAVOUR:-sse2}" -e LWJGL_VERSION="${LWJGL_VERSION:-3.4.1}" "$IMAGE" \
        /work/build.sh "$@"
fi

NO_SSE='%[xy]?mm[0-9]|(^| )(ldmxcsr|stmxcsr|[lms]fence|prefetch[a-z0-9]*|movnti|clflush|f?emms|fisttp[a-z]*)( |$)'
NO_P6='(^| )(cmov[a-z]*|fcmov[a-z]*|fu?comip?|nop[lw]|endbr32)( |$)'
NO_ISA_OK='__x86_rd(rand|seed)'
FLAVOUR=${LWJGL_X86_FLAVOUR:-sse2}
case "$FLAVOUR" in
    sse2) SUFFIX="";      NO_ISA="";              SIMD_FLAGS="-msse2 -mfpmath=sse" ;;
    i686) SUFFIX="-i686"; NO_ISA="$NO_SSE";       SIMD_FLAGS="-march=i686 -mtune=generic -mno-sse -mno-sse2 -mfpmath=387" ;;
    i586) SUFFIX="-i586"; NO_ISA="$NO_SSE|$NO_P6"; SIMD_FLAGS="-march=i586 -mtune=generic -mno-sse -mno-sse2 -mfpmath=387" ;;
    *) echo "unknown LWJGL_X86_FLAVOUR '$FLAVOUR' (sse2, i686, i586)" >&2; exit 1 ;;
esac
VERSION=${LWJGL_VERSION:-3.4.1}
TARBALLS=/work/src
LIBFFI=3.5.0
[[ $VERSION == 3.4.1 ]] || LIBFFI=3.8.0
case "$VERSION" in
    3.4.1) SRC=/work/src; OUT=/work/out/linux-x86$SUFFIX; STAGE=/work/out/jar$SUFFIX; BUILD=/work/build-x86$SUFFIX ;;
    3.4.3) SRC=/work/src-$VERSION; OUT=/work/out/$VERSION/linux-x86$SUFFIX; STAGE=/work/out/$VERSION/jar$SUFFIX
           BUILD=/work/build-$VERSION-x86$SUFFIX ;;
    *) echo "unknown LWJGL_VERSION '$VERSION' (3.4.1, 3.4.3)" >&2; exit 1 ;;
esac
[[ -d "$SRC/lwjgl3" ]] || { echo "${SRC#/work/}/ is missing: run LWJGL_VERSION=$VERSION ./fetch.sh first" >&2; exit 1; }
mkdir -p "$OUT" "$BUILD" "$HOME"
JOBS=$(nproc)

GCC_VER=12.2.0
TOOLCHAIN=/work/build-x86$SUFFIX/toolchain
[[ $FLAVOUR == i586 && $SRC != "$TARBALLS" ]] && for t in "$TARBALLS"/{gcc,gmp,mpfr,mpc}-*.tar.*; do ln -sf "$t" "$SRC/"; done
[[ $FLAVOUR == i586 ]] && export PATH="$TOOLCHAIN/bin:$PATH"

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

check_lib() {
    if readelf -d "$1" | grep -q TEXTREL; then
        echo "!!! $(basename "$1") has text relocations" >&2; return 1
    fi
    [[ -n "$NO_ISA" ]] || return 0
    local bad
    bad=$(objdump -d --no-show-raw-insn "$1" | awk -F'\t' -v bad="$NO_ISA" -v ok="$NO_ISA_OK" '
        /^[0-9a-f]+ <.*>:$/ && !/ <\.L/ { fn = $0; sub(/^[0-9a-f]+ /, "", fn); skip = fn ~ ok; next }
        !skip && /^ *[0-9a-f]+:\t/ && match($2, bad) { m = substr($2, RSTART, RLENGTH); gsub(/ /, "", m); n[m " in " fn]++ }
        END { for (k in n) print n[k], k }' | c++filt | sort -rn)
    [[ -z "$bad" ]] && return 0
    echo "!!! $(basename "$1") has instructions $FLAVOUR CPUs don't, $(wc -l <<< "$bad") (instruction, function) pairs:" >&2
    head -20 <<< "$bad" >&2
    return 1
}

install_lib() {
    check_lib "$1"
    strip "$1" -o "$OUT/$2"
    mkdir -p "$STAGE/linux/x86/org/lwjgl/$3"
    cp "$OUT/$2" "$STAGE/linux/x86/org/lwjgl/$3/$2"
    echo ">>> $2: $(file -b "$OUT/$2" | cut -d, -f1-2)"
}

step_toolchain() {
    local stamp="gcc-$GCC_VER $(declare -f step_toolchain | sha256sum | cut -c1-16)"
    if [[ "$(cat "$TOOLCHAIN/.stamp" 2>/dev/null)" == "$stamp" ]]; then
        echo ">>> gcc $GCC_VER (i586) up to date"; return
    fi
    local src="$BUILD/gcc-src" obj="$BUILD/gcc-obj" p
    find "$BUILD" -mindepth 1 -maxdepth 1 ! -name toolchain.cmake ! -name cross.meson -exec rm -rf {} +
    mkdir -p "$src" "$obj"
    tar -xJf "$SRC/gcc-$GCC_VER.tar.xz" -C "$src" --strip-components=1
    for p in gmp-6.2.1.tar.bz2 mpfr-4.1.0.tar.bz2 mpc-1.2.1.tar.gz; do
        mkdir "$src/${p%%-*}" && tar -xf "$SRC/$p" -C "$src/${p%%-*}" --strip-components=1
    done
    (cd "$obj" && CC=/usr/bin/gcc CXX=/usr/bin/g++ CFLAGS=-O2 CXXFLAGS=-O2 "$src/configure" --prefix="$TOOLCHAIN" \
        --build=x86_64-linux-gnu --host=x86_64-linux-gnu --target=x86_64-linux-gnu --enable-languages=c,c++ \
        --enable-multilib --with-multilib-list=m32,m64 --enable-multiarch --with-arch-32=i586 --with-tune=generic \
        --disable-cet --disable-bootstrap --disable-nls --disable-werror --disable-libsanitizer --disable-libgomp \
        --disable-libitm --disable-libssp --disable-libcc1 --disable-libstdcxx-pch --without-isl \
        --enable-linker-build-id --with-linker-hash-style=gnu \
        CFLAGS_FOR_TARGET="-O2 -fPIC" CXXFLAGS_FOR_TARGET="-O2 -fPIC" \
        && make -j "$JOBS" && make install-strip)
    rm -rf "$src" "$obj"
    echo "$stamp" > "$TOOLCHAIN/.stamp"
    echo ">>> gcc $GCC_VER (i586) in $TOOLCHAIN"
}

step_glfw() {
    "${CMAKE[@]}" -S "$SRC/glfw" -B "$BUILD/glfw" -DGLFW_BUILD_WAYLAND=OFF -DGLFW_LIBRARY_TYPE=SHARED \
        -DGLFW_BUILD_EXAMPLES=OFF -DGLFW_BUILD_TESTS=OFF -DGLFW_BUILD_DOCS=OFF
    cmake --build "$BUILD/glfw" -j "$JOBS"
    install_lib "$BUILD/glfw/src/libglfw.so" libglfw.so glfw
}

step_sdl() {
    "${CMAKE[@]}" -S "$SRC/sdl" -B "$BUILD/sdl" -DSDL_TEST_LIBRARY=OFF -DSDL_TESTS=OFF -DSDL_EXAMPLES=OFF \
        -DSDL_INSTALL=OFF -DSDL_SHARED=ON -DSDL_STATIC=OFF \
        -DCMAKE_C_FLAGS="$ARCH_FLAGS $NOFORTIFY -std=c99" \
        $([[ $FLAVOUR == sse2 ]] || echo -DSDL_ASSEMBLY=OFF)
    cmake --build "$BUILD/sdl" -j "$JOBS"
    install_lib "$(readlink -f "$BUILD/sdl/libSDL3.so")" libSDL3.so sdl
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
    tar -xzf "$TARBALLS/libffi-$LIBFFI.tar.gz" -C "$BUILD/libffi" --strip-components=1
    (cd "$BUILD/libffi" && CC="gcc $ARCH_FLAGS" CFLAGS="-O3 $NOFORTIFY" ./configure --disable-shared \
        --with-pic --disable-docs --host=i686-linux-gnu --build=x86_64-linux-gnu && make -j "$JOBS")
    cp "$BUILD"/libffi/i686-*-linux-gnu/.libs/libffi.a "$BUILD/libffi.a"
    echo ">>> libffi.a"
}

step_lwjgl() {
    [[ -f "$BUILD/libffi.a" ]] || step_libffi
    export LWJGL_BUILD_ARCH=x86
    local off="" vma=vma modules=("" opengl stb tinyfd)
    [[ $VERSION == 3.4.3 ]] && vma="" && modules+=(vma)
    for b in assimp fmod harfbuzz hwloc ktx llvm lmdb lz4 meshoptimizer msdfgen nanovg nfd nuklear odbc opencl \
             opengles openxr opus par remotery renderdoc rpmalloc sdl spng tinyexr $vma xxhash yoga zstd; do
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
    for m in "${modules[@]}"; do
        n=lwjgl${m:+_$m}
        install_lib "bin/libs/native/linux/x86/org/lwjgl/${m:+$m/}lib$n.so" "lib$n.so" "$m"
    done
}

step_package() {
    local lic=/work/out/licenses
    [[ $VERSION == 3.4.1 ]] || lic=/work/out/$VERSION/licenses
    rm -rf "$lic" && mkdir -p "$lic"
    cp "$SRC/lwjgl3/LICENSE.md"                         "$lic/lwjgl.md"
    if [[ $VERSION == 3.4.1 ]]; then
        cp "$SRC/glfw/LICENSE.md"                       "$lic/glfw.md"
    else
        cp "$SRC/sdl/LICENSE.txt"                       "$lic/sdl.txt"
    fi
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
    tar -xzOf "$TARBALLS/libffi-$LIBFFI.tar.gz" "libffi-$LIBFFI/LICENSE" > "$lic/libffi.txt"
    if [[ $VERSION != 3.4.1 ]]; then
        sed -n '/^\/\/ Copyright/,/^\/\/ THE SOFTWARE/p' "$SRC/lwjgl3/modules/lwjgl/vma/src/main/c/vk_mem_alloc.h" \
            | sed 's#^// \{0,1\}##' > "$lic/vma.txt"
    fi
    cp /work/README.md "$lic/SOURCES.md"
    rm -rf "$STAGE/META-INF" && mkdir -p "$STAGE/META-INF/licenses/lwjgl-linux-x86" && cp "$lic"/* "$STAGE/META-INF/licenses/lwjgl-linux-x86/"
    local dir=/work/out
    [[ $VERSION == 3.4.1 ]] || dir=/work/out/$VERSION
    rm -f "$dir/lwjgl-natives-linux-x86$SUFFIX.jar"
    (cd "$STAGE" && jar --create --file "$dir/lwjgl-natives-linux-x86$SUFFIX.jar" --no-manifest linux META-INF)
    tar -czf "/work/out/lwjgl-$VERSION-linux-x86$SUFFIX.tar.gz" -C "$dir" "linux-x86$SUFFIX" licenses
    echo ">>> ${dir#/work/}/lwjgl-natives-linux-x86$SUFFIX.jar, out/lwjgl-$VERSION-linux-x86$SUFFIX.tar.gz"
}

steps=("$@")
if [[ ${#steps[@]} -eq 0 ]]; then
    case "$VERSION" in
        3.4.1) steps=(glfw openal freetype jemalloc spvc shaderc lwjgl package) ;;
        *)     steps=(sdl openal freetype jemalloc spvc shaderc lwjgl package) ;;
    esac
fi
[[ $FLAVOUR == i586 && ${steps[0]} != toolchain ]] && steps=(toolchain "${steps[@]}")
for s in "${steps[@]}"; do
    echo "=================== $s"
    "step_$s"
done
