# Changelog

本包的**版本号与 Node 版本严格一致**（`24.2.0` = Node v24.2.0）。
只记录「包形态」的变化；Node 本体变化一律以新版本号出现（如 Node 24.7.0 ⇒ 包 `24.7.0`）。

## Unreleased（仓库 HEAD：切换为自建二进制）

### 变更

- **二进制来源从第三方预编译切换为本仓 GitHub Actions 自建**（`.github/workflows/build-libnode.yml`，run `40147924234`，Release `v24.2.0-ohos-arm64`）：用 OpenHarmony LLVM-19（每日构建 20261024）从 Node.js 官方 v24.2.0 tarball 交叉编译，参数与原产物等价（`--shared --cross-compiling --openssl-no-asm --v8-disable-temporal-support`，`-fno-emulated-tls`）。
- 自建产物 SHA-256 `92e0ad87d9c7269bdbb9fa12ba46d2162b0133a096b67caeee19e07f6060037b`，大小仍为 126,809,264 B，SONAME `libnode.so.137`，七项静态 ELF 门禁全过（含无 `PT_INTERP`、导出 `node::Start`、NEEDED `libc++_shared.so`+`lib.so`）。
- `Index.ets` 的 `LIB_SHA256` 同步更新；`LIB_SIZE` 不变。

### 发布说明

- ohpm 上已发布的 `24.2.0`（2026-10-22）是版本不可变资产，其内为早期 electerm 预编译产物（SHA-256 `3019bf5f9a27…`，已设备验证）。**本自建产物不覆盖 `24.2.0`**：要么随下一个 Node 版本号发布，要么设备验证通过后以新版本号发布。
- 自建产物**真机验证待做**（静态门禁已过；不挪用旧产物的设备记录）。

## 24.2.0（2026-10-22 发布）

### 新增

- 首次发布：`@fellow99/node-runtime@24.2.0`，承载 Node.js **v24.2.0** 的 `libnode.so`（arm64-v8a）。
- 二进制来源：`electerm/ohos-node-shared` @ tag `ohos-node-shared-v24.2.0`，资产 `libnode-arm64.so`
  （投放时改名 `libnode.so`），SHA-256 `3019bf5f9a279d98a87606fc13c53b0e797b6a50cf174f8a1243d880c71151a1`，
  大小 126,809,264 B，`process.versions.modules = 137`。
- 随包附带 `libc++_shared.so`（来自 ohos-sdk，`DT_NEEDED` 需要）。
- `Index.ets` 导出运行时自证常量：`NODE_VERSION` / `NODE_MODULE_VERSION` / `ABI` / `LIB_SHA256` / `LIB_SIZE` / `RUNTIME_ID`。

### 验证

- `tools/provision.mjs --check`：七项 ELF 门禁全过（ET_DYN / 无 `PT_INTERP` / AArch64 / `DT_NEEDED` 含 libc++ /
  导出 `node::Start` / SHA-256 一致 / 大小与版本串一致）。
- `assembleHar`（release）→ 包 `42,936,534 B`；包内 `libs/arm64-v8a/libnode.so` 的 SHA-256 与锁值一致（未被 strip 改动）。
- 真机（`3QC0226526001227`）：样例经本包提供运行时后 `assembleHap` → `/facts` 200，
  `node v24.2.0` / `modules=137` / `fs_write_readback=OK` / `worker_threads=true`。
