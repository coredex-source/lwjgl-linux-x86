#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd "$(dirname "$0")" && pwd)
VERSION=${LWJGL_VERSION:-3.4.1}
case "$VERSION" in
    3.4.1) SRC="$ROOT/src"; PATCHES="$ROOT/patches" ;;
    3.4.3) SRC="$ROOT/src-$VERSION"; PATCHES="$ROOT/patches/$VERSION" ;;
    *) echo "unknown LWJGL_VERSION '$VERSION' (3.4.1, 3.4.3)" >&2; exit 1 ;;
esac
TARBALLS="$ROOT/src"
[[ "${1:-}" == "--clean" ]] && rm -rf "$SRC"
mkdir -p "$SRC" "$TARBALLS"

export GIT_COMMITTER_NAME="lwjgl-linux-x86" GIT_COMMITTER_EMAIL="lwjgl-linux-x86@localhost"

fetch() {
    local dir=$1 repo=$2 commit=$3 patches=${4:-}
    local stamp="$dir/.lwjgl-x86-stamp"
    local want="$commit $(cat "$patches"/*.patch 2>/dev/null | sha256sum | cut -c1-16)"
    if [[ -f "$stamp" && "$(cat "$stamp")" == "$want" ]]; then
        echo "= $(basename "$dir") up to date"
        return
    fi
    rm -rf "$dir"
    mkdir -p "$dir"
    git -C "$dir" init -q
    git -C "$dir" remote add origin "$repo"
    git -C "$dir" fetch -q --depth 1 origin "$commit"
    git -C "$dir" -c advice.detachedHead=false checkout -q FETCH_HEAD
    if [[ -n "$patches" ]]; then
        git -C "$dir" checkout -q -b "lwjgl-$VERSION-x86"
        git -C "$dir" am -q --keep-cr "$patches"/*.patch
    fi
    echo "$want" > "$stamp"
    echo "+ $(basename "$dir") $(git -C "$dir" rev-parse --short "$commit")${patches:+ + $(ls "$patches" | wc -l) patch(es)}"
}

if [[ $VERSION == 3.4.1 ]]; then
fetch "$SRC/lwjgl3"      https://github.com/LWJGL/lwjgl3.git          b800ccffab14396fc529ddb6c931b7c5c5226763 "$PATCHES/lwjgl3"
fetch "$SRC/glfw"        https://github.com/LWJGL-CI/glfw.git         9352d8fe93cd443be18157abe81f16500549aec0 "$PATCHES/glfw"
fetch "$SRC/openal-soft" https://github.com/LWJGL-CI/openal-soft.git  c41d64c6a35f6174bf4a27010aeac52a8d3bb2c6 "$PATCHES/openal-soft"
fetch "$SRC/freetype"    https://github.com/LWJGL-CI/freetype.git     526ec5c47b9ebccc4754c85ac0c0cdf7c85a5e9b "$PATCHES/freetype"
fetch "$SRC/jemalloc"    https://github.com/LWJGL-CI/jemalloc.git     1972241cd204c60fb5b66f23c48a117879636161
fetch "$SRC/shaderc"     https://github.com/LWJGL-CI/shaderc.git      301b4ede53d59b68bf55f95bb26412d9233c8187 "$PATCHES/shaderc"
fetch "$SRC/SPIRV-Cross" https://github.com/LWJGL-CI/SPIRV-Cross.git  a0fba56c34a6700f1724bf9b751da5b488a3775c
else
fetch "$SRC/lwjgl3"      https://github.com/LWJGL/lwjgl3.git          30fac9b95f99cda97312232be25ba55297bf9951 # (kotlinc fix upstream)
fetch "$SRC/sdl"         https://github.com/LWJGL-CI/SDL.git          147a8ee32dbf9ac02f3794964490687b6bbda1bc "$PATCHES/sdl"
fetch "$SRC/openal-soft" https://github.com/LWJGL-CI/openal-soft.git  7f9c6de1162b1d4604b9a2f8bcd6c53021566221 "$PATCHES/openal-soft"
fetch "$SRC/freetype"    https://github.com/LWJGL-CI/freetype.git     0a0221a1347e2f1e07c395263540026e9a0aa7c7 "$PATCHES/freetype"
fetch "$SRC/jemalloc"    https://github.com/LWJGL-CI/jemalloc.git     81034ce1f1373e37dc865038e1bc8eeecf559ce8
fetch "$SRC/shaderc"     https://github.com/LWJGL-CI/shaderc.git      2c8cae778eec0283b44acbe7ed1a386865d78799 "$PATCHES/shaderc"
fetch "$SRC/SPIRV-Cross" https://github.com/LWJGL-CI/SPIRV-Cross.git  6c09849fe88c48eaed08413aa022aaa136a3a057
fi

fetch "$SRC/freetype/subprojects/harfbuzz" https://github.com/harfbuzz/harfbuzz.git \
      36cb489cb02ce4b92099669ba9f9bea348eff93f "$PATCHES/harfbuzz"
nested="$SRC/freetype/subprojects/freetype"
if [[ ! -f "$nested/.lwjgl-x86-stamp" || "$(cat "$nested/.lwjgl-x86-stamp")" != "$(git -C "$SRC/freetype" rev-parse HEAD)" ]]; then
    rm -rf "$nested" && mkdir -p "$nested"
    git -C "$SRC/freetype" archive HEAD | tar -x -C "$nested"
    git -C "$SRC/freetype" rev-parse HEAD > "$nested/.lwjgl-x86-stamp"
    echo "+ freetype (HarfBuzz's copy)"
fi

if [[ ! -f "$SRC/shaderc/.deps-synced" ]]; then
    (cd "$SRC/shaderc" && python3 utils/git-sync-deps) && touch "$SRC/shaderc/.deps-synced"
    echo "+ shaderc dependencies"
fi

tarball() {
    local url=$1 sum=$2 file="$TARBALLS/$(basename "$1")"
    [[ -f "$file" ]] && return
    curl -fsSL --retry 3 --retry-all-errors -o "$file.part" "$url"
    echo "$sum  $file.part" | "sha$(( ${#sum} * 4 ))sum" -c - >/dev/null
    mv "$file.part" "$file"
    echo "+ $(basename "$file")"
}

tarball https://github.com/libffi/libffi/releases/download/v3.5.0/libffi-3.5.0.tar.gz \
        8c72678628a5dd8782f08ad421d5a441e42c1c5c1b33e0bc211cbfcf1f3b3978
[[ $VERSION == 3.4.1 ]] || tarball https://github.com/libffi/libffi/releases/download/v3.8.0/libffi-3.8.0.tar.gz \
        7da3e2d9a171eb0a038f592ecad3ff2bb2550f3496d87b3b29ad0cf4430c0db4

GNU=https://gcc.gnu.org/pub/gcc
tarball $GNU/releases/gcc-12.2.0/gcc-12.2.0.tar.xz \
        e9e857bd81bf7a370307d6848c81b2f5403db8c7b5207f54bce3f3faac3bde63445684092c2bc1a2427cddb6f7746496d9fbbef05fbbd77f2810b2998f1f9173
tarball $GNU/infrastructure/gmp-6.2.1.tar.bz2 \
        8904334a3bcc5c896ececabc75cda9dec642e401fb5397c4992c4fabea5e962c9ce8bd44e8e4233c34e55c8010cc28db0545f5f750cbdbb5f00af538dc763be9
tarball $GNU/infrastructure/mpfr-4.1.0.tar.bz2 \
        410208ee0d48474c1c10d3d4a59decd2dfa187064183b09358ec4c4666e34d74383128436b404123b831e585d81a9176b24c7ced9d913967c5fce35d4040a0b4
tarball $GNU/infrastructure/mpc-1.2.1.tar.gz \
        3279f813ab37f47fdcc800e4ac5f306417d07f539593ca715876e43e04896e1d5bceccfb288ef2908a3f24b760747d0dbd0392a24b9b341bc3e12082e5c836ee
echo "sources ready in ${SRC#$ROOT/}/ (LWJGL $VERSION)"
