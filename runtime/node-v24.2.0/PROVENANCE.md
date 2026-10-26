# PROVENANCE —— node-v24.2.0 / arm64-v8a（自建）

本文件自证：`libnode-arm64.so` **是什么、从哪来、怎么建的、能不能用、验过没有**。
与 `../../runtime.lock.json` 中 `node === "v24.2.0" && abi === "arm64-v8a"` 那条一一对应。

> **2026-10-25 起，运行时由「第三方预编译」切换为「本仓库自建」**：
> 用本仓库 GitHub Actions（`.github/workflows/build-libnode.yml`）在云上交叉编译，
> 不再依赖 `electerm/ohos-node-shared` 的预编译资产。旧产物的指纹保留在
> `runtime.lock.json` 的 `previousSource` 字段，不静默抹除历史。

---

## 1. 身份

| 项 | 值 |
| --- | --- |
| 文件 | `libnode-arm64.so`（CI 发布资产原名） |
| 大小 | 126,809,264 B（120.9 MiB；`llvm-strip` 后） |
| SHA-256 | `92e0ad87d9c7269bdbb9fa12ba46d2162b0133a096b67caeee19e07f6060037b` |
| Node 版本 | v24.2.0 |
| `process.versions.modules` | 137（SONAME `libnode.so.137`） |
| ABI / 架构 | arm64-v8a（AArch64，`e_machine = 0xb7`） |

## 2. 出处（自建，可复现）

| 项 | 值 |
| --- | --- |
| 构建方式 | 本仓库 GitHub Actions（无需本机 Docker） |
| Workflow | `.github/workflows/build-libnode.yml`（job `build`，matrix arch=arm64） |
| 构建脚本 | `scripts/build-node-ohos.sh` |
| 成功 run | `40147924234`（2026-10-25，约 212 min，4 核 ubuntu-24.04 runner + 16 GB swap） |
| 发布 Release | tag [`v24.2.0-ohos-arm64`](https://github.com/fellow99/ohos-node-runtime/releases/tag/v24.2.0-ohos-arm64)（prerelease） |
| 资产 URL | https://github.com/fellow99/ohos-node-runtime/releases/download/v24.2.0-ohos-arm64/libnode-arm64.so |
| 校验和 | 同 Release 的 `libnode-arm64.so.sha256` |
| Node 源码 | https://nodejs.org/dist/v24.2.0/node-v24.2.0.tar.gz |
| 工具链 | OpenHarmony **LLVM-19** 每日构建 `20261024_061421`（clang + lld + ohos-sysroot + libcxx-ndk） |
| Runner | ubuntu-24.04（GitHub-hosted），`make -j4`，ccache（首轮冷启动） |
| 许可 | Node.js 本体 MIT（含 V8/OpenSSL/ICU 等第三方许可，见 `runtime-har/LICENSE`） |

构建参数（与第三方预编译等价，保证 ABI/行为一致）：

```
./configure --dest-cpu=arm64 --dest-os=openharmony \
            --cross-compiling --openssl-no-asm --shared \
            --v8-disable-temporal-support
CC/CXX   = aarch64-unknown-linux-ohos-clang(++) -fno-emulated-tls
CFLAGS   = -DNDEBUG   (+ 早期 v24 需要的 -Wno-error=implicit-function-declaration)
CC_host  = gcc   CXX_host = g++
补丁     = scripts/0001-fix-argument-list-too-long.patch（gyp make 生成器认 openharmony）
           + maglev-assembler.h（set_allow_* 移出 #ifdef DEBUG）
后处理   = llvm-strip；不自签（HAP 内原生库不需要 .codesign）
```

为什么必须 `--shared`：`--shared` 产出**真正的共享库**（PIC + 动态 TLS，`ET_DYN` 且
`PT_INTERP=0`），`dlopen` 才能干净加载。PIE 可执行文件形态（`PT_INTERP=1`）的
local-exec `%fs` TLS 会别名到宿主应用的 TLS 块，V8 在 `Isolate::Initialize` 的首次堆分配
就触发 release CHECK `AllowHeapAllocationInRelease::IsAllowed()` 崩溃。

## 3. ELF 事实（自解析 + llvm-readelf 双重确认）

| 项 | 实测 |
| --- | --- |
| `e_type` | `ET_DYN`（共享对象，非可执行文件） |
| `PT_INTERP` | **0**（无动态加载器依赖，`dlopen` 可直吃） |
| `e_machine` | `0xb7`（AArch64） |
| `DT_SONAME` | `libnode.so.137` |
| `DT_NEEDED` | `libc++_shared.so`、`lib.so`（OHOS bionic） |
| `node::Start` | `T _ZN4node5StartEiPPc`（已定义导出） |
| 节区 | 有 `.note.ohos.ident`（OHOS clang 自带）；无 `.codesign`（未自签） |
| ICU | 内嵌 |
| V8 snapshot | 内嵌 |
| `expose-internals` 串 | 存在 |

七项门禁（`node tools/provision.mjs --check`）2026-10-25 全过：

```
OK ① e_type == ET_DYN(3)            实测 3
OK ② PT_INTERP 计数 == 0            实测 0
OK ③ e_machine == AArch64(0xB7)    实测 b7
OK ④ DT_NEEDED 含 libc++_shared.so 实测 libc++_shared.so,lib.so
OK ⑤ node::Start 已导出             实测 true
OK ⑥ SHA-256 与 lock 一致           92e0ad87…
OK ⑦ 大小一致 / 版本串存在          v24.2.0
附加：.codesign=false .note.ohos.ident=true expose-internals=true
```

## 4. 验证状态（诚实区分「静态」与「真机」）

- **静态门禁**：✅ 已过（CI verify step + 本机 `provision --check` 双重）。
- **真机验证**：⏳ **待做**。切换二进制后必须在 HarmonyOS 真机重跑
  `node tools/probe.mjs`（进程内 `dlopen` + `node::Start` + JIT/WASM/worker/fs），
  通过后才能把 `runtime.lock.json` 的 `verifiedOn/verifiedDevice` 填上、发布 ohpm。
- 参照：同 Node 版本（v24.2.0）的旧第三方产物曾在 HAD-W24 / OpenHarmony 7.0 真机通过
  （见 `runtime.lock.json#previousSource` 与原 ohos-node-bridge docs/002）。同源码、同
  configure flags、同 LLVM-19 系列工具链，预期行为一致，但**不以旧记录替代新产物的真机验证**。

## 5. 如何复现

1. 仓库 Actions → **Build libnode for OpenHarmony** → Run workflow：
   `node_version=24.2.0`，`arch=arm64`（`llvm_url` 用默认钉死值）。
2. 约 3.5 小时（冷构建；ccache 仅对**同版本重试**增量有效）后，产物在
   prerelease `v24.2.0-ohos-arm64`：`libnode-arm64.so`（+ `.sha256`）、`libc++_shared.so`。
3. 下载资产放到 `runtime/node-v24.2.0/libnode-arm64.so`，在 `runtime/` 下
   `sha256sum -c SHA256SUMS`，再 `node tools/provision.mjs --check`。
4. 提速：4 核托管 runner 是当前瓶颈；需要频繁出包时改挂 self-hosted runner（核多/内存大）。

## 6. 许可与合规

- Node.js 本体 MIT（+ V8/OpenSSL/ICU/zlib 等各自许可，全文见 `runtime-har/LICENSE`）；
- 构建脚本与 workflow 为本仓库原创，MIT；
- `libc++_shared.so` 来自 OpenHarmony LLVM-19 的 libcxx-ndk，随其工具链许可分发；
- 二进制无自签 `.codesign` 段；HAP 内原生库不需要（真机实测，见 ohos-node-bridge 工程规划 §D.6）。
