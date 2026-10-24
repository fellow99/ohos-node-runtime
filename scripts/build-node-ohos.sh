#!/usr/bin/env bash
# build-node-ohos.sh — Build a REAL shared libnode.so for OpenHarmony on GitHub Actions.
#
# This script runs DIRECTLY on the runner (no Docker). It:
#   1. Downloads OHOS SDK + LLVM-19 (cached via actions/cache)
#   2. Downloads Node.js source tarball
#   3. Applies patches (argument-list-too-long, maglev-assembler.h)
#   4. Configures + builds with --shared --cross-compiling
#   5. Strips + self-signs the output
#
# Usage (called by the workflow):
#   ./scripts/build-node-ohos.sh <node_version> <arch> <make_jobs>
#     node_version  e.g. "24.2.0" (no leading v)
#     arch          arm64 | x64
#     make_jobs     parallel make -j (default 2)
#
# Output: $OUTPUT_DIR/libnode-<arch>.so
set -euo pipefail

NODE_VERSION="${1:?usage: build-node-ohos.sh <version> <arch> [jobs]}"
ARCH="${2:?}"
MAKE_JOBS="${3:-2}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
OUTPUT_DIR="${OUTPUT_DIR:-${REPO_ROOT}/dist}"
WORKDIR="${REPO_ROOT}/.build"

# Map ARCH
case "${ARCH}" in
  arm64|aarch64) ARCH="arm64"; CLANG_TRIPLE="aarch64-unknown-linux-ohos" ;;
  x64|x86_64|amd64) ARCH="x64"; CLANG_TRIPLE="x86_64-unknown-linux-ohos" ;;
  *) echo "Unsupported ARCH: ${ARCH}"; exit 1 ;;
esac

VERSION="v${NODE_VERSION}"
NODE_DIR="${WORKDIR}/node-${VERSION}"
INSTALL_PREFIX="${WORKDIR}/node-${VERSION}-openharmony-${ARCH}"

mkdir -p "${WORKDIR}" "${OUTPUT_DIR}"

# --- OHOS SDK + LLVM-19 (downloaded by workflow, expected at $WORKDIR) --------
SDK_DIR="${WORKDIR}/ohos-sdk/linux"
LLVM_DIR="${WORKDIR}/llvm-19/llvm"

if [ ! -d "${SDK_DIR}/toolchains" ]; then
    echo "ERROR: OHOS SDK not found at ${SDK_DIR}/toolchains"
    exit 1
fi
if [ ! -d "${LLVM_DIR}/bin" ]; then
    echo "ERROR: LLVM-19 not found at ${LLVM_DIR}/bin"
    exit 1
fi
echo "==> OHOS SDK: ${SDK_DIR}"
echo "==> LLVM-19:  ${LLVM_DIR}"

# --- Node.js source (downloaded by workflow, expected at $WORKDIR) ------------
if [ ! -f "${NODE_DIR}/configure" ]; then
    echo "ERROR: Node.js source not found at ${NODE_DIR}"
    exit 1
fi
echo "==> Node source: ${NODE_DIR}"

# --- Environment ----------------------------------------------------------------
export CC="${LLVM_DIR}/bin/${CLANG_TRIPLE}-clang -fno-emulated-tls"
export CXX="${LLVM_DIR}/bin/${CLANG_TRIPLE}-clang++ -fno-emulated-tls"
export CC_host="gcc"
export CXX_host="g++"
export CFLAGS="${CFLAGS:-} -DNDEBUG"
export CXXFLAGS="${CXXFLAGS:-} -DNDEBUG"

echo "    CC=${CC}"

# --- Patches --------------------------------------------------------------------
cd "${NODE_DIR}"

# Patch 0001: fix argument list too long (gyp make generator for openharmony)
if [ -f "${SCRIPT_DIR}/0001-fix-argument-list-too-long.patch" ]; then
    echo "==> Applying 0001-fix-argument-list-too-long.patch"
    patch -p1 < "${SCRIPT_DIR}/0001-fix-argument-list-too-long.patch" || echo "    (already applied or failed, continuing)"
fi

# Patch: maglev-assembler.h — move set_allow_* out of #ifdef DEBUG
MAGLEV_H="${NODE_DIR}/deps/v8/src/maglev/maglev-assembler.h"
if [ -f "${MAGLEV_H}" ]; then
    echo "==> Patching maglev-assembler.h"
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
        if (prev ~ /allow_deferred_call/) {
            next
        } else {
            print
            next
        }
    }
    { prev = $0; print }
    ' "${MAGLEV_H}" > "${MAGLEV_H}.tmp" && mv "${MAGLEV_H}.tmp" "${MAGLEV_H}"
    if ! grep -q 'bool allow_allocate_ = false;' "${MAGLEV_H}"; then
        sed -i 's/  bool allow_call_ = false;/  bool allow_allocate_ = false;\n  bool allow_call_ = false;/' "${MAGLEV_H}"
    fi
    echo "    Done"
fi

# --- Configure -------------------------------------------------------------------
echo "==> Configuring Node.js ${VERSION} for OpenHarmony ${ARCH} ..."

CONFIGURE_ARGS="--dest-cpu=${ARCH} \
  --dest-os=openharmony \
  --cross-compiling \
  --openssl-no-asm \
  --shared \
  --prefix=${INSTALL_PREFIX}"

# Add --v8-disable-temporal-support if the configure script supports it
if ./configure --help 2>&1 | grep -q -- "--v8-disable-temporal-support"; then
    CONFIGURE_ARGS="${CONFIGURE_ARGS} --v8-disable-temporal-support"
    echo "    (added --v8-disable-temporal-support)"
fi

echo "    Args: ${CONFIGURE_ARGS}"
./configure ${CONFIGURE_ARGS}

# --- Build ------------------------------------------------------------------------
echo "==> Building (make -j${MAKE_JOBS}) ..."
make -j"${MAKE_JOBS}"

# --- Install ----------------------------------------------------------------------
echo "==> Installing ..."
make install

# --- Locate libnode.so -------------------------------------------------------------
LIBNODE=""
for d in \
    "${INSTALL_PREFIX}/lib" \
    "${NODE_DIR}/out/Release/lib.target" \
    "${NODE_DIR}/out/Release"; do
    for f in "${d}"/libnode.so*; do
        [ -e "${f}" ] || continue
        LIBNODE="${f}"
        echo "    Found: ${LIBNODE} ($(du -h "${LIBNODE}" | cut -f1))"
        break 2
    done
done
if [ -z "${LIBNODE}" ]; then
    echo "ERROR: libnode.so not found"
    exit 1
fi

# --- Strip --------------------------------------------------------------------------
echo "==> Stripping ..."
"${LLVM_DIR}/bin/llvm-strip" "${LIBNODE}" || echo "    (strip failed, keeping unstripped)"

# --- Self-sign -----------------------------------------------------------------------
echo "==> Self-signing ..."
BINSIGN_JAR="${SDK_DIR}/toolchains/lib/binary-sign-tool.jar"
if [ -f "${BINSIGN_JAR}" ]; then
    SIGNED_TMP="$(mktemp).signed"
    if java -jar "${BINSIGN_JAR}" sign \
        -inFile "${LIBNODE}" \
        -outFile "${SIGNED_TMP}" \
        -selfSign 1 2>/dev/null; then
        mv -f "${SIGNED_TMP}" "${LIBNODE}"
        echo "    Signed"
    else
        echo "    (self-sign failed, shipping unsigned)"
        rm -f "${SIGNED_TMP}"
    fi
else
    echo "    (binary-sign-tool.jar not found, skipping)"
fi

# --- Output ---------------------------------------------------------------------------
OUT_FILE="${OUTPUT_DIR}/libnode-${ARCH}.so"
cp "${LIBNODE}" "${OUT_FILE}"
echo ""
echo "==> Build complete!"
echo "    Output: ${OUT_FILE}"
echo "    $(du -h "${OUT_FILE}" | cut -f1)  $(file "${OUT_FILE}" | cut -d: -f2)"
