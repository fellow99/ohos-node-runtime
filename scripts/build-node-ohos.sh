#!/usr/bin/env bash
# build-node-ohos.sh — Build a REAL shared libnode.so for OpenHarmony on a CI
# runner (runs directly on Linux, no Docker).
#
# Toolchain: LLVM-19 tarball from OpenHarmony daily builds, which contains
#   llvm-linux-x86_64.tar.gz     (clang + lld, with *-unknown-linux-ohos wrappers)
#   ohos-sysroot.tar.gz         (OHOS bionic sysroot)
#   libcxx-ndk-linux-aarch64.tar.gz (libc++_shared.so for arm64)
#
# No OHOS SDK / Java / code-signing is needed: a native lib packaged inside a
# HAR/HAP does not require .codesign (verified on device).
#
# Usage:
#   ./scripts/build-node-ohos.sh <node_version> <arch> <llvm_dir> <node_src_dir> <out_dir> [jobs]
#     node_version  e.g. "24.2.0" (no leading v)
#     arch          arm64 | x64
#     llvm_dir      directory that contains bin/aarch64-unknown-linux-ohos-clang
#                   (i.e. <extract>/llvm)
#     node_src_dir  path to extracted node-v<version> source
#     out_dir       where to write libnode-<arch>.so (+ libc++_shared.so)
#     jobs          make -j (default: nproc)
set -euo pipefail

NODE_VERSION="${1:?node_version required}"
ARCH_IN="${2:?arch required}"
LLVM_DIR="${3:?llvm_dir required}"
NODE_SRC="${4:?node_src_dir required}"
OUT_DIR="${5:?out_dir required}"
MAKE_JOBS="${6:-$(nproc 2>/dev/null || echo 2)}"

case "${ARCH_IN}" in
  arm64|aarch64) ARCH="arm64"; CLANG_TRIPLE="aarch64-unknown-linux-ohos"; LIBCXX_TARBALL="libcxx-ndk-linux-aarch64.tar.gz" ;;
  x64|x86_64|amd64) ARCH="x64"; CLANG_TRIPLE="x86_64-unknown-linux-ohos"; LIBCXX_TARBALL="libcxx-ndk-linux-x86_64.tar.gz" ;;
  *) echo "Unsupported ARCH: ${ARCH_IN}"; exit 1 ;;
esac

VERSION="v${NODE_VERSION}"
INSTALL_PREFIX="${OUT_DIR}/install-${ARCH}"

mkdir -p "${OUT_DIR}"

# --- Verify toolchain -----------------------------------------------------------
CLANG="${LLVM_DIR}/bin/${CLANG_TRIPLE}-clang"
if [ ! -x "${CLANG}" ]; then
    echo "ERROR: clang wrapper not found: ${CLANG}"
    echo "  LLVM_DIR contents:"; ls -la "${LLVM_DIR}/bin" 2>/dev/null | head -20 || true
    exit 1
fi
echo "==> Clang: ${CLANG}"
echo "==> Node source: ${NODE_SRC}"
[ -f "${NODE_SRC}/configure" ] || { echo "ERROR: ${NODE_SRC}/configure missing"; exit 1; }

# --- Environment ----------------------------------------------------------------
export CC="${CLANG} -fno-emulated-tls"
export CXX="${LLVM_DIR}/bin/${CLANG_TRIPLE}-clang++ -fno-emulated-tls"
export CC_host="gcc"
export CXX_host="g++"
export CFLAGS="${CFLAGS:-} -DNDEBUG"
export CXXFLAGS="${CXXFLAGS:-} -DNDEBUG"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# --- Patches --------------------------------------------------------------------
cd "${NODE_SRC}"

# Patch 0001: gyp make generator — treat openharmony like linux/android for
# shared-lib link rules. Only needed on early v24.x / v22.x; harmless to skip
# elsewhere (patch would fail to apply).
NEED_0001="v24.2.0 v24.3.0 v24.4.0 v24.4.1 v24.5.0 v24.6.0"
if echo " ${NEED_0001} " | grep -q " ${VERSION} "; then
    if [ -f "${SCRIPT_DIR}/0001-fix-argument-list-too-long.patch" ]; then
        echo "==> Applying 0001-fix-argument-list-too-long.patch"
        patch -p1 < "${SCRIPT_DIR}/0001-fix-argument-list-too-long.patch" || echo "    (apply returned non-zero, continuing)"
    fi
fi

# Patch: maglev-assembler.h — move set_allow_* declarations out of #ifdef DEBUG
MAGLEV_H="${NODE_SRC}/deps/v8/src/maglev/maglev-assembler.h"
if [ -f "${MAGLEV_H}" ]; then
    echo "==> Patching maglev-assembler.h (set_allow_* DEBUG guard)"
    awk '
    /^#ifdef DEBUG$/ {
        save = $0
        getline next_line
        if (next_line ~ /bool allow_allocate/ || next_line ~ /bool allow_call_/) {
            print next_line
            next
        } else {
            print save
            print next_line
            next
        }
    }
    /^#endif  \/\/ DEBUG$/ {
        if (prev ~ /allow_deferred_call/) { next } else { print; next }
    }
    { prev = $0; print }
    ' "${MAGLEV_H}" > "${MAGLEV_H}.tmp" && mv "${MAGLEV_H}.tmp" "${MAGLEV_H}"
    grep -q 'bool allow_allocate_ = false;' "${MAGLEV_H}" || \
        sed -i 's/  bool allow_call_ = false;/  bool allow_allocate_ = false;\n  bool allow_call_ = false;/' "${MAGLEV_H}"
fi

# Some early v24/v22 builds error on implicit function declarations under -Werror
NEED_NOERROR="v24.2.0 v24.3.0 v24.4.0 v24.4.1 v24.5.0 v24.6.0 v24.7.0 v24.8.0 v22.17.0 v22.17.1 v22.18.0 v22.19.0"
if echo " ${NEED_NOERROR} " | grep -q " ${VERSION} "; then
    export CC="${CC} -Wno-error=implicit-function-declaration"
    export CXX="${CXX} -Wno-error=implicit-function-declaration"
fi

# --- Configure ------------------------------------------------------------------
echo "==> Configuring Node.js ${VERSION} for OpenHarmony ${ARCH} ..."
CONFIGURE_ARGS="--dest-cpu=${ARCH} \
  --dest-os=openharmony \
  --cross-compiling \
  --openssl-no-asm \
  --shared \
  --prefix=${INSTALL_PREFIX}"
if ./configure --help 2>&1 | grep -q -- "--v8-disable-temporal-support"; then
    CONFIGURE_ARGS="${CONFIGURE_ARGS} --v8-disable-temporal-support"
fi
echo "    ${CONFIGURE_ARGS}"
./configure ${CONFIGURE_ARGS}

# --- Build + install ------------------------------------------------------------
echo "==> Building (make -j${MAKE_JOBS}) ..."
make -j"${MAKE_JOBS}"
echo "==> Installing ..."
make install

# --- Locate libnode.so ----------------------------------------------------------
LIBNODE=""
for d in "${INSTALL_PREFIX}/lib" "${NODE_SRC}/out/Release/lib.target" "${NODE_SRC}/out/Release"; do
    for f in "${d}"/libnode.so*; do
        [ -e "${f}" ] || continue
        LIBNODE="${f}"; break 2
    done
done
[ -n "${LIBNODE}" ] || { echo "ERROR: libnode.so not found"; exit 1; }
echo "==> libnode.so: ${LIBNODE} ($(du -h "${LIBNODE}" | cut -f1))"

# --- Strip ----------------------------------------------------------------------
echo "==> Stripping ..."
"${LLVM_DIR}/bin/llvm-strip" "${LIBNODE}" || echo "    (strip failed, keeping unstripped)"

# --- Output ---------------------------------------------------------------------
cp "${LIBNODE}" "${OUT_DIR}/libnode-${ARCH}.so"
echo "==> Output: ${OUT_DIR}/libnode-${ARCH}.so ($(du -h "${OUT_DIR}/libnode-${ARCH}.so" | cut -f1))"
file "${OUT_DIR}/libnode-${ARCH}.so"
