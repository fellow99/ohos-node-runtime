# runtime/ —— Node 运行时产物本地仓库（releases）

本目录是 **`ohos-node-bridge` 仓库内**的二进制落地缓存（2026-10-18 自父工程
`<父工程>/ohos-node-runtime/` 迁入）：只放**已发布/已锁定**的运行时产物，供构建流程
幂等投放进 HAP。

> **二进制不入 git，文档入 git**：`.gitignore` 只排除 `/runtime/**/*.so`，
> 本 `README.md`、`SHA256SUMS`、各版本的 `PROVENANCE.md` **随仓库分发**。
> 真正决定"该用哪个二进制"的唯一事实源是 **`../runtime.lock.json`**
> （版本号、SHA-256、门禁结果与出处）；本目录的 `*.so` 只是本机上的一份缓存，
> 缺失时按第 3 节重新填充。

---

## 1. 目录布局

```
runtime/
├── README.md                      ← 本文件（入库）
├── SHA256SUMS                     ← 全目录校验和（sha256sum -c 可直接用，入库）
├── node-v22.23.4/
│   ├── libnode-arm64.so           ← ABI 127 / SONAME libnode.so.127（不入库）
│   └── PROVENANCE.md
├── node-v24.2.0/                  ← active
│   ├── libnode-arm64.so           ← ABI 137 / SONAME libnode.so.137（不入库）
│   └── PROVENANCE.md
└── node-v24.22.1/
    ├── libnode-arm64.so           ← ABI 137 / SONAME libnode.so.137（不入库）
    └── PROVENANCE.md
```

命名约定（新增版本时照抄）：

- 目录 `node-<上游版本>`，例如 `node-v24.2.0`；
- 文件保留**上游资产原名**，例如 `libnode-arm64.so`（部署进 HAP 时才改名 `libnode.so`，
  由 `runtime.lock.json` 的 `deployAs` 控制）。

为什么保留原名而不统一改成 `libnode.so`？因为校验、比对上游、写 `SHA256SUMS` 都要靠原名定位，
改名会让"这份文件到底是哪个 release 资产"变得无法自证。

## 2. 当前内容

| 版本 | ABI | 文件 | 大小 | SHA-256（前 16 位） | 状态 |
| --- | --- | --- | --- | --- | --- |
| v24.22.1 | arm64-v8a | `node-v24.22.1/libnode-arm64.so` | 114,488,552 B (109.2 MiB) | `c3aad4381cdfc940…` | 🔒 自建·静态门禁过（真机待验） |
| v24.2.0 | arm64-v8a | `node-v24.2.0/libnode-arm64.so` | 126,809,264 B (120.9 MiB) | `92e0ad87d9c72698…` | ✅ 锁定（active，自建；ohpm `24.2.0` 内为旧 electerm 产物） |
| v22.23.4 | arm64-v8a | `node-v22.23.4/libnode-arm64.so` | 121,429,072 B (115.8 MiB) | `ab7c62e5ec40b538…` | 🔒 自建·静态门禁过（真机待验；ABI 127 / SONAME .127） |

完整哈希见 `SHA256SUMS` 与各 `node-*/PROVENANCE.md`。三份均为本仓 GitHub Actions 自建（release tag
`v<ver>-ohos-arm64`）；`active` 仍为 v24.2.0（与当前 HAR/ohpm 包一致）。升级 `active` 到新版本需：
设备 probe 通过 → 改 `runtime.lock.json#active` + `runtime-har/Index.ets` 常量 + `oh-package.json5` 版本 → 出 HAR。

## 3. 怎么用

投放（幂等：目标已是同一 SHA-256 就跳过）：

```bash
# 在 ohos-node-bridge/ 下执行；默认来源就是本目录（runtime/）

# ①【发布路径】投进**运行时包**模块 —— 这是 @fellow99/node-runtime 的包内容
node tools/provision.mjs --out runtime-har/libs/arm64-v8a

# ②【离线 / 探针路径】直接投进消费方或样例模块（与 ① 择一）
node tools/provision.mjs --out samples/minimal-app/libs/arm64-v8a
node tools/provision.mjs --check          # 只校验、不投放
node tools/provision.mjs --list           # 打印锁定的运行时可选项
```

指定其它缓存位置（CI / 另一台机器）：

```bash
# 1) 环境变量（优先）
OHOS_NODE_RUNTIME_DIR=/path/to/runtime node tools/provision.mjs --out <dir>
# 2) 显式来源
node tools/provision.mjs --from /path/to/libnode-arm64.so --out <dir>
```

本目录缺失时如何重新填充（离线优先 → 联网兜底）：

```bash
# a) 手工：把上游资产按第 1 节的布局放进来，再校验
cd runtime && sha256sum -c SHA256SUMS

# b) 联网（Node 内置 fetch 默认不读代理；国内网络必须显式开启）
export HTTPS_PROXY=http://127.0.0.1:7890
NODE_USE_ENV_PROXY=1 node tools/provision.mjs --download --out <dir>
```

`provision.mjs` 无论走哪条来源，都会对产物做 **七项 ELF 门禁 + SHA-256 比对**，
任一不过即**硬失败**（绝不静默降级）；校验通过后才会把文件拷进 `entry/libs/<abi>/`，
并按需从 ohos-sdk 取 `libc++_shared.so` 一起投放。

## 4. 新增一个版本

1. 取到通过七项门禁的 `libnode-arm64.so`，放进 `node-<版本>/`；
2. 在 `../runtime.lock.json` 的 `runtimes[]` 追加一条（版本、`size`、`sha256`、
   `soname`、`source`、`gates`、`verifiedOn`），需要切换时改 `active`；
3. 重新生成校验和并当次校验：

   ```bash
   cd runtime && sha256sum node-*/*.so > SHA256SUMS && sha256sum -c SHA256SUMS
   ```
4. 写 `node-<版本>/PROVENANCE.md`（照抄 v24.2.0 那份的结构）；
5. 跑真机探针（`node ../tools/probe.mjs`，在仓库根执行）后再把 `verifiedOn` / `verifiedDevice` / `verifiedNotes` 填上。

**只改 lock、不放二进制**：lock 里没有的产物，`provision.mjs` 会直接拒绝投放（不会"就地找另一个"
凑合）。

## 5. 许可与合规

- Node.js 本体：MIT（+ 其依赖各自的许可，详见上游 `LICENSE`）；
- Node.js 本体：MIT（+ 其依赖各自的许可，详见上游 `LICENSE`）；
- 交叉编译脚本与 workflow：本仓库原创，MIT；
- 本目录下的二进制**随其上游许可分发**，不额外附加条款；对外分发时保留本节说明。

`libc++_shared.so` **不放在本目录**：它属于 ohos-sdk 交付物，由 `provision.mjs` 在投放时
从本机 SDK 取（锁文件里只记录 `libcxx.sdkRelPath`，不固化哈希——因为它的哈希随 SDK 版本变化）。
