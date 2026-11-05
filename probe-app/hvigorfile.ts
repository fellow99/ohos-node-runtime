import { hapTasks } from '@ohos/hvigor-ohos-plugin';

/**
 * probe-app —— HAP 模块探针。
 * 签名材料在仓库根 hvigorfile.ts 统一注入；本模块无签名配置时产出未签名包（本仓库仅编译验证）。
 */
export default {
  system: hapTasks, /* Built-in plugin of hvigor. It cannot be modified. */
  plugins: []       /* Custom plugin to extend the functionality of hvigor. */
};
