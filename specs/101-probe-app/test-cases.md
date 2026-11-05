# 101-probe-app / test-cases.md

> 判据与用例。**host**=本机（无设备可跑）；**device**=HarmonyOS 真机
> （本机 `hdc list targets`=[Empty] 且无签名材料 ⇒ 全部登记 ⬜，写明前置）。
> **PASS-FACT**=记录式判据（只要求记录 + 附证据来源，不判对错）。

## 0. 全局禁止判据（必读）
- FB-1 禁止把「占位 payload」当作真实载荷上报（占位必须显式标记 `placeholder=true`）。
- FB-2 禁止绕过 SHA-256 / 七项 ELF 门禁做任何投放判定。
- FB-3 禁止在设备侧硬造 `dlopen 成功`/`Node 启动`语义（无 API / 无桥即 ⬜）。
- FB-4 禁止修改 `runtime-har/Index.ets` / `runtime.lock.json` 任一版本源来做「对齐」。

## 1. PRB-xx 判据

### PRB-01 载荷就位（FR-101-PROBE-010）— host+device
- P1-1 枚举 `context.bundleCodeDir`（device）/ `runtime-har/libs/arm64-v8a`（host）下
  `libnode.so`、`libc++_shared.so` 是否存在。
- P1-2 实测 size vs LOCK active（libnode 119868824）：`match | mismatch | missing`。
- P1-3 目录不可枚举 ⇒ 记录原因，判 `FAIL`（不得静默 PASS）。

### PRB-02 版本事实（FR-101-PROBE-020）— host+device
- P2-1 输出 CLAIMED（@fellow99/node-runtime：NODE_VERSION=24.2.0 / NODE_MODULE_VERSION=137 /
  ABI=arm64-v8a / RUNTIME_ID）。
- P2-2 输出 LOCK（rawfile 事实：node=26.13.0 / nodeModuleVersion=147 / size=119868824 /
  soname=libnode.so.147）。
- P2-3 对照列 `差异项`（版本/abi/size/sha256 至少版本与 abi 必须如实列出）→ **PASS-FACT**。
- P2-4 证据源字段 = `runtime-har/Index.ets` 与 `runtime.lock.json`（经 rawfile 快照）必填。

### PRB-03 ELF 头校验（FR-101-PROBE-040）— host(device ⬜/记录)
- P3-1 host：`node tools/provision.mjs --check` ⇒ 七项门禁全过 ⇒ PASS（任一 FAIL ⇒ FAIL）。
- P3-2 device：只读 64B，判魔数 `7F 45 4C 46` + `e_machine=AArch64(0xB7)` ⇒ **PASS-FACT**。
      读取失败 ⇒ ⬜（引用 P3-1 host 结果）。完整门禁**不**在设备侧复刻。
- P3-3 预期（本机为 v26.13.0 静态门禁已验 2026-10-31）：host PASS-七项详见 lock `staticGatesVerifiedOn`。

### PRB-04 加载边界（FR-101-PROBE-030）— ⬜（device 不可执行）
- P4-1 ArkTS 层无裸 `requireNapi`/`dlopen`/`loadLibrary` 声明（SDK as grep 实证）+ 本 HAP 无
  native 桥 + libnode.so 无 NAPI 注册 ⇒ 加载尝试**不可编译/不可编译成合法语义**。
- P4-2 判据：**PASS-FACT**（记录「不可执行」+ 原因），**非** PASS/FAIL——不得伪造 dlopen 结果。
- P4-3 衔接：执行级验证 `node::Start` 依赖 bridge C 层 dlopen（`@fellow99/node-bridge`
  仓 `library/src/main/cpp/...`），本仓库只披露边界。

### PRB-05 报告（FR-101-PROBE-050/060）— host(device 未接线 ⬜)
- P5-1 结果 UTF-8 JSON 写 `filesDir/probe-result.json`；包含时间戳/ABI/各探针 id+判据+来源。
- P5-2 无头：`aa start ... --ps probeAuto true` 自动执行（未接线=device ⬜；逻辑经编译验证）。
- 判定：文件存在且 JSON 合法 && 各必填字段齐全 ⇒ PASS（构建期以「逻辑编译通过」为限）。

## 2. host 用例（本机可执行，逐条登记结果）
| 用例 | 命令 | 判定 | 登记 |
|---|---|---|---|
| H-P1 | `node tools/provision.mjs --list` | 打印 active=v26.13.0 | ✅（active=v26.13.0） |
| H-P2 | `HTTPS_PROXY=… NODE_USE_ENV_PROXY=1 node tools/provision.mjs --from <release URL> --out runtime-har/libs/arm64-v8a` | 投放成功 / 占位 | ✅（v26.13.0 下载成功，七项门禁全过） |
| H-P3 | 门禁复核（`--check` 只校验本地 store，见 plan 决断 E）`node tools/provision.mjs --from runtime-har/libs/arm64-v8a/libnode.so --out runtime-har/libs/arm64-v8a` | 七项门禁 | ✅（SHA 命中，七项全过，跳过拷贝） |
| H-P4 | `node tools/verify-har.mjs <runtime-har 打包 har>` | 发布门禁（发布期） | 说明：本构建只包 HAP，未产 dist HAR，作引用 |
| H-P5 | `node tools/smoke-host.mjs` | host 契约（bridge 相关项 skip） | 说明：本仓无 bridge 源码，作引用 |

## 3. device 用例（⬜ 本机无在线设备 / 无签名材料）
- D-1 前置：在线 HarmonyOS 设备 + `hdc list targets` 非空 + 签名材料（debug/release Profile）。
- D-2 `hdc install <unsigned或signed>.hap`（unsigned 需设备侧允许/或签名后）→ 安装状态记录。
- D-3 `hdc shell "aa start -a EntryAbility -b org.fellow99.noderuntime.probe --ps probeAuto true"`
      → onWindowStage 执行探针 → 日志输出 PRB-01..05 摘要。
- D-4 `hdc shell cat /data/app/<...>/probe-result.json` 或 `hdc file recv` 拉报告 → 逐项核对
      P1/P2/P3/P4/P5 登记。
- D-5 加载边界复核：若接入 bridge NAPI 后重跑 P4（真 dlopen），须在 test-cases 追加实测结果。
- 以上未执行为 ⬜（阻塞原因：`hdc list targets`=[Empty]；无签名材料→仅产出 unsigned HAP）。

## 4. 判据汇总（本实施应达状态）
- host：H-P1/H-P2/H-P3 有实测登记；H-P4/H-P5 为引用说明。
- device：D-1..D-5 全部 ⬜，阻塞原因写入 DEV_CHECKLIST.md。
- 一致性：本文件与 `dev checklist`/`report` 三处交叉引用，任何不一致须显式列出。
