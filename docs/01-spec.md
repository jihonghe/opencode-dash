# 01 · 功能规格

> 产品：**OpenCode Quota**（Omarchy 顶栏插件）
> 目标用户：使用 OpenCode Go / Go Plus 的 Omarchy 用户
> 一句话：直接看到订阅额度还剩多少、什么时候重置；点开有详情、趋势、模型用量和设置；阈值到了会提醒。

---

## 1. 定位与边界

**做**
- 顶栏常驻：剩余额度（最紧窗口 / 全部窗口）
- 悬停 tooltip：三个窗口 + 重置倒计时 + 本周期模型用量
- 点击面板：窗口卡片、runway、趋势图、模型明细、设置
- 阈值通知（剩余 20% / 10%）
- 支持 OpenCode v2（DB credential）与 v1（auth.json）
- 自动适配 Go / Go Plus（不硬编码套餐或模型上限）

**不做**
- 余额、充值、账单
- 配额美元换算（API 不给基数）
- Pace（已用 % vs 时间 %）
- JSON 导出（v1）
- 多 provider（Claude / Codex / Zen）
- Waybar 模块
- 多账号聚合

---

## 2. 数据与口径

| 数据 | 来源 | 用途 |
|---|---|---|
| 三个窗口的已用百分比 + 重置时间 | `GET https://opencode.ai/zen/go/v1/usage`（Bearer key） | 顶栏、面板、通知 |
| 按模型用量（消息数 / tokens / cost） | 本地 `opencode.db`（v2 `session_message` / v1 `message`） | 面板明细、趋势 |
| key | v2：DB `credential`；v1：`auth.json` | 仅用于调用端点 |

**口径规则**
- `percent` 是**已用**百分比（0–100），剩余 = 100 − percent
- **百分比是官方口径**（与 console 同源）；本地 cost 只做“模型用量”，**不换算配额美元**
- API 是**账号级聚合**，不按模型；模型维度只有本地数据
- 订阅月以 API 的 `resetsAt` 为准；设置里的 `renewOverride` 仅在 API 失败时兜底

**降级**
| 情况 | 表现 |
|---|---|
| API 失败 / 超时 | 显示上次成功读数 + `更新于 HH:mm` + 降级标记；通知暂停 |
| 401/403 | 面板提示“登录已过期”，顶栏 `—` |
| 没有 key | 面板提示“未登录 OpenCode Go”，顶栏 `—` |
| 响应格式异常 | 同“API 失败”，保留缓存 |
| 无任何数据 | 顶栏 `—` |

缓存最短 60 秒；手动刷新可强制。

---

## 3. 顶栏 widget

### 3.1 显示模式（设置 `barWindows`）

| 值 | 显示 | 说明 |
|---|---|---|
| `worst`（默认） | 剩余最少的窗口，如 `M 86%` | 哪个先撞墙就自动切到哪个 |
| `all` | `5h 97% · 7d 80% · M 86%` | 三个都显示 |
| `month` | `M 86%` | 只看订阅月 |

标签：`5h` / `7d` / `M`（英文短标签）。

### 3.2 颜色与状态

| 状态 | 条件 | 表现 |
|---|---|---|
| 正常 | 剩余 > `warnRemaining`（20） | 健康绿色（明暗自适应） |
| 警告 | 剩余 ≤ 20% | 警示色（amber） |
| 严重 | 剩余 ≤ 10% | 严重色（red）+ 文本带 `!` |
| 降级 | 缓存过期 / API 失败 | 半透明；tooltip 标“缓存于 HH:mm” |
| 无数据 | 无 key / 首次无响应 | `—` |

正常绿色、警告 amber、严重色按明暗背景选择可读色（严重色优先 `bar.urgent`），需在明暗主题下都可读。

### 3.3 交互

| 操作 | 行为 |
|---|---|
| 左键 | 打开 / 关闭面板 |
| 右键 | 打开面板的设置页 |
| 中键 | 立即刷新（可选） |
| 悬停 | 显示 tooltip |

---

## 4. Tooltip

```
OpenCode Go · 剩余
5h    97%    重置 04:08（约 4h）
7d    80%    重置 周一 08:00（约 5d）
月    86%    重置 11-17 22:35（约 26d）
── 本周期本地用量 ──
deepseek-v4.1-flash   $3.85 / 1196 次
nemotron（免费）       $0 / 24 次
更新于 20:35
```

- 重置时间用**本地时区**；同时给相对倒计时
- 模型明细按 cost 降序；免费模型标注 `free`
- 降级时最后一行改为 `缓存于 20:35（API 不可用）`
- 实现说明：百分比数字按状态着色（绿/amber/红），窗口标签保持前景色；因为顶栏共享 tooltip 是单色纯文本，这里使用自定义 QML hover card（`ui/QuotaTooltip.qml`）。

---

## 5. 面板

```
┌ OpenCode Quota                        [刷新] [设置] [×] ┐
│  OpenCode Go（planLabel，可改）                          │
│                                                          │
│  5h   ◔ 97%   重置 04:08（约 4h）      runway: 约 6h     │
│  7d   ◔ 80%   重置 周一 08:00（约 5d） runway: —         │
│  月   ◔ 86%   重置 11-17 22:35（约 26d） runway: 约 12d  │
│                                                          │
│  ── 趋势（7 天 / 本周期） ──────────────────────────      │
│  每日本地 cost 柱状 + 剩余 % 折线                         │
│                                                          │
│  ── 模型明细（本周期） ────────────────────────────       │
│  模型                  消息数   输入/输出/缓存    cost   │
│  deepseek-v4.1-flash    1196    …               $3.85   │
│  nemotron（免费）         24    …                 $0     │
│                                                          │
│  数据源：官方 API · 更新于 20:35                          │
└──────────────────────────────────────────────────────────┘
```

### 5.1 窗口卡片
- 环形或条形显示剩余 %
- 大号剩余 %、重置倒计时 + 绝对时间
- **Runway**：按百分比斜率估算“还能用多久”；取 `min(runway, 距离重置)`；样本不足显示 `—`

### 5.2 趋势
- 每日本地 cost 柱（从 DB 回填，刚装就有数据）
- 剩余 % 折线（从插件运行后开始采样）
- 切换：最近 7 天 / 本周期
- 采样存 `~/.cache/opencode-quota/samples.jsonl`，保留 30 天

### 5.3 模型明细
- 本周期（订阅月）内，按模型聚合：消息数、input/output/reasoning/cache tokens、cost
- 免费模型标注；按 cost 降序
- 空数据时显示“暂无本地用量”

### 5.4 设置（面板内）
与 Setup → Plugins 表单改的是同一份 `shell.json` 内联字段：
- 显示：`barWindows`、`percentMode`、`showModelDetail`
- 阈值：`warnRemaining`、`critRemaining`
- 刷新：`refreshIntervalSec`
- 通知：`notifyEnabled`、`notifyReset`
- Renew 覆盖：`renewOverride`（ISO；空 = 用 API）
- 计划标签：`planLabel`

---

## 6. 设置项（manifest schema）

| key | 类型 | 默认 | 范围 | 说明 |
|---|---|---|---|---|
| `refreshIntervalSec` | integer | 300 | 60–3600 | 刷新间隔 |
| `barWindows` | enum | `worst` | `worst`/`all`/`month` | 顶栏显示 |
| `percentMode` | enum | `remaining` | `remaining`/`used` | 百分比含义 |
| `warnRemaining` | integer | 20 | 1–99 | 警告阈值 |
| `critRemaining` | integer | 10 | 1–99 | 严重阈值 |
| `notifyEnabled` | boolean | true | — | 阈值通知 |
| `notifyReset` | boolean | false | — | 重置时通知 |
| `showModelDetail` | boolean | true | — | 面板模型明细 |
| `renewOverride` | string | `""` | ISO 时间 | 手动 Renew |
| `planLabel` | string | `OpenCode Go` | — | 面板标签 |

设置存储：`~/.config/omarchy/shell.json` 里本 widget 的 entry（**不要**另建配置文件）。

---

## 7. 通知

- 每次刷新检查：剩余 ≤ `warnRemaining` 发一次警告；≤ `critRemaining` 发一次严重
- `notify-send`：警告 normal、严重 critical；标题如 `OpenCode Go · 5h 剩余 18%`，正文带重置时间
- 去重：`窗口 + 级别 + resetsAt`；窗口重置后重新计
- `notifyReset` 开启时，检测到 resetsAt 已过且新周期开始 → “额度已重置”
- 不刷屏；DND 由通知守护进程处理
- 实现位置：插件内（QML 调 `notify-send`），**不装 systemd 单元**

---

## 8. 架构

```
opencode-quota/
  manifest.json          # id、kinds: bar-widget、entryPoints、schema
  BarWidget.qml          # 顶栏
  Panel.qml              # 面板
  Model.js               # 格式化、状态映射、颜色、设置读写辅助
  scripts/quota.py       # 数据层：key、API、DB、缓存、采样、runway
  README.md
  LICENSE
  preview.png
  tests/
```

- QML 不写 HTTP/DB 逻辑：定时或手动调用 `quota.py --json`，只渲染
- 数据层输出稳定 JSON（见 `02-data-sources.md`）
- 缓存/采样：`~/.cache/opencode-quota/state.json`、`samples.jsonl`
- 只读打开 DB（`mode=ro`）

---

## 9. 兼容性与隐私

- Omarchy Quattro 4.x / Quickshell；顶栏四个方向、明暗主题、多显示器
- OpenCode v2 优先；v1 回退（`auth.json` + `message` 表）
- Go / Go Plus 都不需要改代码（只看百分比）
- key 只发给 `opencode.ai`；不收集遥测；不写日志；README 明示
- DB 只读；不修改 OpenCode 任何数据

---

## 10. 发布

- 本地 id：`local.opencode-quota`；公开 id：`<GitHub 用户名>.opencode-quota`
- MIT LICENSE
- README：截图、依赖、安装、配置表、数据源（官方未文档化端点）、隐私、排障
- 发布检查单：`omarchy plugin validate`、明暗主题、四方向、v1/v2、无 key/断网、截图、tag `v1.0.0`
- 曝光：GitHub topic `omarchy-plugin`；`plugins.omarchy.org`；Omarchy 论坛/Discord

---

## 11. 验收（摘要）

1. 顶栏：worst 自动切换；20%/10% 变色；`—`/降级正确
2. 面板：三窗口、倒计时、runway、趋势、模型表；开关正常
3. 设置：面板与 Setup 同步；shell 重启后保留
4. 通知：每窗口每阈值每次重置只发一次；严重用 critical
5. 数据：与 console 的百分比一致（±1% 取整/时间差）；无 key/断网不崩溃
6. 发布：`omarchy plugin validate` 通过；README 可复现安装
