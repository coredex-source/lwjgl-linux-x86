#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd "$(dirname "$0")" && pwd)
SRC="$ROOT/src"
[[ "${1:-}" == "--clean" ]] && rm -rf "$SRC"
mkdir -p "$SRC"

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
        git -C "$dir" checkout -q -b lwjgl-3.4.1-x86
        git -C "$dir" am -q --keep-cr "$patches"/*.patch
    fi
    echo "$want" > "$stamp"
    echo "+ $(basename "$dir") $(git -C "$dir" rev-parse --short "$commit")${patches:+ + $(ls "$patches" | wc -l) patch(es)}"
}

fetch "$SRC/lwjgl3"      https://github.com/LWJGL/lwjgl3.git          b800ccffab14396fc529ddb6c931b7c5c5226763 "$ROOT/patches/lwjgl3"
fetch "$SRC/glfw"        https://github.com/LWJGL-CI/glfw.git         9352d8fe93cd443be18157abe81f16500549aec0 "$ROOT/patches/glfw"
fetch "$SRC/openal-soft" https://github.com/LWJGL-CI/openal-soft.git  c41d64c6a35f6174bf4a27010aeac52a8d3bb2c6 "$ROOT/patches/openal-soft"
fetch "$SRC/freetype"    https://github.com/LWJGL-CI/freetype.git     526ec5c47b9ebccc4754c85ac0c0cdf7c85a5e9b "$ROOT/patches/freetype"
fetch "$SRC/jemalloc"    https://github.com/LWJGL-CI/jemalloc.git     1972241cd204c60fb5b66f23c48a117879636161
fetch "$SRC/shaderc"     https://github.com/LWJGL-CI/shaderc.git      301b4ede53d59b68bf55f95bb26412d9233c8187 "$ROOT/patches/shaderc"
fetch "$SRC/SPIRV-Cross" https://github.com/LWJGL-CI/SPIRV-Cross.git  a0fba56c34a6700f1724bf9b751da5b488a3775c

fetch "$SRC/freetype/subprojects/harfbuzz" https://github.com/harfbuzz/harfbuzz.git \
      36cb489cb02ce4b92099669ba9f9bea348eff93f "$ROOT/patches/harfbuzz"
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

ffi="$SRC/libffi-3.5.0.tar.gz"
if [[ ! -f "$ffi" ]]; then
    curl -fsSL -o "$ffi.part" https://github.com/libffi/libffi/releases/download/v3.5.0/libffi-3.5.0.tar.gz
    echo "8c72678628a5dd8782f08ad421d5a441e42c1c5c1b33e0bc211cbfcf1f3b3978  $ffi.part" | sha256sum -c - >/dev/null
    mv "$ffi.part" "$ffi"
    echo "+ libffi 3.5.0"
fi
echo "sources ready in src/"
