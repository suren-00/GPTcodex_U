# GPTcodex_U v1.2.1

## 修复内容

- 修复 Codex 官方接口的当天桶更新延迟时，旧的官方值覆盖本机实时统计的问题。
- 历史累计、历史每日趋势继续使用官方数据；当天用量使用官方值与本机 `token_count` 实时值中更完整的结果。
- 清理项目主页和仓库中的旧版截图、公众号二维码、交流群二维码及相关宣传内容。

## 本机核验

修复前，官方当天延迟快照为 `9440140` tokens；同一时刻本机实时 `token_count` 已超过 `1 亿`。修复后程序输出会随本机事件更新，不再固定停留在 `944 万`。

## 安装

1. Apple Silicon Mac 下载 `GPTcodex_U-1.2.1-mac-arm64.dmg`；Intel Mac 下载 `GPTcodex_U-1.2.1-mac-x86_64.dmg`。
2. 打开 DMG，将 `GPTcodex_U.app` 拖入 Applications。
3. 首次启动若被 macOS 拦截，请在“系统设置 → 隐私与安全性”中选择“仍要打开”。

## SHA-256

- `GPTcodex_U-1.2.1-mac-arm64.dmg`: `070ea224184af1fcf5a03ad21d4fc4201bec97a207c7c3ea5b106b4d5f769c3b`
- `GPTcodex_U-1.2.1-mac-x86_64.dmg`: `b3b36cde3bb0828a0df3ed9a4935d44651d6ee1b293a215bf13a064ec86bb9f0`

## 说明

安装包使用临时（ad-hoc）签名，未经过 Apple 公证；第一次打开时可能需要手动允许。
