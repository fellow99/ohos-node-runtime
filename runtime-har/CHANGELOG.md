# Changelog

本包的**版本号与 Node 版本严格一致**（包 `X.Y.Z` = Node v`X.Y.Z`）。
只记录「包形态」的变化；Node 本体变化一律以新版本号出现（如 Node 24.7.0 ⇒ 包 `24.7.0`）。

## 26.13.0（2026-10-31 发布）

### 新增

- 升级到 Node.js **v26.13.0 LTS（Lithium）**：`libnode.so`（arm64-v8a），119,868,824 B，
  SHA-256 `15e9e17f93d7aafd11b622ac94cccccf6547ee66cf782fdda5a37c8223ecb57b`，SONAME `libnode.so.147`。
- `process.versions.modules = 147`（Node 26 跨大版本 ABI，不同于 Node 24 的 137 / Node 22 的 127）。桥接包以裸名 `dlopen("libnode.so")` + 稳定 Node-API 加载，不链 SONAME，故同一 `@fellow99/node-bridge` 二进制可直接承载。
- 本仓 GitHub Actions 自建（run `41221254869`，稳定 Release `v26.13.0`），OpenHarmony LLVM-19 交叉编译，七项静态 ELF 门禁全过。

### 已知差异

- **Temporal 已禁用**：Node 26 的 Temporal 由 Rust crate（`deps/crates`）构建，上游未提供 Rust→OpenHarmony 交叉 target，故 configure 传 `--v8-disable-temporal-support`。本包**不提供 Temporal API**。
- 随包 `libc++_shared.so` 改为取自 aarch64 三元组的 libcxx-ndk（修复此前多架构包 `find|head -1` 误取 x86_64/arm32 的问题）。
- 真机验证待做。

## 24.22.1（2026-10-31 发布）

### 新增

- 升级到 Node.js **v24.22.1**：`libnode.so`（arm64-v8a），114,488,552 B，
  SHA-256 `c3aad4381cdfc940db165b7497ebf0d6ad290abf2e5a79ee33db4bfe107724e3`，SONAME `libnode.so.137`。
- `process.versions.modules = 137`（与 Node 24.x 一致，对 24.2.0 为 drop-in 升级）。
- 本仓 GitHub Actions 自建（run `41221254910`，稳定 Release `v24.22.1`），零源码补丁。
- 随包 `libc++_shared.so` 修复为 aarch64 架构（此前多架构包误取 x86_64）。
- 真机验证待做。

## 22.23.4（2026-10-31 发布）

### 新增

- 升级到 Node.js **v22.23.4 LTS（Jod）**：`libnode.so`（arm64-v8a），121,429,072 B，
  SHA-256 `ab7c62e5ec40b538d305451be62c0d47a48e8ecd56cb30d96e39673ec267394c`，SONAME `libnode.so.127`。
- `process.versions.modules = 127`（Node 22 LTS Jod，ABI 不同于 Node 24 的 137，但 bridge 以 dlopen 按名加载、不链 SONAME，故同一 bridge 可载）。
- 本仓 GitHub Actions 自建（run `41221255138`，稳定 Release `v22.23.4`）。
- 随包 `libc++_shared.so` 修复为 aarch64 架构。
- 真机验证待做。

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
