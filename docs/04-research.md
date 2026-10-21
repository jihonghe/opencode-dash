# 04 · 同类工具调研（2026-10-20）

> **2026-10-21 范围变更**：本地用量/模型明细/cost/趋势图已移除；本文的
> 模型明细、趋势等“借鉴”条目仅作历史参考，最终采用官方百分比、Runway
> （Avg/Active）、阈值颜色和设置结构。
>
> 目的：不闭门造车。下面是同类工具的**功能面**与**可借鉴的交互**，以及它们在本机（OpenCode v2）上的问题。
> 结论：**没有现成插件能直接满足需求**（v2 key 位置 + 设置面板 + 顶栏直显），所以自建是合理的；但要借鉴它们的 UX。

---

## 1. 工具清单

| 工具 | 星 | 平台 | 关键能力 | 值得我们借鉴 |
|---|---|---|---|---|
| [slkiser/opencode-quota](https://github.com/slkiser/opencode-quota) | 1041★ | OpenCode TUI 插件 / CLI | 官方 Go 端点；`used`/`remaining`；`runway`；`allWindows`；阈值退出码；toast/重置通知；JSON 导出 | remaining 模式、runway、allWindows、阈值语义、文案 |
| [mryll/claudebar](https://github.com/mryll/claudebar) | 60★ | Waybar + Omarchy | 5h/周窗口 + 倒计时；按模型窗口；额外用量（本月花费/余额/上限）；**pace**；颜色分级 `low/mid/high/critical`；自定义格式；`--json`；纯 Bash | 颜色分级、tooltip gauge、自定义格式（v1 可简化）、失败降级 |
| [othavi0/omarchy-agent-bar](https://github.com/othavi0/omarchy-agent-bar) | 11★ | Omarchy | 每 provider 一个 chip；popup：计划标签 + 主窗口 + 其他窗口；chip 状态（变暗/`!`/`—`）；刷新失败保留上次读数；左键 popup / 中键刷新 / 右键设置；不碰凭据 | chip 状态语义、popup 信息层级、刷新失败处理、鼠标约定 |
| [crmne/omastats](https://github.com/crmne/omastats) | 41★ | Omarchy（本机已装） | 系统监控；模块勾选/排序/样式；ring + 历史曲线；schema 设置页；主题适配 | 设置 UI 结构、RingGauge、HistoryGraph、`persist()` 写法 |
| [mrc04d/omarchy-opencode-go](https://github.com/mrc04d/omarchy-opencode-go) | 2★ | Omarchy | 给内置 `omarchy.agents` 面板加 OpenCode Go tab；官方端点 + 本地 DB；按天/按模型；v1/v2 表适配 | 数据契约设计、agents 面板集成方式；**但它读 `auth.json`，v2 失效** |
| [srsergi0/omarchy-opencode-usage](https://github.com/srsergi0/omarchy-opencode-usage) | 0★ | Omarchy | 顶栏直接显示 `Go · 15%`；官方端点；面板 5h/周/月 | 顶栏直显的形态；但硬编码 $12/$30/$60，且读 `auth.json` |
| [M4Marvin/omarchy-plugin-opencode-go](https://github.com/M4Marvin/omarchy-plugin-opencode-go) | 8★ | Omarchy | OpenCode Go 顶栏 widget | 硬编码 $12/$30/$60；读 `auth.json` |
| [markbus-ai/omarchy-opencode-usage](https://github.com/markbus-ai/omarchy-opencode-usage) | 3★ | Omarchy | 本地 DB 按天/模型 | 没有配额 |
| [lvmiao233/QuotaHub](https://github.com/lvmiao233/QuotaHub) | 23★ | Web / Docker | 多账号、多 provider 面板；接近上限高亮 | 多账号/高亮思路（v1 不做） |
| [Ruinique/opencode-go-dashboard](https://github.com/Ruinique/opencode-go-dashboard) | 25★ | 自托管 Web | 多账号 OpenCode Go 额度；Cookie 仅存服务端 | 多账号（v1 不做） |
| [MeIotCOM/CodingPlanQuota](https://github.com/MeIotCOM/CodingPlanQuota) | 46★ | 移动端 | 5h/周/月额度 + 重置倒计时 | 移动端信息层级 |
| [pinkpixel-dev/quota](https://github.com/pinkpixel-dev/quota) | 29★ | 桌面/VSCode/CLI | 多 provider 用量与余额 | 多 provider 架构（v1 不做） |

---

## 2. 为什么现成 Omarchy 插件在你这台机器上不行

本机是 **OpenCode 2.0.32（v2）**：

| | v1 | v2（本机） |
|---|---|---|
| key | `~/.local/share/opencode/auth.json` | `opencode.db` → `credential` 表 |
| 消息表 | `message` | `session_message`（`model.providerID` 嵌套） |

- `mrc04d` / `srsergi0` / `M4Marvin` 都从 `auth.json` 读 key → 本机该文件**不存在** → 拿不到额度。
- `srsergi0` 还硬编码 $12/$30/$60（DeepSeek V4.1 Flash 的月上限是 $80，Go Plus $160），并读旧 `message` 表。
- `mrc04d` 最接近完整方案（agents 面板 + 官方端点 + 按天/模型），但没有设置面板，且需要改 key 来源才能跑。

→ **我们的差异化**：同时支持 v1/v2、Go/Go Plus、顶栏直显 + 面板设置。

---

## 3. 值得直接采纳的 UX 约定

| 约定 | 来源 | 我们的做法 |
|---|---|---|
| 剩余优先 | opencode-quota | 默认显示 remaining |
| 只显示“最紧窗口” | 我们自己的判断 | `worst` 模式：哪个先撞墙显示哪个 |
| 颜色分级 | claudebar | 正常 / 20% 警告 / 10% 严重（`!`） |
| 状态语义 | Agent Bar | `—` 无数据；降级半透明；刷新失败保留上次读数 |
| 鼠标约定 | Agent Bar | 左键面板、右键设置、中键刷新 |
| 重置倒计时 | 全部 | `约 4h` + 本地绝对时间 |
| 窗口卡片 | omastats | ring + 大号剩余 % + 倒计时 |
| 趋势 | omastats | 每日本地 cost 柱 + 剩余 % 折线 |
| 设置入口 | omastats | 面板内 + schema 的 Setup → Plugins |

## 4. 明确不采纳

| 功能 | 原因 |
|---|---|
| Pace（已用% vs 时间%） | 用户明确不要；增加心智负担 |
| 配额美元换算 | API 只给百分比；本地 cost 口径不一致 |
| 多 provider | v1 范围控制 |
| 多账号 | v1 范围控制 |
| JSON 导出 | 用户暂无需求；等反馈 |
| Waybar | v1 只做 Omarchy |

## 5. 功能矩阵（v1 目标 vs 现成）

| 能力 | 我们 v1 | opencode-quota | claudebar | Agent Bar | mrc04d | srsergi0 |
|---|---|---|---|---|---|---|
| Omarchy 顶栏直显 | ✅ | ❌ | ✅ | ✅ | ❌（icon） | ✅ |
| 官方额度百分比 | ✅ | ✅ | ✅（Claude） | ✅ | ✅ | ✅ |
| OpenCode v2 key | ✅ | ✅ | — | — | ❌ | ❌ |
| 剩余/已用切换 | ✅ | ✅ | — | ✅ | — | — |
| 三窗口 + 倒计时 | ✅ | ✅ | ✅（2） | ✅ | ✅ | ✅ |
| 最紧窗口模式 | ✅ | — | — | — | — | — |
| 面板 + 设置 | ✅ | ✅（TUI） | ✅ | ✅ | ❌ | ❌ |
| 模型明细 | ✅ | ✅（tokens） | ✅（按模型限额） | — | ✅ | — |
| 趋势图 | ✅ | ✅（报告） | — | — | ✅ | — |
| Runway | ✅ | ✅ | — | — | — | — |
| 阈值通知 | ✅ | ✅ | — | — | — | — |
| Go / Go Plus 自适应 | ✅ | ✅ | — | — | — | ❌ 硬编码 |
