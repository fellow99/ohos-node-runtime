# ohos-node-runtime

[![license](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

> The **OpenHarmony arm64-v8a Node.js runtime** — a real shared `libnode.so`
> loaded via `dlopen` inside a HarmonyOS app process.

This repository contains only the **runtime package** (engine binary + version
constants). The **bridge package** (ArkTS API + bootstrap) lives in
[ohos-node-bridge](https://github.com/fellow99/ohos-node-bridge) and is published
as `@fellow99/node-bridge`.

**Language: English** · [简体中文](README_zh.md)

---

## Releases — ohpm (`@fellow99/node-runtime`)

> ⚠️ **AARCH64 (arm64-v8a) only** — HarmonyOS targets `2in1` / `tablet` (no phone) and there are no x86 / x86_64 / arm32 artifacts.

| Version | OS | Arch | Link |
|---|---|---|---|
| 24.2.0 | OpenHarmony | arm64-v8a | https://ohpm.openharmony.cn/#/cn/detail/@fellow99%2Fnode-runtime/v/24.2.0 |
| 22.23.4 | OpenHarmony | arm64-v8a | https://ohpm.openharmony.cn/#/cn/detail/@fellow99%2Fnode-runtime/v/22.23.4 |
| 24.22.1 | OpenHarmony | arm64-v8a | https://ohpm.openharmony.cn/#/cn/detail/@fellow99%2Fnode-runtime/v/24.22.1 |
| 26.13.0 | OpenHarmony | arm64-v8a | https://ohpm.openharmony.cn/#/cn/detail/@fellow99%2Fnode-runtime/v/26.13.0 |

---

## Installation

```bash
ohpm install @fellow99/node-runtime@26.13.0
```

> The package version **equals the Node.js version**. Node v26.13.0 → package `26.13.0`.

## What's in the package

| Item | Value |
|------|-------|
| Node.js version | **v26.13.0** |
| `process.versions.modules` | **147** (SONAME `libnode.so.147`) |
| ABI | **arm64-v8a** (AArch64) |
| Devices | `2in1` / `tablet` (no phone) |
| Binary size | 119,868,824 B (114.3 MiB) |
| SHA-256 | `15e9e17f93d7aafd11b622ac94cccccf6547ee66cf782fdda5a37c8223ecb57b` |
| Built by | This repo's GitHub Actions (self-built, run `41221254869`) → stable release `v26.13.0` |
| License | Node.js MIT + build scripts MIT |

### Available builds

All are built by `.github/workflows/build-libnode.yml`; the 7 static ELF gates pass (CI + local). Full metadata: [`runtime/README.md`](runtime/README.md).

| Node | ABI / SONAME | Size | Releases |
|------|--------------|------|----------|
| **v26.13.0 (LTS Lithium, Temporal disabled)** | **147** / `libnode.so.147` | 119,868,824 B | `26.13.0` (ohpm) |
| v24.22.1 (LTS Krypton) | 137 / `libnode.so.137` | 114,488,552 B | `24.22.1` (ohpm) |
| v24.2.0 | 137 / `libnode.so.137` | 126,809,264 B | `24.2.0` (ohpm) |
| v22.23.4 (LTS Jod) | **127** / `libnode.so.127` | 121,429,072 B | `22.23.4` (ohpm) |

The bridge loads `libnode.so` by name via `dlopen` (it never links the SONAME and
uses only the stable Node-API + `node::Start`), so the **same** bridge binary runs on
both ABI 127 and 137. A cold build takes ~2.5–3 h on a 4-core GitHub runner (ccache only
helps same-version retries); use a self-hosted runner to speed it up.

This package has **no ArkTS API**. It only ships:

- `libs/arm64-v8a/libnode.so` — the engine itself (V8/JIT, all built-in modules)
- `libs/arm64-v8a/libc++_shared.so` — C++ shared runtime (a `DT_NEEDED` dependency)
- `Index.ets` — version constants (`NODE_VERSION` / `LIB_SHA256` / `RUNTIME_ID`, …)

## The two repositories

| | [ohos-node-bridge](https://github.com/fellow99/ohos-node-bridge) | **ohos-node-runtime** (this repo) |
|---|---|---|
| **ohpm package** | `@fellow99/node-bridge` | `@fellow99/node-runtime` |
| **Version** | Independent semver | **Equals the Node.js version** |
| **Contains** | ArkTS API + bootstrap `.so` | `libnode.so` + `libc++_shared.so` |
| **Release cadence** | Driven by feature work | Driven by Node.js major versions |

They are coupled by a **runtime symbol contract** (`dlopen` + `napi_*`); swapping
the Node.js version does not require recompiling the bridge.

## Repository layout

```
ohos-node-runtime/
├── runtime-har/                  # HAR module (@fellow99/node-runtime)
│   ├── Index.ets                 #   Version constants
│   └── src/main/libs/            #   libnode.so (provisioned, not committed)
├── runtime/                      # Local binary cache
│   ├── SHA256SUMS                #   Checksums (committed)
│   └── node-v24.2.0/
│       └── PROVENANCE.md         #   Provenance (committed; the .so is not)
├── scripts/                      # CI build script + patches (builds libnode)
├── .github/workflows/            # Cloud build (GitHub Actions)
├── tools/                        # provision · release · verify-har · smoke-host · probe
└── runtime.lock.json             # ★ Single source of truth: version + SHA-256 + gates + origin
```

## Building libnode in the cloud (GitHub Actions)

`libnode.so` is cross-compiled on a GitHub-hosted runner — no local Docker needed.
The workflow downloads the OpenHarmony LLVM-19 toolchain (clang + sysroot +
libc++), the Node.js source, applies the required patches, and builds with
`--shared --cross-compiling --openssl-no-asm --dest-os=openharmony`.

Run it manually:

1. Open the **Actions** tab → **Build libnode for OpenHarmony** → **Run workflow**
2. Inputs:
   - `node_version` — e.g. `24.2.0`
   - `arch` — `arm64` / `x64` / `both`
   - `llvm_url` — pinned OpenHarmony LLVM-19 daily-build tarball
3. The run verifies the artifact (`ET_DYN`, no `PT_INTERP`, `node::Start` exported)
4. Output is published to a **prerelease** tagged `v<version>-ohos-<arch>` with
   `libnode-<arch>.so`, `libc++_shared.so`, and `.sha256` files

Relevant files: [`.github/workflows/build-libnode.yml`](.github/workflows/build-libnode.yml),
[`scripts/build-node-ohos.sh`](scripts/build-node-ohos.sh).

## Local provisioning & packaging

```bash
export DEVECO_SDK_HOME='D:\oh-workspace\command-line-tools\sdk'
export PATH="/d/oh-workspace/DevEco Studio/tools/node:$PATH"

# (1) Verify the runtime (7 ELF gates + SHA-256)
node tools/provision.mjs --check

# (2) Provision into the HAR module (idempotent; not committed)
node tools/provision.mjs --out runtime-har/src/main/libs/arm64-v8a

# (3) Build the release HAR
cmd //c "D:\oh-workspace\command-line-tools\bin\hvigorw.bat --mode module -p module=runtimehar@default -p buildMode=release assembleHar --no-daemon"

# (4) Publish gate
node tools/verify-har.mjs runtime-har/build/default/outputs/default/runtimehar.har
```

## Publishing to ohpm

```bash
ohpm config set publish_registry https://ohpm.openharmony.cn/ohpm
ohpm config set publish_id <publisher-id>
ohpm config set key_path <private-key>
ohpm publish runtime-har/build/default/outputs/default/runtimehar.har
```

> Run in an **interactive terminal** (the passphrase prompt hangs/OOMs without a
> TTY). Do **not** pass `-t latest` (the registry rejects it).

## Upgrading the Node.js version

1. Build or obtain a new `libnode-arm64.so` (cloud workflow above; see
   [`runtime/node-v24.2.0/PROVENANCE.md`](runtime/node-v24.2.0/PROVENANCE.md))
2. Place it under `runtime/node-v<version>/`, update `SHA256SUMS`
3. Update `runtime.lock.json` (append a `runtimes[]` entry, switch `active`)
4. Bump `version` in `runtime-har/oh-package.json5`
5. Update constants in `runtime-har/Index.ets`
6. Write `runtime/node-v<version>/PROVENANCE.md`
7. Run `node tools/provision.mjs --check` (7 gates)
8. Run `node tools/release.mjs --all` (version consistency → provision → build → gate)
9. Verify on a real device (`node tools/probe.mjs`)
10. `ohpm publish`

## Binary origin & verification gates

Since 2026-10-25 the v24.2.0 `libnode.so` is **self-built** by this repo's GitHub
Actions workflow (`scripts/build-node-ohos.sh`, run `40147924234`) using OpenHarmony
LLVM-19, cross-compiled from the official Node.js v24.2.0 tarball and published to
release `v24.2.0-ohos-arm64`. Before that it consumed the device-verified
`electerm/ohos-node-shared` prebuilt (its fingerprint is kept in
`runtime.lock.json#previousSource`).

The build produces a true **shared library** (`ET_DYN` + `PT_INTERP=0`) that
`dlopen()`s cleanly — not a PIE executable (whose local-exec TLS aliases the host
app's TLS and kills V8 on the first heap allocation):

- Exports `node::Start`, the required in-process entry point
- Embeds ICU + the V8 snapshot
- Configure flags: `--shared --cross-compiling --openssl-no-asm --v8-disable-temporal-support`

The 7 ELF gates (`provision.mjs --check`):

| # | Check | Meaning |
|---|-------|---------|
| 1 | `ET_DYN` | Shared object, not an executable |
| 2 | `PT_INTERP = 0` | No dynamic loader dependency (directly `dlopen`-able) |
| 3 | `EM_AARCH64` | arm64-v8a |
| 4 | `DT_NEEDED` includes `libc++_shared.so` | C++ runtime dependency |
| 5 | Exports `_ZN4node5StartEiPPc` | `node::Start(int, char**)` |
| 6 | SHA-256 matches the lock | Integrity |
| 7 | Size + version string match | Tamper resistance |

Full provenance: [`runtime/node-v24.2.0/PROVENANCE.md`](runtime/node-v24.2.0/PROVENANCE.md).

## License

This repository is **MIT** licensed ([`LICENSE`](LICENSE)). `libnode.so` is
covered by the **Node.js MIT license** (including the full text of V8/OpenSSL/ICU
and other third-party licenses; see `runtime-har/LICENSE`).
