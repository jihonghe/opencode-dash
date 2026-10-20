# 给 ZCode 的启动提示（可直接复制）

```
你在 ~/code/opencode-quota 为 Omarchy（Quattro 4.x）开发一个可发布的顶栏插件：
OpenCode Quota —— 显示 OpenCode 订阅（Go / Go Plus）的剩余额度。

请先完整读：
- HANDOFF.md
- docs/01-spec.md
- docs/02-data-sources.md
- docs/03-omarchy-plugin-guide.md
- docs/04-research.md
- docs/05-test-plan.md

读完先给我一份实现计划（文件清单 + 每个里程碑的验收方式），我确认后再写代码。

硬性约束：
- 顶栏默认只显示剩余最少的窗口（worst），可选 all / month；百分比默认显示"剩余"。
- 不做 Pace、不做 JSON 导出、不做配额美元换算、不接多 provider、不做 Waybar。
- 通知在插件内用 notify-send，不装 systemd 单元。
- 数据源：官方端点 https://opencode.ai/zen/go/v1/usage（Bearer key）+ 本地 opencode.db 的模型明细。
- key 从 ~/.local/share/opencode/opencode.db 的 credential 表读（v2）；v1 回退 auth.json。
- 绝不把 key 写进文件/日志/提交/错误信息；DB 只读。
- 联网走代理：https_proxy=http://127.0.0.1:10801。
- 改本机配置前 oma-backup；系统级操作先问我；改完 ~/.agents 用 oma-commit --agent zcode。
- 插件 id 本地用 local.opencode-quota；公开时用 <我的 GitHub 用户名>.opencode-quota。
- 按可发布标准做：MIT、README（中英）、截图、omarchy plugin validate 通过。

请先读文档，然后告诉我：你打算怎么分步实现、每一步怎么验证、有哪些风险。
```
