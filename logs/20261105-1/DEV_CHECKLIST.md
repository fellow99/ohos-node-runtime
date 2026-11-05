# 101-probe-app — 设备/构建验证清单 DEV_CHECKLIST

> 记录轮次：2026-11-05（本机）。与 specs/101-probe-app/{spec,plan,tasks,test-cases}.md 三处交叉引用。
> 无在线 HarmonyOS 设备 + 无签名材料 → 设备侧一律 ⬜；host 侧如实登记。

## 1. 构建验证（host，已完成 ✅）

| 步骤 | 命令 | 结果 |
|---|---|---|
| provision | `HTTPS_PROXY=…:7890 NODE_USE_ENV_PROXY=1 node tools/provision.mjs --from https://github.com/fellow99/ohos-node-runtime/releases/download/v26.13.0/libnode-arm64.so --out runtime-har/libs/arm64-v8a` | ✅ 下载成功；七项 ELF 门禁全过；SHA-256=15e9e17f… 与 lock 一致；投放 libnode.so(119868824B)+libc++_shared.so(1262504B) |
| provision 补验 | `node tools/provision.mjs --from runtime-har/libs/arm64-v8a/libnode.so --out runtime-har/libs/arm64-v8a` | ✅ 七项门禁全过（ET_DYN / PT_INTERP=0 / AArch64 / NEEDED libc+++libc / node::Start 导出 / SHA-256 / v26.13.0 版本串）；SHA 命中→跳过拷贝 |
| ohpm install | `D:/oh-workspace/command-line-tools/bin/ohpm.bat install` | ✅ 完成；probe-app/oh_modules/@fellow99/node-runtime → 符号链接到 runtime-har/ |
| 构建 | `D:/oh-workspace/command-line-tools/bin/hvigorw.bat assembleHap --mode module -p module=probeapp@default` | ✅ **BUILD SUCCESSFUL** in 40s |
| 产物 | `probe-app/build/default/outputs/default/probeapp-default-unsigned.hap` | 121,271,197 B（unsigned，无密钥） |

HAP 内容抽查（unzip -l）：
- `libs/arm64-v8a/libnode.so` = 119868824 B（= lock active size，v26.13.0 payload 随 HAR 进 HAP）
- `libs/arm64-v8a/libc++_shared.so` = 1262504 B
- `resources/rawfile/node-runtime-facts.json` = 575 B（LOCK 事实快照）
- `ets/modules.abc` 含 24.2.0（CLAIMED 常量内联自 @fellow99/node-runtime import）、PRB-01..05、node-runtime-facts

ArkTS 编译告警（非阻塞，如实登记）：
- EntryAbility:19 `Function may throw exceptions`（want 相关，已 try/吞）
- probe-runner:226 `decodeWithStream deprecated`（改用 decode 需再验；保留现状并登记）
- Index:28 `getContext deprecated`（API 语义等价，登记）
- WARN: probeapp 版本 SemVer + `Missing module info for local modules '@fellow99/node-runtime'`（同仓 file: 依赖未在项目层建模，构建仍成功）

## 2. host 用例登记（spec test-cases.md §2）

| 用例 | 判定 |
|---|---|
| H-P1 `provision --list` | ✅ active=v26.13.0/arm64-v8a |
| H-P2 provision 下载投放 | ✅（上述） |
| H-P3 门禁复核 | ✅ 七项全过（provision 下载时 + --from 补验各跑一次） |
| H-P4 verify-har | 引用说明：本轮只包 HAP，未产 dist HAR，发布期执行 |
| H-P5 smoke-host | 引用说明：本仓无 bridge 源码，bridge 相关项跳过 |

## 3. 版本不一致事实（spec 决断 A，只登记不改）

- runtime-har/Index.ets / oh-package.json5 写死：**24.2.0 / abi137** / LIB_SIZE=126809264 / sha=92e0ad87…
- runtime.lock.json active：**26.13.0 / abi147** / size=119868824 / sha=15e9e17f… / soname=libnode.so.147
- 仓库处于「lock 已升 26、runtime-har 仍 24」中间态；发布脚本 tools/release.mjs 对此有断言，本轮**不动**。
- 探针 PRB-02 以 PASS-FACT 输出对照；PRB-01 以 119868824 作为「与 lock 比对」基准（HAP 内 payload 实测即 119868824 → PASS）。

## 4. 设备侧（⬜ 阻塞原因登记）

- `hdc list targets` = **[Empty]**（无在线 HarmonyOS 设备）
- 无签名材料 ⇒ 只出 `probeapp-default-unsigned.hap`，不可装机
- 待接线项（spec test-cases.md §3 D-1..D-5）：install → `aa start -a EntryAbility -b org.fellow99.noderuntime.probe --ps probeAuto true` → 拉取 `filesDir/probe-result.json`
- PRB-04（加载边界）设备侧登记 ⬜：ArkTS 层无裸 dlopen（SDK ets grep requireNapi/dlopen/loadLibrary=无）+ 本 HAP 无 bridge；执行级验证须接 @fellow99/node-bridge

## 5. 阻塞/开放项

1. **设备运行 ⬜**：无在线设备 + 无签名材料（T5）。
2. `provision --download` 缺 URL 字段（lock source.release.url vs 脚本读 source.url/mirror.url）→ 已用 `--from` 绕过，未改 tools/（见 plan 决断 E）。
3. ArkTS 三处 deprecation / throw WARN（非阻塞，见 §1）。
4. 构建期 `Missing module info for local modules '@fellow99/node-runtime'`：同仓 file: 依赖未在项目 build-profile 建模；如需在 CI 稳定复现可后续把模块级依赖显式化（不在本轮范围）。
