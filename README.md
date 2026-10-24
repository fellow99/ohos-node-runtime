# ohos-node-runtime

> Node.js 的 **OpenHarmony arm64-v8a 运行时**（`libnode.so` 共享库）。
> 本仓库只包含 **runtime 包**（引擎二进制 + 版本常量）；**bridge 包**（ArkTS API + 引导件）在
> [ohos-node-bridge](https://github.com/fellow99/ohos-node-bridge)。

## 安装

```bash
ohpm install @fellow99/node-runtime@24.2.0
```

> 版本号 **= Node.js 版本号**。Node v24.2.0 → 包 `24.2.0`。

## 这个包装什么

| 项 | 值 |
|---|---|
| Node 版本 | **v24.2.0** |
| `process.versions.modules` | **137**（SONAME `libnode.so.137`） |
| ABI | **arm64-v8a**（AArch64） |
| 设备 | `2in1` / `tablet`（不做 phone） |
| 二进制大小 | 126,809,264 B（120.9 MiB） |
| SHA-256 | `3019bf5f9a279d98a87606fc13c53b0e797b6a50cf174f8a1243d880c71151a1` |
| 来源 | [`electerm/ohos-node-shared`](https://github.com/electerm/ohos-node-shared) @ `ohos-node-shared-v24.2.0` |
| 许可 | Node.js MIT + 构建脚本 MIT |

本包**不含 ArkTS API**，只提供：
- `libs/arm64-v8a/libnode.so` —— 引擎本体（V8/JIT、全部内置模块）
- `libs/arm64-v8a/libc++_shared.so` —— C++ 共享库（`DT_NEEDED`）
- `Index.ets` —— 版本常量导出（`NODE_VERSION` / `LIB_SHA256` / `RUNTIME_ID` 等）

## 两个仓库

| | [ohos-node-bridge](https://github.com/fellow99/ohos-node-bridge) | [ohos-node-runtime](https://github.com/fellow99/ohos-node-runtime)（本仓库） |
|---|---|---|
| **ohpm 包** | `@fellow99/node-bridge` | `@fellow99/node-runtime` |
| **版本策略** | 自身 semver | **= Node 版本** |
| **装什么** | ArkTS API + 引导件 `.so` | `libnode.so` + `libc++_shared.so` |
| **发布节奏** | 跟功能迭代走 | 跟 Node 大版本走 |

两者靠**运行期符号契约**咬合（`dlopen` + `napi_*`），换 Node 版本不需要重编 bridge。

## 仓库结构

```
ohos-node-runtime/
├── runtime-har/            # HAR 模块（@fellow99/node-runtime）
│   ├── Index.ets           #   版本常量导出
│   └── src/main/libs/      #   libnode.so（由 provision 投放，不入库）
├── runtime/                # 二进制本地缓存
│   ├── SHA256SUMS          #   校验和（入库）
│   └── node-v24.2.0/
│       └── PROVENANCE.md   #   溯源文档（入库；.so 不入库）
├── runtime.lock.json       # ★ 唯一事实源：版本 + SHA-256 + 门禁 + 出处
├── tools/                  # provision · release · verify-har · smoke-host · probe
└── build-profile.json5 oh-package.json5 hvigorfile.ts
```

## 构建与投放

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

> 必须**交互式终端**；无 TTY 环境会死循环 OOM。
> **不要**加 `-t latest`（服务端拒绝）。

## 升级 Node 版本

1. 获取新版本的 `libnode-arm64.so`（来源见 [`runtime/node-v24.2.0/PROVENANCE.md`](runtime/node-v24.2.0/PROVENANCE.md)）
2. 放入 `runtime/node-v<版本>/`，更新 `SHA256SUMS`
3. 更新 `runtime.lock.json`（追加 `runtimes[]` 条目，切换 `active`）
4. 更新 `runtime-har/oh-package.json5` 的 `version`
5. 更新 `runtime-har/Index.ets` 的常量
6. 写 `runtime/node-v<版本>/PROVENANCE.md`
7. 跑 `node tools/provision.mjs --check`（七项门禁）
8. 跑 `node tools/release.mjs --all`（版本一致性 → 投放 → 构建 → 门禁）
9. 真机验证（`node tools/probe.mjs`）
10. `ohpm publish`

## 二进制来源与门禁

当前 v24.2.0 的 `libnode.so` 来自 [`electerm/ohos-node-shared`](https://github.com/electerm/ohos-node-shared)：

- **唯一**发布**共享库形态**（`ET_DYN` + `PT_INTERP=0`，`dlopen` 可直接加载）的 Node OHOS 产物
- 导出 `node::Start`（进程内启动 Node 的必需入口）
- 内嵌 ICU + V8 snapshot
- 构建参数：`--shared --cross-compiling --openssl-no-asm --v8-disable-temporal-support`

七项 ELF 门禁（`provision.mjs --check`）：

| # | 检查 | 说明 |
|---|------|------|
| 1 | `ET_DYN` | 共享库（非可执行文件） |
| 2 | `PT_INTERP = 0` | 不依赖动态加载器（`dlopen` 可直吃） |
| 3 | `EM_AARCH64` | arm64-v8a |
| 4 | `DT_NEEDED` 含 `libc++_shared.so` | C++ 运行时依赖 |
| 5 | 导出 `_ZN4node5StartEiPPc` | `node::Start(int, char**)` |
| 6 | SHA-256 与 lock 一致 | 完整性 |
| 7 | 大小 + 版本串一致 | 防篡改 |

完整溯源见 [`runtime/node-v24.2.0/PROVENANCE.md`](runtime/node-v24.2.0/PROVENANCE.md)。

## 许可

本仓库 **MIT**（见 [`LICENSE`](LICENSE)）。
`libnode.so` 适用 **Node.js 官方 MIT 许可**（含 V8/OpenSSL/ICU 等全部第三方许可全文，
见 `runtime-har/LICENSE`）。
