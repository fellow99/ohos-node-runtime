# specs / README

`specs/` 是本仓库的规范目录，当前仅含一个条目：**101-probe-app**（见下）。

- `101-probe-app/`：probe-app（HAP 探针）需求基准。
  - `spec.md`：技术无关规范（RFC2119，FR-101-PROBE-010..070）。
  - `plan.md`：实现特定计划（命令 / FR→实现点 / 决断记录）。
  - `tasks.md`：任务分解与完成标记。
  - `test-cases.md`：判据与 host / device 用例（含 ⬜ 登记）。

约定：
- 先文档后实现：改动任何 FR 判定须同步更新 spec → plan → tasks → test-cases。
- 事实披露优先：寄存器状态（如 lock 26.13.0 vs Index 24.2.0 不一致）只记录、不臆断。
- 无 TODO/TBD 占位；未完成项用 ⬜ 并写明阻塞原因。
