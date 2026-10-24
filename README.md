# ohos-node-runtime

Node.js 的 **OpenHarmony arm64-v8a 运行时**（`libnode.so` 共享库），供 [ohos-node-bridge](https://github.com/fellow99/ohos-node-bridge) 在 HarmonyOS 应用进程内 `dlopen` 加载。

## ohpm 坐标

```
@fellow99/node-runtime:<node-version>
```

版本号 = Node.js 版本号（如 `24.2.0`）。

## 仓库结构

```
runtime-har/            # HAR 模块（@fellow99/node-runtime）
  Index.ets             # 版本常量导出
  src/main/libs/        # libnode.so（由 CI/provision 投放）
runtime/                # 二进制存储（node-v24.2.0/libnode-arm64.so + PROVENANCE.md）
runtime.lock.json       # 版本 + SHA-256 + 门禁 + 出处（唯一事实源）
tools/                  # provision + release 脚本
```

## License

MIT（见 [LICENSE](LICENSE)）
