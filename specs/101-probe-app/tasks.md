# 101-probe-app / tasks.md

> 任务分解与完成标记。`⬜`=未完成 / `✅`=已完成 / `⛔`=阻塞（如实登记）。
> 更新人：本实施轮次。不加 TODO/TBD 占位。

## T1 — 规范（先文档后实现）
- [x] T1.1 spec.md（RFC2119，FR-101-PROBE-010..070，事实披露）
- [x] T1.2 plan.md（命令 + FR→实现点 + 决断 A/B/C/D）
- [x] T1.3 tasks.md（本文件）
- [x] T1.4 test-cases.md（PRB-xx 判据 + host 用例 + 设备 ⬜）
- [x] T1.5 specs/README.md（简短模块说明）

## T2 — probe-app 模块（HAP）
- [x] T2.1 根 build-profile.json5 追加 module `probe-app`
- [x] T2.2 AppScope/app.json5 bundleName → org.fellow99.noderuntime.probe
- [x] T2.3 probe-app/build-profile.json5 + hvigorfile.ts（hapTasks）+ oh-package.json5（file:../runtime-har）
- [x] T2.4 src/main/module.json5（name=probeapp；skills/abilities/requestPermissions 空权限）
- [x] T2.5 EntryAbility.ets（--ps probeAuto）+ pages/Index.ets（摘要页）
- [x] T2.6 common/probe-runner.ets（PRB-01/02/03/04/05）
- [x] T2.7 resources（string/color/media/main_pages）+ rawfile/node-runtime-facts.json（自 lock 生成）

## T3 — payload 投放
- [x] T3.1 `HTTPS_PROXY + NODE_USE_ENV_PROXY` provision 下载 v26.13.0 → runtime-har/libs/arm64-v8a
      （实跑：`--from <release URL>`，因 lock 无 source.url；下载成功、七项门禁全过、SHA 命中）
- [x] T3.2 占位兜底：**未触发**（T3.1 成功投放真实 payload，无占位）

## T4 — 构建验证
- [x] T4.1 ohpm install（仓库根）
- [x] T4.2 hvigorw assembleHap（-p module=probeapp@default；模块标识符 probeapp，见 plan 决断 F）
- [x] T4.3 产物 HAP 路径记录
- [x] T4.4 logs/20261105-1/DEV_CHECKLIST.md

## T5 — 设备运行（本机 ⬜）
- [ ] T5.1 hdc 连设备 / install / `aa start --ps probeAuto true`
- [ ] T5.2 沙箱 probe-result.json 拉取（hdc file recv）
- 前置：在线 HarmonyOS 设备（当前 `hdc list targets`=[Empty]）+ 签名材料（当前无，只出 unsigned）。

## T6 — host 侧交叉用例（本机可跑）
- [x] T6.1 provision 门禁：下载时七项 + `--from runtime-har/libs/arm64-v8a/libnode.so` 补验七项（`--check` 只查本地 store，见 plan 决断 E）
- [x] T6.2 verify-har / smoke-host 引用记录（发布期执行）
