# ohos-node-runtime

[![license](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

> Node.js 的 **OpenHarmony arm64-v8a 运行时**——一个可在 HarmonyOS 应用进程内
> 被 `dlopen` 加载的真正共享库 `libnode.so`。

本仓库只包含 **runtime 包**（引擎二进制 + 版本常量）；**bridge 包**（ArkTS API +
引导件）在 [ohos-node-bridge](https://github.com/fellow99/ohos-node-bridge)，发布为
`@fellow99/node-bridge`。

[English](README.md) · **语言：简体中文**

---

## 安装

```bash
ohpm install @fellow99/node-runtime@24.2.0
```

> 包版本号 **= Node.js 版本号**。Node v24.2.0 → 包 `24.2.0`。

## 这个包装什么

| 项 | 值 |
|---|---|
| Node.js 版本 | **v24.2.0** |
| `process.versions.modules` | **137**（SONAME `libnode.so.137`） |
| ABI | **arm64-v8a**（AArch64） |
| 设备 | `2in1` / `tablet`（不做 phone） |
| 二进制大小 | 126,809,264 B（120.9 MiB） |
| SHA-256 | `92e0ad87d9c7269bdbb9fa12ba46d2162b0133a096b67caeee19e07f6060037b` |
| 构建方 | 本仓库 GitHub Actions（自建，run `40147924234`）→ Release `v24.2.0-ohos-arm64` |
| 许可 | Node.js MIT + 构建脚本 MIT |

本包**不含 ArkTS API**，只提供：

- `libs/arm64-v8a/libnode.so` —— 引擎本体（V8/JIT、全部内置模块）
- `libs/arm64-v8a/libc++_shared.so` —— C++ 共享运行时（`DT_NEEDED` 依赖）
- `Index.ets` —— 版本常量（`NODE_VERSION` / `LIB_SHA256` / `RUNTIME_ID` 等）

## 两个仓库

| | [ohos-node-bridge](https://github.com/fellow99/ohos-node-bridge) | **ohos-node-runtime**（本仓库） |
|---|---|---|
| **ohpm 包** | `@fellow99/node-bridge` | `@fellow99/node-runtime` |
| **版本** | 自身 semver | **= Node 版本** |
| **装什么** | ArkTS API + 引导件 `.so` | `libnode.so` + `libc++_shared.so` |
| **发布节奏** | 跟功能迭代走 | 跟 Node 大版本走 |

两者靠**运行期符号契约**咬合（`dlopen` + `napi_*`），换 Node 版本不需要重编 bridge。

## 仓库结构

```
ohos-node-runtime/
├── runtime-har/                  # HAR 模块（@fellow99/node-runtime）
│   ├── Index.ets                 #   版本常量
│   └── src/main/libs/            #   libnode.so（由 provision 投放，不入库）
├── runtime/                      # 二进制本地缓存
│   ├── SHA256SUMS                #   校验和（入库）
│   └── node-v24.2.0/
│       └── PROVENANCE.md         #   溯源文档（入库；.so 不入库）
├── scripts/                      # 云端构建脚本 + 补丁（产出 libnode）
├── .github/workflows/            # 云端构建（GitHub Actions）
├── tools/                        # provision · release · verify-har · smoke-host · probe
└── runtime.lock.json             # ★ 唯一事实源：版本 + SHA-256 + 门禁 + 出处
```

## 在云上构建 libnode（GitHub Actions）

`libnode.so` 在 GitHub 托管 runner 上交叉编译，本机无需 Docker。workflow 会下载
OpenHarmony LLVM-19 工具链（clang + sysroot + libc++）与 Node.js 源码，应用必要补丁，
再以 `--shared --cross-compiling --openssl-no-asm --dest-os=openharmony` 构建。

手动运行：

1. 打开 **Actions** 标签 → **Build libnode for OpenHarmony** → **Run workflow**
2. 输入参数：
   - `node_version` —— 如 `24.2.0`
   - `arch` —— `arm64` / `x64` / `both`
   - `llvm_url` —— 钉死的 OpenHarmony LLVM-19 每日构建 tarball
3. 构建会校验产物（`ET_DYN`、无 `PT_INTERP`、导出 `node::Start`）
4. 产物发布到 tag 为 `v<版本>-ohos-<arch>` 的 **prerelease**，包含
   `libnode-<arch>.so`、`libc++_shared.so` 及 `.sha256` 文件

相关文件：[.github/workflows/build-libnode.yml](.github/workflows/build-libnode.yml)、
[scripts/build-node-ohos.sh](scripts/build-node-ohos.sh)。

## 本地投放与打包

```bash
export DEVECO_SDK_HOME='D:\oh-workspace\command-line-tools\sdk'
export PATH="/d/oh-workspace/DevEco Studio/tools/node:$PATH"

# ① 校验运行时（七项 ELF 门禁 + SHA-256）
node tools/provision.mjs --check

# ② 投放进 HAR 模块（幂等；不入库）
node tools/provision.mjs --out runtime-har/src/main/libs/arm64-v8a

# ③ 出 release HAR
cmd //c "D:\oh-workspace\command-line-tools\bin\hvigorw.bat --mode module -p module=runtimehar@default -p buildMode=release assembleHar --no-daemon"

# ④ 发布门禁
node tools/verify-har.mjs runtime-har/build/default/outputs/default/runtimehar.har
```

## 发布到 ohpm

```bash
ohpm config set publish_registry https://ohpm.openharmony.cn/ohpm
ohpm config set publish_id <发布码>
ohpm config set key_path <私钥>
ohpm publish runtime-har/build/default/outputs/default/runtimehar.har
```

> 必须在**交互式终端**运行（无 TTY 时口令提示会挂起并 OOM）。
> **不要**加 `-t latest`（服务端拒绝）。

## 升级 Node 版本

1. 构建或获取新的 `libnode-arm64.so`（用上面的云端 workflow；参考
   [`runtime/node-v24.2.0/PROVENANCE.md`](runtime/node-v24.2.0/PROVENANCE.md)）
2. 放入 `runtime/node-v<版本>/`，更新 `SHA256SUMS`
3. 更新 `runtime.lock.json`（追加 `runtimes[]` 条目，切换 `active`）
4. 修改 `runtime-har/oh-package.json5` 的 `version`
5. 更新 `runtime-har/Index.ets` 的常量
6. 撰写 `runtime/node-v<版本>/PROVENANCE.md`
7. 跑 `node tools/provision.mjs --check`（七项门禁）
8. 跑 `node tools/release.mjs --all`（版本一致性 → 投放 → 构建 → 门禁）
9. 真机验证（`node tools/probe.mjs`）
10. `ohpm publish`

## 二进制来源与门禁

自 2026-10-25 起，v24.2.0 的 `libnode.so` 由本仓库 GitHub Actions workflow
（`scripts/build-node-ohos.sh`，run `40147924234`）**自建**：用 OpenHarmony LLVM-19，从 Node.js
官方 v24.2.0 tarball 交叉编译，发布到 Release `v24.2.0-ohos-arm64`。此前使用已设备验证的
`electerm/ohos-node-shared` 预编译产物（指纹保留在 `runtime.lock.json#previousSource`）。

构建产出真正的**共享库**（`ET_DYN` + `PT_INTERP=0`），可直接 `dlopen`——不是 PIE 可执行文件
（PIE 的 local-exec TLS 会别名到宿主应用 TLS，导致 V8 在首次堆分配时崩溃）：

- 导出进程内入口 `node::Start`
- 内嵌 ICU 与 V8 snapshot
- configure 参数：`--shared --cross-compiling --openssl-no-asm --v8-disable-temporal-support`

七项 ELF 门禁（`provision.mjs --check`）：

| # | 检查 | 含义 |
|---|------|------|
| 1 | `ET_DYN` | 共享对象，非可执行文件 |
| 2 | `PT_INTERP = 0` | 不依赖动态加载器（可直接 `dlopen`） |
| 3 | `EM_AARCH64` | arm64-v8a |
| 4 | `DT_NEEDED` 含 `libc++_shared.so` | C++ 运行时依赖 |
| 5 | 导出 `_ZN4node5StartEiPPc` | `node::Start(int, char**)` |
| 6 | SHA-256 与 lock 一致 | 完整性 |
| 7 | 大小 + 版本串一致 | 防篡改 |

完整溯源：[`runtime/node-v24.2.0/PROVENANCE.md`](runtime/node-v24.2.0/PROVENANCE.md)。

## 许可

本仓库 **MIT** 许可（见 [`LICENSE`](LICENSE)）。`libnode.so` 适用 **Node.js 官方 MIT 许可**
（含 V8/OpenSSL/ICU 等全部第三方许可全文，见 `runtime-har/LICENSE`）。
