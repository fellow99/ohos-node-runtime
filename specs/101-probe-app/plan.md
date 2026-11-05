# 101-probe-app / plan.md

> 实现特定计划。FR = 见 `spec.md` §4；RF = 仓库根（本仓库）；SC = 源码路径。

## 1. 变更面（本实施只动这些）

1. `specs/101-probe-app/`：spec.md / plan.md / tasks.md / test-cases.md + `specs/README.md`（简短）。
2. `probe-app/`（新建 HAP 模块，type=entry）：
   - `build-profile.json5`（apiType=stageMode, targets default）
   - `hvigorfile.ts`（hapTasks）
   - `oh-package.json5`（name `probeapp`；deps `@fellow99/node-runtime: file:../runtime-har`）
   - `src/main/module.json5`（name `probeapp`，不允许连字符；deviceTypes `2in1`,`tablet`）
   - `src/main/ets/entryability/EntryAbility.ets`（读 `--ps probeAuto`，接 umbrella probe）
   - `src/main/ets/common/probe-runner.ets`（探针逻辑核心）
   - `src/main/ets/pages/Index.ets`（结果摘要页）
   - `src/main/resources/base/{element,media,profile}`（string/color/icon/main_pages）
   - `src/main/resources/rawfile/node-runtime-facts.json`（LOCK 事实快照，生成自 runtime.lock.json）
3. `build-profile.json5`（根）：`modules[]` 追加 `probe-app` 条目。
4. `AppScope/app.json5`：bundleName → `org.fellow99.noderuntime.probe`。
5. `runtime-har/libs/arm64-v8a/`：provision 投放 v26.13.0 payload（.gitignore 已忽略，不入库）。
6. `logs/20261105-1/DEV_CHECKLIST.md`：构建验证清单与结果。

## 2. FR → 实现点映射

| FR | 实现点（rf/sc） |
|---|---|
| FR-101-PROBE-010（载荷就位） | `probe-app/src/main/ets/common/probe-runner.ets`：枚举 `context.bundleCodeDir` 下 libs/arm64-v8a 清单 + size |
| FR-101-PROBE-020（版本事实） | 常量 import 自 `@fellow99/node-runtime`（CLAIMED）；`rawfile/node-runtime-facts.json`（LOCK） |
| FR-101-PROBE-030（加载边界） | probe-runner 披露无 NAPI/无桥；设备侧加载项标 ⬜（见 §4 决断） |
| FR-101-PROBE-040（ELF 头） | 设备侧只读 64B 解析魔数/AArch64；完整门禁 host `tools/provision.mjs --check` |
| FR-101-PROBE-050（报告） | 沙箱 `filesDir/probe-result.json`（UTF-8）+ 摘要页 |
| FR-101-PROBE-060（无头） | EntryAbility 读 `want.parameters.probeAuto==='true'` → 自动执行 |
| FR-101-PROBE-070（NFR） | arm64 / App 域 / `minAPIVersion=17` / `targetAPIVersion=24`；无外部网络 |

## 3. 命令（本机可复现）

```bash
# 0. 前提
#    node v24（PATH 已含）；工具链在 D:/oh-workspace 下。


# 1. provision（代理下载 GitHub Release v26.13.0 产物 → 投放进 runtime-har/libs/arm64-v8a）
HTTPS_PROXY=http://127.0.0.1:7890 NODE_USE_ENV_PROXY=1 \
  node tools/provision.mjs --from "https://github.com/fellow99/ohos-node-runtime/releases/download/v26.13.0/libnode-arm64.so" \
    --out runtime-har/libs/arm64-v8a
#    注：lock 的 self-built 条目把 URL 放 source.release.url（顶层无 source.url/mirror.url），
#        故 `--download` 实测报「lock 里没有可下载 URL」；`--from <url>` 走同一代理下载路径，实测成功。
#    补验已投放文件：node tools/provision.mjs --from runtime-har/libs/arm64-v8a/libnode.so --out runtime-har/libs/arm64-v8a

# 2. 依赖解析（仓库根）
D:/oh-workspace/command-line-tools/bin/ohpm.bat install

# 3. 构建 probe-app HAP
D:/oh-workspace/command-line-tools/bin/hvigorw.bat assembleHap --mode module -p module=probeapp@default
#    或全量：.../hvigorw.bat assembleHap
#    注：module 标识符为 `probeapp`（module.json5 的 name 不允许连字符，build-profile 须同名）。
#    产物：probe-app/build/default/outputs/default/probeapp-default-unsigned.hap
#         （无签名材料 → unsigned；不装真机）

# 4. host 侧门禁（交叉引用）
node tools/provision.mjs --check                      # 七项 ELF + SHA-256（payload）
#    └ 注：--check 校验本地 store（runtime/node-<v>/）而非已投放目录；本机 store 无 v26 ⇒
#       用 `--from runtime-har/libs/arm64-v8a/libnode.so`（§3 补验命令）复核已投放文件（实测七项全过）。
node tools/verify-har.mjs <disthar>                   # HAR 发布门禁（可选，发布期）
node tools/smoke-host.mjs                             # host 契约（bridge 仓相关项 skip）
```

## 4. 决断记录（spec 披露项）

- **决断 A（版本不一致）**：lock active=26.13.0/abi147 vs runtime-har Index=24.2.0/abi137。
  不改任何一方；probe 以 PASS-FACT 记录对照。依据 REQ-20-03/20-04。
- **决断 B（payload 投放失败兜底）**：若代理下载失败，`runtime-har/libs/arm64-v8a/` 放
  0 字节占位 `libnode.so` + `libc++_shared.so`（保证 HAP 打包与构建通过），报告中把
  「payload=占位」显式标记，禁止冒充真实载荷。依据 REQ-70-04/70-05。
- **决断 C（加载边界）**：SDK `ets` 全域 grep 无 `requireNapi`/`dlopen`/`loadLibrary`
  声明 ⇒ ArkTS 层不可编译裸 dlopen；本 HAP 无 native 桥 ⇒ 设备侧 PRB-04 登记 ⬜，
  host 侧记「加载语义依赖 bridge」，不硬造执行。依据 REQ-30-01/30-02。
- **决断 D（无设备）**：`hdc list targets`=[Empty] 且无签名材料 ⇒ 设备侧一律 ⬜，
  只交付「未签名 HAP + host 用例」；DEV_CHECKLIST.md 如实登记。依据 NG2/NG4/REQ-50-03。
- **决断 E（provision --download 缺 URL 字段）**：lock self-built 条目的下载地址在
  `source.release.url`（顶层无 `source.url`/`mirror.url`），provision `--download` 因此报
  「lock 里没有可下载 URL」——属 lock schema 与脚本的既有缺口；本实施改用 `--from <url>`
  走同一代理下载路径（实测成功）。不改 tools/（超出本任务范围），在 plan/test-cases 披露。
- **决断 F（module 标识符）**：hvigor 要求根 build-profile 的 module name 与 module.json5 的
  `module.name` 一致且不允许连字符 ⇒ 统一用 `probeapp`（目录仍为 `probe-app/`）。构建命令用
  `-p module=probeapp@default`。

## 5. 顺序

1. specs 四件套 → 2. probe-app 骨架+probe-runner → 3. 根 build-profile/AppScope →
4. provision → 5. ohpm install → 6. hvigorw build → 7. DEV_CHECKLIST + 报告。
