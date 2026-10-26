# PROVENANCE —— node-v24.22.1 / arm64-v8a（自建）

本仓库 GitHub Actions 自建产物，结构与门禁口径同
[`../node-v24.2.0/PROVENANCE.md`](../node-v24.2.0/PROVENANCE.md)（构建原理、为什么必须 `--shared`、七项门禁含义见该文）。

## 1. 身份

| 项 | 值 |
| --- | --- |
| 文件 | `libnode-arm64.so` |
| 大小 | 114,488,552 B（109.2 MiB；`llvm-strip` 后） |
| SHA-256 | `c3aad4381cdfc940db165b7497ebf0d6ad290abf2e5a79ee33db4bfe107724e3` |
| Node 版本 | v24.22.1（Current → 已转 LTS **Krypton**） |
| `process.versions.modules` | 137（SONAME `libnode.so.137`） |
| ABI / 架构 | arm64-v8a（AArch64，`e_machine = 0xb7`） |

## 2. 出处

| 项 | 值 |
| --- | --- |
| Workflow | `.github/workflows/build-libnode.yml` |
| 成功 run | [`40212292303`](https://github.com/fellow99/ohos-node-runtime/actions/runs/40212292303)（2026-10-25，约 157 min） |
| Release | [`v24.22.1-ohos-arm64`](https://github.com/fellow99/ohos-node-runtime/releases/tag/v24.22.1-ohos-arm64)（prerelease） |
| Node 源码 | https://nodejs.org/dist/v24.22.1/node-v24.22.1.tar.gz |
| 工具链 | OpenHarmony LLVM-19 每日构建 `20261024_061421` |

构建参数：

```
./configure --dest-cpu=arm64 --dest-os=openharmony --cross-compiling \
            --openssl-no-asm --shared
CC/CXX = aarch64-unknown-linux-ohos-clang(++) -fno-emulated-tls；CFLAGS=-DNDEBUG
```

**零源码补丁**：此版本 gyp make.py 已内建 openharmony（0001 跳过）、所有 maglev
`set_allow_*` 调用点都在 `#ifdef DEBUG` 内（maglev 补丁跳过）。注意该版本 configure
**已没有** `--v8-disable-temporal-support` 选项（24.2.0 早期才需要），V8 temporal
support 保持开启，编译/链接正常。

## 3. ELF 事实（CI verify + 本机 llvm-readelf 双确认）

ET_DYN；PT_INTERP=0；e_machine=0xb7；SONAME `libnode.so.137`；DT_NEEDED
`libc++_shared.so` + `lib.so`；导出 `T _ZN4node5StartEiPPc`；有 `.note.ohos.ident`、
无 `.codesign`；含版本串 `v24.22.1` 与 `expose-internals`。七项门禁
（`node tools/provision.mjs --check --node v24.22.1`）2026-10-26 全过。

## 4. 验证状态

- 静态门禁：✅ CI + 本机双过。
- 真机验证：⏳ 待做。与 v24.2.0 同为 ABI 137、同一加载契约，理论上 drop-in；
  但新二进制必须独立在 HarmonyOS 真机 probe 通过后才能发布 ohpm `24.22.1`。
