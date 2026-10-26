# PROVENANCE —— node-v22.23.4 / arm64-v8a（自建）

本仓库 GitHub Actions 自建产物。构建原理、为什么必须 `--shared`、七项门禁含义见
[`../node-v24.2.0/PROVENANCE.md`](../node-v24.2.0/PROVENANCE.md)。

## 1. 身份

| 项 | 值 |
| --- | --- |
| 文件 | `libnode-arm64.so` |
| 大小 | 121,429,072 B（115.8 MiB；`llvm-strip` 后） |
| SHA-256 | `ab7c62e5ec40b538d305451be62c0d47a48e8ecd56cb30d96e39673ec267394c` |
| Node 版本 | v22.23.4（**LTS Jod**） |
| `process.versions.modules` | **127**（SONAME `libnode.so.127`） |
| ABI 对 bridge 的影响 | 与 24 线不同（127 vs 137）；bridge 以 `dlopen` 按名加载、不链 SONAME，故同一 bridge 可载 |
| ABI / 架构 | arm64-v8a（AArch64，`e_machine = 0xb7`） |

## 2. 出处

| 项 | 值 |
| --- | --- |
| Workflow | `.github/workflows/build-libnode.yml` |
| 成功 run | [`40213105923`](https://github.com/fellow99/ohos-node-runtime/actions/runs/40213105923)（2026-10-25，约 172 min；含一次因 C++ 标准失败的重试） |
| Release | [`v22.23.4-ohos-arm64`](https://github.com/fellow99/ohos-node-runtime/releases/tag/v22.23.4-ohos-arm64)（prerelease） |
| Node 源码 | https://nodejs.org/dist/v22.23.4/node-v22.23.4.tar.gz |
| 工具链 | OpenHarmony LLVM-19 每日构建 `20261024_061421` |

构建参数：

```
./configure --dest-cpu=arm64 --dest-os=openharmony --cross-compiling \
            --openssl-no-asm --shared
CC/CXX = aarch64-unknown-linux-ohos-clang(++) -fno-emulated-tls；CFLAGS=-DNDEBUG
```

### 唯一需要的补丁：给 openharmony 开 C++20（node 22 专属）

Node 22 全局以 `gnu++17` 编译（`common.gypi`），仅把**核心 target** 通过
`common_node.gypi` 升到 `gnu++20`，但其 OS 白名单里有 `android`、**没有 `openharmony`**。
后果：`deps/ncrypto` 使用了 C++20（三向比较 `operator<=>`、`auto` 形参的缩写函数模板），
却按 17 编译，报 10 个 error（`'auto' not allowed in function prototype`、
`'operator<=' cannot be the name of a variable or data member`）。
构建脚本以特征检测的 sed 将 `openharmony` 加入白名单（v24+ 全局已是 gnu++20、无此文件，自动跳过）。
首跑（run `40212286975`）即因此失败，修复（commit `9cd56f1`）后通过。

gyp 0001 与 maglev 两个历史补丁在此版本均自动跳过（源码已修）；configure 无
`--v8-disable-temporal-support` 选项。

## 3. ELF 事实

ET_DYN；PT_INTERP=0；e_machine=0xb7；SONAME **`libnode.so.127`**；DT_NEEDED
`libc++_shared.so` + `lib.so`；导出 `T _ZN4node5StartEiPPc`；有 `.note.ohos.ident`、
无 `.codesign`；含版本串 `v22.23.4` 与 `expose-internals`。七项门禁
（`node tools/provision.mjs --check --node v22.23.4`）2026-10-26 全过。

## 4. 验证状态

- 静态门禁：✅ CI + 本机双过。
- 真机验证：⏳ 待做。发布 ohpm `22.23.4` 前必须在 HarmonyOS 真机 probe
  （dlopen + node::Start + JIT/WASM/worker/fs）通过。
