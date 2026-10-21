# 01 · 功能规格

> **2026-10-21 范围变更**：本地用量/模型明细/cost 已移除。插件只使用官方 `/zen/go/v1/usage`（账号级，覆盖所有客户端）；`opencode.db` 仅用于读取 credential key。趋势图已移除；面板改为 Runway 表（Period / Avg pace / Lasts）：只保留按实际时间、含空闲的 Avg 估算；样本不足（<3 点或 <1h）或最新样本过期时整块隐藏。`showModelDetail`、`renewOverride` 已删除。


> 产品：**OpenCode Quota**（Omarchy 顶栏插件）
> 目标用户：使用 OpenCode Go / Go Plus 的 Omarchy 用户
> 一句话：直接看到订阅额度还剩多少、什么时候重置；点开有详情、Runway 估算和设置；阈值到了会提醒。

---

## 1. 定位与边界

**做**
- 顶栏常驻：剩余额度（最紧窗口 / 全部窗口）
- 悬停 tooltip：三个窗口 + 重置倒计时 + Runway（Avg pace / Lasts）
- 点击面板：窗口卡片、Runway 表、设置
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
- 本地用量 / 模型明细 / cost / 趋势图（已移除；无法覆盖所有客户端）

---

## 2. 数据与口径

| 数据 | 来源 | 用途 |
|---|---|---|
| 三个窗口的已用百分比 + 重置时间 | `GET https://opencode.ai/zen/go/v1/usage`（Bearer key） | 顶栏、面板、通知 |
| 每次刷新的百分比采样 | `~/.cache/opencode-quota/samples.jsonl` | Runway 估算 |
| key | v2：DB `credential`；v1：`auth.json` | 仅用于调用端点 |

**口径规则**
- `percent` 是**已用**百分比（0–100），剩余 = 100 − percent
- **百分比是官方口径**（与 console 同源）；不读取本地 cost，也不换算配额美元
- API 是**账号级聚合**，覆盖所有客户端，不按模型
- 订阅月以 API 的 `monthly.resetsAt` 为准

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
OpenCode Go · remaining                    updated 14:36
Period    Left   Resets in   Avg pace          Lasts
Rolling    93%   2h 37m         0.2%/h      ≥ 2h 37m
Weekly     69%   4d 17h        13.2%/day    ≥ 4d 17h
Monthly    81%   27d 7h         6.2%/day    ~12d 18h
Official API · estimates from 15h 17m of samples
```

- `Resets in` 只显示倒计时；面板显示 `Resets in <倒计时> (<绝对时间>)`
- 百分比数字按状态着色（绿/amber/红），周期标签保持前景色
- Tooltip 用 `Avg pace` / `Lasts` 两列；颜色只加在 `Lasts` 上
- 降级时底部改为 `cached at HH:mm (API unavailable)`
- 实现说明：顶栏共享 tooltip 是单色纯文本，这里使用自定义 QML hover card
  （`ui/QuotaTooltip.qml`）

---

## 5. 面板

```
┌ OpenCode Quota                        [刷新] [设置] [×] ┐
│  OpenCode Go                          updated 14:36   │
│                                                        │
│  ◔ 93%  Rolling   Resets in 2h 37m (17:13)            │
│  ◔ 69%  Weekly    Resets in 4d 17h (Mon 08:00)        │
│  ◔ 81%  Monthly   Resets in 27d 7h (11-17 22:35)      │
│                                                        │
│  Runway                                                │
│  Period      Avg pace              Lasts               │
│  Rolling       0.2%/h             ≥ 2h 37m             │
│  Weekly       13.2%/day           ≥ 4d 17h             │
│  Monthly       6.2%/day           ~12d 18h             │
│  Avg includes idle · ≥ lasts until reset               │
│  ~ runs out earlier                                    │
│  Based on official API samples · 15h 17m · 265 points  │
│  Official usage API · account-wide, all clients        │
└────────────────────────────────────────────────────────┘
```

### 5.1 窗口卡片
- 环形显示剩余 %
- 大号剩余 %、重置倒计时 + 绝对时间
- 倒计时与 `Resets in` 使用同一个值，并按周期上限钳制

### 5.2 Runway 表
- 三列：`Period | Avg pace | Lasts`；速度与预计时长分列，时长右对齐并着色
- **Avg**：当前周期内所有采样的最小二乘趋势，使用实际时间（含空闲）
- 时长：`≥ <重置倒计时>` 能撑到重置；`~<时长>` 会在重置前用完；`0m` 已空；
  `Idle` 无消耗
- 样本要求：≥3 点、跨度 ≥1h、最新样本足够新；否则整块隐藏
- 采样存 `~/.cache/opencode-quota/samples.jsonl`，保留 30 天
- 颜色只加在预计时长上；百分比颜色仍表达当前剩余

### 5.3 设置（面板内）
与 Setup → Plugins 表单改的是同一份 `shell.json` 内联字段：
- 显示：`barWindows`、`percentMode`
- 阈值：`warnRemaining`、`critRemaining`
- 刷新：`refreshIntervalSec`
- 通知：`notifyEnabled`、`notifyReset`
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
2. 面板：三窗口、倒计时、Runway 表（Period / Avg pace / Lasts）；开关正常
3. 设置：面板与 Setup 同步；shell 重启后保留
4. 通知：每窗口每阈值每次重置只发一次；严重用 critical
5. 数据：与 console 的百分比一致（±1% 取整/时间差）；无 key/断网不崩溃
6. 发布：`omarchy plugin validate` 通过；README 可复现安装
