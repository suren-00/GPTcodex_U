# GPTcodex_U v1.2.0

## 主要更新

- Codex 累计、近 7 天、月度与每日趋势改用 app-server 官方 `account/usage` 数据，尽量与 Codex 官方统计页保持一致。
- 官方当天桶尚未生成时，使用排除 subagent 重复事件后的本机 `token_count` 实时补齐“今日”；官方数据出现后自动切回官方值。
- Token 数量按中文习惯显示：达到一万使用“万”，达到一亿使用“亿”；金额保持完整数字。
- 菜单栏额度进度条加长并改用更深的绿色，百分比使用高对比白字，重置倒计时（如 `5d`）放大加粗。
- 应用名称更新为 `GPTcodex_U`，同时替换程序坞 3D 彩色图标和菜单栏纯白模板图标。
- 合入上游 v1.1.4 的 macOS 13、app-server 管道读取和内存稳定性修复。

## 安装

1. Apple Silicon Mac 下载 `GPTcodex_U-1.2.0-mac-arm64.dmg`；Intel Mac 下载 `GPTcodex_U-1.2.0-mac-x86_64.dmg`。
2. 打开 DMG，将 `GPTcodex_U.app` 拖入 Applications。
3. 首次启动若被 macOS 拦截，请在“系统设置 → 隐私与安全性”中选择“仍要打开”。

## SHA-256

- `GPTcodex_U-1.2.0-mac-arm64.dmg`: `9ef59a4176d041522493953b3c55811d4ec0ceac096dd06623a93ea9f72d6bce`
- `GPTcodex_U-1.2.0-mac-x86_64.dmg`: `a7a2e5481d3ae856164ee9816e31305a41a4099d4bf6fc5a2825641cdc5ecae2`

## 说明

安装包使用临时（ad-hoc）签名，未经过 Apple 公证；第一次打开时可能需要手动允许。应用继续沿用原 Bundle ID、可执行文件名和缓存目录，以兼容已有设置与历史数据。
