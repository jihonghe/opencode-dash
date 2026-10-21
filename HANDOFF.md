# OpenCode Quota — 交接文档（给实现者）

> **2026-10-21 范围变更**：本地用量/模型明细/cost 已移除。插件只使用官方 `/zen/go/v1/usage`（账号级，覆盖所有客户端）；`opencode.db` 仅用于读取 credential key。趋势图已移除；面板改为 Runway 表（Period / Avg / Active）：Avg 含空闲时间，Active 只统计用量上升的区间；样本不足（<3 点或 <1h）或最新样本过期时整块隐藏。`showModelDetail`、`renewOverride` 已删除。


> 交付对象：**ZCode**（长任务 / goal 模式）
> 项目目录：`~/code/opencode-quota`
> 目标：为 **Omarchy（Quattro 4.x）** 开发一个**可发布**的顶栏插件，显示 **OpenCode 订阅（Go / Go Plus）** 的剩余额度。

---

## 0. 先读什么（按顺序）

1. `docs/01-spec.md` —— 完整功能规格（做什么、长什么样）
2. `docs/02-data-sources.md` —— 官方端点、key 位置、DB 查询、口径与坑
3. `docs/03-omarchy-plugin-guide.md` —— 插件结构、manifest、设置、开发/发布流程
4. `docs/04-research.md` —— 同类工具调研与可借鉴的 UX
5. `docs/05-test-plan.md` —— 测试矩阵与验收标准

读完先给用户一份**实现计划**（文件清单 + 每步验收），确认后再写代码。

---

## 1. 一句话

给 Omarchy 顶栏加一个 **OpenCode Quota** widget：直接看到订阅额度还剩多少、什么时候重置；点开有详情面板、Runway 估算和设置；阈值到了会提醒。

## 2. 已决定（不要重新论证）

| 项 | 决定 |
|---|---|
| 顶栏默认 | **worst**：只显示剩余最少的窗口（如 `M 86%`）；可选 `all` / `month` |
| 百分比含义 | **剩余**（remaining）为默认；设置里可切 `used` |
| 阈值 | 剩余 ≤ **20%** 警告、≤ **10%** 严重（带 `!`） |
| 面板 | 三个窗口 + 重置倒计时 + Runway 表（Period / Avg / Active）+ 设置 |
| Runway | 要（百分比斜率估算，不依赖美元） |
| 趋势图 | **不做**（已移除；官方 API 不提供历史） |
| Pace（已用% vs 时间%） | **不做**（用户明确不要，增加心智负担） |
| JSON 导出 | **v1 不做**（等用户反馈） |
| 配额美元换算 | **不做**（API 不给基数，本地 cost 口径不一致，硬换算会误导） |
| 多 provider（Claude/Codex/Zen） | **v1 不做** |
| Waybar 模块 | **v1 不做** |
| 通知 | 插件内实现（`notify-send`），**不装 systemd 单元** |
| UI 语言 | **英文界面**；README 中英双语 |
| 发布标准 | MIT、README、截图、`omarchy plugin validate` 通过 |
| 插件 id | 本地 `local.opencode-quota`；公开 `<GitHub 用户名>.opencode-quota` |
| 计划标签 | `planLabel` 默认 `OpenCode Go`（API 不返回套餐名，可改） |

## 3. 非目标

- 不做余额/充值/账单
- 不读、不存、不打印 API key
- 不修改 OpenCode 数据库（只读）
- 不修改 `/usr/share/omarchy/`（更新会覆盖）
- 不装 systemd timer/unit
- 不做多账号聚合

## 4. 本机规则（必须遵守）

1. **先读机器知识**：`~/.agents/skills/oma-machine/SKILL.md`；按需读 `shell-bar.md`、`shell-plugins.md`、`pitfalls.md`、`verify.md`、`collaboration.md`。
2. **联网必须走代理**：`pcurl` / `pgit` / `pwget`，或 `https_proxy=http://127.0.0.1:10801`。
3. **改本机配置前**：`oma-backup <文件>`；系统级/不可逆操作（sudo、更新、重启、删包、push）先要用户明确授权。
4. **改完 `~/.agents`**：跑 `oma-skill-check`，再 `oma-commit --agent zcode "<一句话>"`；不要问用户要不要提交（push 才问）。
5. **key 安全**：只在进程内读取使用；**绝不**写入文件、日志、提交、错误信息。
6. **不要动** `~/.agents/skills/` 里 `omarchy` / `diagnose-crash`（只读软链）。
7. 代码仓库如果放在 `~/.config/omarchy/plugins/` 下，注意 shell 热重载；开发期用软链或副本，别直接改系统插件目录。

## 5. 工作顺序（里程碑）

| 阶段 | 内容 | 结束条件 |
|---|---|---|
| **M1** 数据层 | `scripts/quota.py`：key、API、DB、缓存、采样、`--json` | 真机返回正确 JSON；无 key/401/断网分类正确；key 不泄漏 |
| **M2** 顶栏 | `BarWidget.qml`：worst/all/month、颜色、tooltip、状态 | 最紧窗口自动切换；阈值变色；`—`/降级正确 |
| **M3** 面板 | `Panel.qml`：三窗口、倒计时、Runway 表 | 打开/关闭正常；与顶栏一致 |
| **M4** 设置 + 通知 | schema、面板设置持久化、阈值通知 | 设置重启后保留；每个阈值每窗口只通知一次 |
| **M5** 发布 | README、截图、LICENSE、validate、tag | `omarchy plugin validate` 通过；别人按 README 能装 |

## 6. 完成定义（DoD）

- `omarchy plugin validate ~/.config/omarchy/plugins/local.opencode-quota` 通过
- `omarchy-shell shell ping` 返回 `ok`，shell 日志无 QML 报错
- 顶栏在 top/bottom/left/right 四个方向、明暗主题下都可读
- 三个窗口的数据与 console（±1% 取整/时间差）一致
- 无 key / 断网 / 401 / 空数据：都有明确状态，不崩溃、不伪造
- 阈值通知：每个窗口每个阈值每次重置只发一次
- 设置：面板与 Setup → Plugins 改的是同一份值；`omarchy restart shell` 后保留
- README 有截图、安装命令、配置表、数据源说明、隐私说明、排障
- MIT LICENSE；manifest `version` 为 `1.0.0`

## 7. 参考资料

**本机（只读，直接读源码）**
- 顶栏基类：`/usr/share/omarchy/shell/Ui/BarWidget.qml`
- 面板基类：`/usr/share/omarchy/shell/Ui/Panel.qml`
- 官方 agents 插件（同目录含 collector 思路）：`/usr/share/omarchy/shell/plugins/agents/`
- omastats（设置 UI、ring、趋势图的现成范例）：`~/.config/omarchy/plugins/crmne.omastats/`
- 顶栏文档：`/usr/share/omarchy/shell/plugins/bar/README.md`
- shell 文档（manifest/schema/IPC）：`/usr/share/omarchy/shell/README.md`
- 本机机器知识：`~/.agents/skills/oma-machine/shell-bar.md`、`shell-plugins.md`

**远程（同类工具）**
- `slkiser/opencode-quota`（1041★）：同一官方端点、runway、used/remaining、导出
- `mryll/claudebar`（60★）：颜色分级、格式自定义、Omarchy + Waybar
- `othavi0/omarchy-agent-bar`（11★）：chip 状态、popup、设置、刷新失败保留上次读数
- `mrc04d/omarchy-opencode-go`（2★）：agents 面板 tab、官方端点、v1/v2 表适配；但读 `auth.json`，v2 失效
- `srsergi0/omarchy-opencode-usage`（0★）：顶栏直接显示；硬编码美元；旧表

**本机事实（验收基准，2026-10-20）**
- Omarchy 4.0.6 Quattro；OpenCode 2.0.32
- 订阅：OpenCode **Go**；订阅月重置 `2026-11-17T14:35:30Z`（本地 11-17 22:35）
- 当前 API：rolling ~2–3%、weekly 20%、monthly 13–14%
- 本机用量：`deepseek-v4.1-flash` $3.85 / 1196 条；`nemotron-3.5-super-vl-free` $0 / 24 条
- key 位置：`~/.local/share/opencode/opencode.db` → `credential` 表（`integration_id=opencode-go`），value 是 `{"type":"api","key":"…"}`
- `~/.local/share/opencode/auth.json` **不存在**（v2 已迁移）

## 8. 两个默认值（用户未反对，按此执行）

1. **英文 UI**（标签短、面向国际受众）；README 中英双语。
2. `planLabel` 默认 `OpenCode Go`，作为面板里的可改标签。

---

## 9. 交付物

```
opencode-quota/
  manifest.json
  BarWidget.qml
  Panel.qml
  Model.js
  scripts/quota.py
  README.md
  LICENSE
  preview.png
  docs/            ← 本交接包（可保留）
  tests/
```

> 实现说明（2026-10-20）：面板组件实际文件名为 `QuotaPanel.qml`，避免与 `qs.Ui.Panel` 基类同名；面板子组件放在 `ui/`。
