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
# Optional ccache: prefix the cross compiler when ccache is on PATH. gyp invokes
# the compiler through the shell, so the space-separated form works.
if command -v ccache >/dev/null 2>&1; then
    export USE_CCACHE=1
    export CC="ccache ${CLANG} -fno-emulated-tls"
    export CXX="ccache ${LLVM_DIR}/bin/${CLANG_TRIPLE}-clang++ -fno-emulated-tls"
else
    export CC="${CLANG} -fno-emulated-tls"
    export CXX="${LLVM_DIR}/bin/${CLANG_TRIPLE}-clang++ -fno-emulated-tls"
fi
export CC_host="gcc"
export CXX_host="g++"
export CFLAGS="${CFLAGS:-} -DNDEBUG"
export CXXFLAGS="${CXXFLAGS:-} -DNDEBUG"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# --- Patches --------------------------------------------------------------------
cd "${NODE_SRC}"

# Patch 0001: gyp make generator — treat openharmony like linux/android for
# shared-lib/thin-archive link rules (fixes argument-list-too-long). Applied
# only when the source still has the OLD tuple: upstream gyp merged openharmony
# by v22.23.x / v24.22.x, where the patch would fail to apply.
MAKE_PY="${NODE_SRC}/tools/gyp/pylib/gyp/generator/make.py"
if [ -f "${MAKE_PY}" ] && grep -q '("linux", "android")' "${MAKE_PY}" \
        && ! grep -q '("linux", "android", "openharmony")' "${MAKE_PY}"; then
    if [ -f "${SCRIPT_DIR}/0001-fix-argument-list-too-long.patch" ]; then
        echo "==> Applying 0001-fix-argument-list-too-long.patch (old gyp detected)"
        patch -p1 --forward < "${SCRIPT_DIR}/0001-fix-argument-list-too-long.patch" \
            || { echo "ERROR: 0001 patch needed but failed to apply"; exit 1; }
    fi
else
    echo "==> gyp make.py already knows openharmony — skipping 0001 patch"
fi

# Patch: maglev-assembler.h — move set_allow_* declarations out of #ifdef DEBUG.
# Only needed when some caller compiles those setters in RELEASE (NDEBUG) builds;
# early v24.2.0 had such a call site. Newer V8 wraps every call in #ifdef DEBUG,
# so we detect instead of maintaining a version allowlist (fail-safe: on any
# detector error we apply the patch, which is harmless when unneeded).
MAGLEV_H="${NODE_SRC}/deps/v8/src/maglev/maglev-assembler.h"
need_maglev_patch() {
    python3 - "${NODE_SRC}/deps/v8/src" <<'PYEOF'
import pathlib, re, sys
root = pathlib.Path(sys.argv[1])
calls = re.compile(r'set_allow_(?:allocate|call)\s*\(')
debug_guard = re.compile(r'^\s*#\s*(?:ifdef\s+DEBUG|if\s+defined\(\s*DEBUG\s*\))\s*$')
if_re = re.compile(r'^\s*#\s*(if|ifdef|ifndef)\b')
endif_re = re.compile(r'^\s*#\s*endif\b')
found = False
for p in root.rglob('*'):
    if p.suffix not in ('.cc', '.h') and not p.name.endswith('-inl.h'):
        continue
    if p.name in ('maglev-assembler.h', 'maglev-assembler-inl.h'):
        continue
    depth = 0
    try:
        for line in p.read_text(errors='ignore').splitlines():
            if debug_guard.match(line):
                depth += 1
            elif if_re.match(line):
                pass  # non-DEBUG conditional: DEBUG depth unchanged
            if calls.search(line) and depth == 0:
                print(f'RELEASE CALLER: {p}: {line.strip()}')
                found = True
                break
            if endif_re.match(line) and depth > 0:
                depth -= 1
    except OSError:
        sys.exit(2)
    if found:
        break
sys.exit(1 if found else 0)
PYEOF
}
_apply_maglev() {
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
}
# Decision captured explicitly (avoids $? ambiguity around the if/else above).
if [ -f "${MAGLEV_H}" ]; then
    MAGLEV_RC=0
    need_maglev_patch || MAGLEV_RC=$?
    if [ "${MAGLEV_RC}" != "0" ]; then
        echo "==> Applying maglev patch (detector rc=${MAGLEV_RC}: 1=needed, 2=error)"
        _apply_maglev
    else
        echo "==> All set_allow_* callers are DEBUG-only — skipping maglev patch"
    fi
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
