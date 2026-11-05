# Specifications / 101-probe-app

> 模块：probe-app（HarmonyOS HAP 探针）。技术无关、RFC2119 规范。
> 状态：作为 specs 起点，本规范即 101-probe-app 需求基准，无上游依赖。

## 1. 背景与范围（技术无关）

本仓库（ohos-node-runtime）当前只承载运行时 HAR（`runtimehar`，目录 `runtime-har/`）：
对外无 ArkTS 业务 API，`Index.ets` 只导出版本常量；`libnode.so` 以裸 soname 暴露，
无 NAPI 注册，运行期加载依赖桥（bridge 的 C 层 dlopen）或外部消费方。

101-probe-app 交付一个 HAP 模块 `probe-app/`，在**设备侧（无头）**取证四件事：
载荷是否随 HAP 打包就位、版本契约的事实（含不一致披露）、ELF 头校验事实、
加载能力边界（不硬造执行）。结果写入应用沙箱并由 host 侧用例承接可导出部分。

**事实披露（寄存器状态，不臆断谁对）**：仓库当前处于「runtime.lock.json 已升
active=26.13.0 / ABI 147」而「runtime-har 仍写死 24.2.0 / ABI 137」的中间态。
本规范把该**不一致作为事实登记**，探针只如实记录，不做裁决。

## 2. 术语

- **LOCK**：仓库根 `runtime.lock.json`（`active` 及其对应 runtime 条目的事实源）。
- **CLAIMED**：`runtime-har/Index.ets` 对外声称的版本常量而。
- **PASS-FACT**：探针判据——仅要求记录事实并附证据来源，**不判断对错**（区别于 PASS/FAIL）。
- **payload**：`libnode.so`（部署名）+ `libc++_shared.so`（随 HAR 打包的原生载荷）。
- **ps**：Ability 启动参数（`aa start --ps <key> <value>`）透传的 want.parameters。

## 3. 目标与非目标（技术无关）

### 3.1 目标
- G1：构建一个可安装、可无头运行、结果落沙箱的 HAP 探针（probe-app）。
- G2：设备侧客观取证 payload 打包/装载状态与版本契约事实。
- G3：与 host 侧门禁（`tools/provision.mjs --check`、`tools/verify-har.mjs`、
      `tools/smoke-host.mjs` 中与运行时相关的检查）交叉引用，形成可归档证据链。

### 3.2 非目标
- NG1：**不**在本仓库实现 Node 执行（`node::Start`）——引擎无 ArkTS API、无 NAPI，
      执行级验证属 bridge/外部消费方职责（见 7.2 边界）。
- NG2：**不**在本仓库提供签名材料或产出签名 HAP（无签名材料，只出未签名包）。
- NG3：**不**新增 native 源码 / CMake（本仓库是纯预编译载体）。
- NG4：**不**伪造任何设备侧成功语义（无设备则登记 ⬜，见 test-cases.md）。

## 4. 规范（RFC2119）

### 4.1 载荷完整性（FR-101-PROBE-010）
- REQ-10-01 探针 **MUST** 尝试从应用代码路径定位 `arm64-v8a` 原生库目录，并列出其中
  `libnode.so` 与 `libc++_shared.so` 是否存在与文件大小。
- REQ-10-02 探针 **MUST** 将实测尺寸与 LOCK active 项（node=v26.13.0, size=119868824）
  比对并记录「一致/不一致/缺失」。
- REQ-10-03 若原生库目录不可枚举（权限/不存在），探针 **MUST** 如实记录失败原因，
  不得静默通过。

### 4.2 版本契约与不一致披露（FR-101-PROBE-020）
- REQ-20-01 探针 **MUST** 读取 CLAIMED 常量（NODE_VERSION / NODE_MODULE_VERSION / ABI /
  LIB_SHA256 / LIB_SIZE / RUNTIME_ID）。
- REQ-20-02 探针 **MUST** 独立读取随包携带的 LOCK 事实（active node=26.13.0 /
  nodeModuleVersion=147 / size / sha256 / soname）。
- REQ-20-03 探针 **MUST** 输出「CLAIMED vs LOCK」不一致对照，判据为 **PASS-FACT**
  （记录式，不判对错）；本地已知不一致（24.2.0/abi137 vs 26.13.0/abi147）**MUST** 在
  报告中显式列出。
- REQ-20-04 探针 **MUST NOT** 尝试自行「修复」不一致或改写任一版本源。

### 4.3 加载能力边界（FR-101-PROBE-030）
- REQ-30-01 探针 **MUST** 披露：`libnode.so` 无 NAPI 注册，本 HAP 无 native 桥，
  ArkTS 层无裸 dlopen API —— 因此本 HAP **MUST NOT** 声称能启动 Node。
- REQ-30-02 设备侧加载尝试（若 ArkTS 具备可编译的加载手段）判据为 **PASS-FACT**；
  若加载途径在本实施中不可编译/不可用（如无 API），该探针项 **MUST** 登记为 ⬜ 并写明原因，
  **MUST NOT** 编造失败语义。
- REQ-30-03 报告 **MUST** 明确指出「执行级验证依赖 bridge/外部消费方」，给出衔接方向。

### 4.4 ELF 头校验事实（FR-101-PROBE-040）
- REQ-40-01 探针 **MUST** 尝试以只读方式读取本机 payload 文件头（ELF 魔数 0x7F'ELF'、
  64 位小端、e_machine=AArch64 0xB7），结果判 **PASS-FACT**。
- REQ-40-02 完整七项 ELF 门禁 **MUST** 交由 host 侧 `node tools/provision.mjs --check`
  执行，设备侧不得重复实现或伪造；host 结果 **MUST** 记入设备报告对照区。
- REQ-40-03 若设备侧无法读取文件头，如实登记 ⬜ 并引用 host 用例。

### 4.5 HAP 载体报告（FR-101-PROBE-050）
- REQ-50-01 探针 **MUST** 将全部结果以 UTF-8 JSON 写入应用沙箱
  `context.filesDir/` 下固定名 `probe-result.json`，并在界面/日志给摘要。
- REQ-50-02 报告 **MUST** 含：时间戳、机器信息、ABI、产物路径、各探针项
  （id/判据/结果/证据来源）。
- REQ-50-03 报告导出路径/方式 **MUST** 在 plan/test-cases 中明确；host 侧承接
  拉取（如 `hdc file recv`）归为设备在线后的执行项，未接线时登记 ⬜。

### 4.6 无头模式（FR-101-PROBE-060）
- REQ-60-01 探针 **MUST** 支持 `aa start ... --ps probeAuto true` 自动执行全部探针而不依赖
  人工点击。
- REQ-60-02 `probeAuto` 缺省 **MUST** 反映为「等待人工触发」，不得默认自动执行。
- REQ-60-03 单 token 传参约束：`aa start --ps` 每次仅传一个 token（多词 flags 会被截断），
  本探针仅消费单值键（`probeAuto`），不得依赖多词参数。

### 4.7 非功能（FR-101-PROBE-070）
- REQ-70-01 仅构建 `arm64-v8a`（仓库无 x86 产物；NFR：ARCH=arm64-v8a）。
- REQ-70-02 HAP 属 App 域 `org.fellow99.noderuntime.probe`，`runtimeOS=HarmonyOS`，
  `minAPIVersion=17 / targetAPIVersion=24`。
- REQ-70-03 设备运行期 **MUST NOT** 依赖外部网络（探针只读本地文件与常量）。
- REQ-70-04 构建期 **MUST** 可离线/弱网完成：依赖 `file:../runtime-har`（同仓 resolver），
  payload 由 provision 投放或构建期占位（见 plan.md 决断记录）。
- REQ-70-05 禁止项：不得引入未锁定二进制、不得绕过 SHA-256 门禁、不得把占位当真实
  载荷上报（占位须在报告中显式标记）。

## 5. 判据总表

| 探针 | 关联 FR | 判据 | 结果类型 |
|---|---|---|---|
| PRB-01 载荷就位 | FR-101-PROBE-010 | 目录清单+尺寸 vs LOCK | PASS/FAIL/缺失 |
| PRB-02 版本事实 | FR-101-PROBE-020 | CLAIMED vs LOCK 对照 | PASS-FACT |
| PRB-03 ELF 头校验 | FR-101-PROBE-040 | 魔数/AArch64（设备）+ host --check | PASS-FACT（/⬜） |
| PRB-04 加载边界 | FR-101-PROBE-030 | 尝试加载并如实记录（依赖桥） | PASS-FACT（/⬜） |
| PRB-05 报告 | FR-101-PROBE-050/060 | 沙箱 JSON + 无头自动 | PASS/FAIL |

详细判据与 host/device 用例见 `test-cases.md`。
