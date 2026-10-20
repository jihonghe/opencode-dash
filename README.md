# OpenCode Quota

[English](#english) · [中文](#中文)

| Dark theme | Light theme |
|---|---|
| ![Dark theme](preview.png) | ![Light theme](preview-light.png) |

## English

OpenCode Quota is an Omarchy bar widget for the **OpenCode Go / Go Plus**
subscription. It reads the official usage endpoint, so the percentages include
**every client** that uses the subscription — the OpenCode CLI/TUI, ZCode, and
any future agent.

### Features

- Bar display: `worst` (least remaining), `all` periods, or `month` only.
- Remaining percentage by default; switch to used in the settings.
- Status colors: healthy green, remaining ≤ 20% amber, ≤ 10% red with `!`.
- Only the percentage is colored; the period label and `%` stay in the
  foreground.
- Panel: three quota periods, reset times/countdowns, and a Runway table with
  burn rate, runway, and warn/crit ETAs.
- Threshold notifications through `notify-send`, deduplicated per period,
  level, and reset time.
- Settings in the panel and in Setup → Plugins edit the same `shell.json`
  fields.
- Light and dark themes; top, bottom, left, and right bars.
- Official account-level data only; no local agent logs, no model/cost
  estimates, no telemetry.

### Requirements

- Omarchy Quattro 4.x (tested on 4.0.6).
- Python 3.10 or newer (standard library only).
- `notify-send` from libnotify, for notifications (optional).
- OpenCode signed in to OpenCode Go or Go Plus.

### Install

```bash
omarchy plugin add https://github.com/jihonghe/opencode-quota --enable
omarchy restart shell
```

If the widget is installed but not in the bar yet:

```bash
omarchy plugin enable jihonghe.opencode-quota
```

Move it with `omarchy bar move jihonghe.opencode-quota --section right`, or
drag it in the bar. Update and remove with:

```bash
omarchy plugin update jihonghe.opencode-quota
omarchy plugin remove jihonghe.opencode-quota
```

### Configuration

Settings live inline in `~/.config/omarchy/shell.json` under this widget's
layout entry. The panel's settings page and **Setup → Plugins** edit the same
fields.

| Key | Type | Default | Description |
|---|---|---|---|
| `refreshIntervalSec` | integer | `300` | Refresh interval, 60–3600 seconds |
| `barWindows` | enum | `worst` | `worst`, `all`, or `month` |
| `percentMode` | enum | `remaining` | `remaining` or `used` |
| `warnRemaining` | integer | `20` | Warn below this remaining percentage |
| `critRemaining` | integer | `10` | Critical below this remaining percentage |
| `notifyEnabled` | boolean | `true` | Threshold notifications |
| `notifyReset` | boolean | `false` | Notify when a period resets |
| `planLabel` | string | `OpenCode Go` | Label shown in the panel and notifications |

The bar uses the official period names: `Rolling`, `Weekly`, and `Monthly`.
In a vertical bar it uses the short aliases `5h`, `7d`, and `M`, with the
worst period on two lines (`7d` / `79%`), to stay readable.

### Runway

The official endpoint only returns the **current** percentages. Runway is built
from samples the plugin records each time it refreshes:

- At least **3 samples** spanning **1 hour** are required, and the latest
  sample must be reasonably fresh. Until then, the Runway table is **not
  displayed at all** — no placeholders.
- `Burn`: average percentage points per hour (5h) or per day (7d / M).
- `Runway`: time until the period is exhausted. `Lasts until reset` means the
  current burn rate will not exhaust it before the period resets.
- `Warn` / `Crit`: time until the period reaches the configured remaining
  thresholds. `now` means it is already below, `after reset` means it will not
  reach the threshold before the period resets.
- The footer shows the sample basis, e.g.
  `Based on official API samples · 5h 10m · 106 points`.
- If usage is flat or a period just reset, that period has no estimate until
  enough new samples accumulate. The panel hides the whole table when no period
  has a usable estimate.
- The estimates use official readings, so they cover every client.
- Runway colors:
  - **Green**: remaining is healthy and the current burn lasts until reset.
  - **Amber**: remaining is at or below the warn threshold, or the current
    burn is projected to exhaust the period before reset.
  - **Red**: remaining is at or below the critical threshold, or the period is
    empty.
- The percentage color reflects **current remaining**; the Runway color
  reflects the **forecast**. They can differ: a green percentage with an amber
  runway means there is still quota, but the current burn will use it before
  the period resets.
- If a period has no consumption at all (a flat burn rate), the table shows
  `0.0%/h`, `Lasts until reset`, and `after reset` instead of blank cells.
  Insufficient sample history is still hidden/blank.
- In the tooltip, `Resets in` shows only the countdown (`2m`, `5d 2h`); the
  panel shows both the absolute reset time and the countdown. The `Runway`
  cell also shows the burn rate, and the footer shows the sample span.

### Data sources and privacy

- Quota percentages come from
  `GET https://opencode.ai/zen/go/v1/usage` with a Bearer token. This endpoint
  is official but not documented; other OpenCode tools use it as well.
- The key is read from the v2 `credential` table in
  `~/.local/share/opencode/opencode.db` (`integration_id = 'opencode-go'`), with
  `~/.local/share/opencode/auth.json` as the v1 fallback.
- The database is opened with `mode=ro`, and only the `credential` table is
  read. No session, message, model, or cost data is read from OpenCode.
- The key is kept in memory only. It is never written to a file, cache, log,
  command line, or error message. The only host that receives it is
  `opencode.ai`.
- Cache files live in `~/.cache/opencode-quota/` and contain percentages,
  timestamps, and API samples only.
- Standard `https_proxy` / `HTTPS_PROXY` environment variables are honored;
  no proxy is configured by the plugin itself.
- No telemetry and no other network destinations.

### How it works

`BarWidget.qml` periodically runs `python3 scripts/quota.py --json`. The
script reads the key, calls the usage endpoint, appends a sample, computes
runway, and returns one JSON document. QML only renders it. A 60-second cache
and a file lock keep multiple bar instances from duplicating API calls; manual
refresh (`middle click`, the panel button, or `r` in the panel) bypasses the
cache. Notifications are sent with `notify-send`; no systemd unit is installed.

### Troubleshooting

- **Bar shows `—`**: no credentials, or the sign-in expired. Run OpenCode and
  sign in to OpenCode Go.
- **Values look stale**: the API is unreachable; the last successful reading
  is shown dimmed. The panel footer says when it was cached.
- **No Runway table**: wait until the plugin has at least 3 samples over
  1 hour with a fresh latest sample. It appears automatically; nothing is
  shown before that.
- **No notifications**: check `notify-send`, your notification daemon, and
  Do Not Disturb. Alerts are deduplicated per period/level/reset.
- **Check the data layer manually**:
  `python3 scripts/quota.py --json --force | python3 -m json.tool`
- **Logs**: `journalctl --user -b --no-pager | grep -i opencode-quota`
- After installing or updating, run `omarchy restart shell` once.

### Development

```bash
# Link the working tree instead of cloning
ln -sfn "$PWD" ~/.config/omarchy/plugins/jihonghe.opencode-quota
omarchy-shell shell rescanPlugins
omarchy plugin enable jihonghe.opencode-quota

# Tests (no network or real key required)
python3 -m unittest discover -s tests -v
tests/run-model-test.sh

# Manifest check
omarchy plugin validate .
```

For UI state tests, add `"debugFixture": "/path/to/tests/fixtures/report-stale.json"`
to the widget's `shell.json` entry. The script then returns that fixture
instead of real data. Available fixtures: `report-stale.json`,
`report-no-key.json`, `report-auth-expired.json`, `report-not-ready.json`
(Runway table hidden), and `report-idle.json` (zero burn / idle period).
Remove the setting when done.

### Credits and license

- Settings persistence follows the pattern from
  [crmne/omastats](https://github.com/crmne/omastats) (MIT).
- Endpoint behavior and UX were informed by
  [slkiser/opencode-quota](https://github.com/slkiser/opencode-quota),
  [mryll/claudebar](https://github.com/mryll/claudebar), and
  [othavi0/omarchy-agent-bar](https://github.com/othavi0/omarchy-agent-bar).
- Licensed under the MIT License; see [LICENSE](LICENSE).

---

## 中文

OpenCode Quota 是一个显示 **OpenCode Go / Go Plus** 订阅额度的 Omarchy 顶栏插件。
它直接读取官方 usage 端点，所以百分比覆盖**所有使用该订阅的客户端**——OpenCode
CLI/TUI、ZCode，以及未来任何 Agent。

### 功能

- 顶栏显示：`worst`（剩余最少）、`all`（三个周期）、`month`（只看订阅月）。
- 默认显示剩余百分比，可在设置里切换为已用。
- 状态颜色：健康绿色、剩余 ≤ 20% amber、≤ 10% 红色并带 `!`。
- 只有百分比本身着色，周期标签和 `%` 保持前景色。
- 面板：三个额度周期、重置时间和倒计时，以及包含 burn rate、runway 和
  警告/严重 ETA 的 Runway 表。
- 阈值通知由 `notify-send` 发送；按“周期 + 级别 + 重置时间”去重。
- 面板设置页和 Setup → Plugins 修改同一份 `shell.json` 字段。
- 明暗主题、top/bottom/left/right 四个方向的顶栏。
- 只使用官方账号级数据；不读本地 Agent 日志，不做模型/cost 估算，无遥测。

### 依赖

- Omarchy Quattro 4.x（在 4.0.6 上测试）。
- Python 3.10+（只用标准库）。
- `notify-send`（libnotify），用于通知，可选。
- OpenCode 已登录 OpenCode Go 或 Go Plus。

### 安装

```bash
omarchy plugin add https://github.com/jihonghe/opencode-quota --enable
omarchy restart shell
```

如果插件已安装但没出现在顶栏：

```bash
omarchy plugin enable jihonghe.opencode-quota
```

用 `omarchy bar move jihonghe.opencode-quota --section right` 移动位置，或在顶栏上
直接拖动。更新和卸载：

```bash
omarchy plugin update jihonghe.opencode-quota
omarchy plugin remove jihonghe.opencode-quota
```

### 配置

设置保存在 `~/.config/omarchy/shell.json` 中本 widget 的 layout entry 里。面板设置页
和 **Setup → Plugins** 修改的是同一份字段。

| 键 | 类型 | 默认 | 说明 |
|---|---|---|---|
| `refreshIntervalSec` | integer | `300` | 刷新间隔，60–3600 秒 |
| `barWindows` | enum | `worst` | `worst` / `all` / `month` |
| `percentMode` | enum | `remaining` | `remaining` / `used` |
| `warnRemaining` | integer | `20` | 剩余低于此百分比时警告 |
| `critRemaining` | integer | `10` | 剩余低于此百分比时严重警告 |
| `notifyEnabled` | boolean | `true` | 阈值通知 |
| `notifyReset` | boolean | `false` | 周期重置时通知 |
| `planLabel` | string | `OpenCode Go` | 面板和通知里的套餐标签 |

顶栏使用官方周期名：`Rolling` / `Weekly` / `Monthly`。垂直顶栏为节省宽度使用短标签
`5h` / `7d` / `M`，并分两行显示最紧周期（`7d` / `79%`）。

### Runway

官方端点只返回**当前**百分比。Runway 来自插件每次刷新时记录的采样：

- 至少需要 **3 个样本**、跨度至少 **1 小时**，且最新样本不能太旧。在此之前，
  Runway 表**完全不显示**——没有任何占位内容。
- `Burn`：平均消耗速度；5h 用 `%/h`，7d / M 用 `%/day`。
- `Runway`：额度耗尽时间。`Lasts until reset` 表示按当前速度不会在重置前用完。
- `Warn` / `Crit`：距离进入设置里剩余阈值的时间。`now` 表示已经在阈值下，
  `after reset` 表示重置前不会到达该阈值。
- 底部显示样本依据，例如
  `Based on official API samples · 5h 10m · 106 points`。
- 如果用量平稳或周期刚重置，该周期暂时没有估算；所有周期都没有可用估算时，
  整张表隐藏。
- 估算来自官方读数，因此同样覆盖所有客户端。
- Runway 颜色：
  - **绿色**：剩余健康，且按当前速度能撑到重置。
  - **amber**：剩余已到/低于警告阈值，或按当前速度会在重置前耗尽。
  - **红色**：剩余已到/低于严重阈值，或周期已经为空。
- 百分比颜色表达**当前剩余**，Runway 颜色表达**预测**。两者可以不同：绿色百分比 +
  amber runway 表示“还剩不少，但当前速度会在重置前用完”。
- 如果某个周期完全没有消耗（burn rate 为 0），表格显示 `0.0%/h`、
  `Lasts until reset`、`after reset`，而不是空白；样本历史不足时仍然隐藏/留空。
- Tooltip 的 `Resets in` 列只显示倒计时（`2m`、`5d 2h`）；面板同时显示绝对重置
  时间和倒计时。`Runway` 单元格附带 burn rate，底部显示采样跨度。

### 数据源与隐私

- 额度百分比来自 `GET https://opencode.ai/zen/go/v1/usage`，使用 Bearer token。
  该端点是官方的但未文档化，其他 OpenCode 工具也在使用。
- key 优先从 `~/.local/share/opencode/opencode.db` 的 v2 `credential` 表读取
  （`integration_id = 'opencode-go'`），回退到
  `~/.local/share/opencode/auth.json`（v1）。
- 数据库以 `mode=ro` 只读打开，只读取 `credential` 表；不读取 OpenCode 的 session、
  message、模型或 cost 数据。
- key 只在内存中使用：不写文件、不写缓存、不写日志、不进命令行、不进错误信息。
  唯一接收 key 的地址是 `opencode.ai`。
- 缓存位于 `~/.cache/opencode-quota/`，只包含百分比、时间和 API 采样。
- 尊重标准 `https_proxy` / `HTTPS_PROXY` 环境变量；插件本身不硬编码代理。
- 无遥测，不访问其他网络地址。

### 工作原理

`BarWidget.qml` 定时运行 `python3 scripts/quota.py --json`。脚本读取 key、调用额度
端点、写入采样、计算 runway，最后输出一份 JSON；QML 只负责渲染。60 秒缓存和文件
锁避免多显示器重复请求；手动刷新（中键、面板按钮或面板内按 `r`）会绕过缓存。
通知直接调用 `notify-send`，不安装 systemd 单元。

### 排障

- **顶栏显示 `—`**：没有凭据或登录已过期。运行 OpenCode 并重新登录 OpenCode Go。
- **数值看起来是旧的**：API 不可达，显示上次成功读数并变暗；面板底部会标注缓存
  时间。
- **没有 Runway 表**：等插件积累至少 3 个样本、跨度 1 小时，且最新样本足够新；
  满足后会自动出现，在此之前不显示任何占位内容。
- **没有通知**：检查 `notify-send`、通知守护进程和勿扰模式。通知按周期/级别/
  重置时间去重。
- **手动检查数据层**：
  `python3 scripts/quota.py --json --force | python3 -m json.tool`
- **日志**：`journalctl --user -b --no-pager | grep -i opencode-quota`
- 安装或更新后执行一次 `omarchy restart shell`。

### 开发

```bash
# 用软链代替 clone
ln -sfn "$PWD" ~/.config/omarchy/plugins/jihonghe.opencode-quota
omarchy-shell shell rescanPlugins
omarchy plugin enable jihonghe.opencode-quota

# 测试（不需要网络或真实 key）
python3 -m unittest discover -s tests -v
tests/run-model-test.sh

# manifest 校验
omarchy plugin validate .
```

调试界面状态时，可以在 widget 的 `shell.json` entry 里加
`"debugFixture": "/path/to/tests/fixtures/report-stale.json"`，脚本会直接返回该
fixture。可用 fixture：`report-stale.json`、`report-no-key.json`、
`report-auth-expired.json`、`report-not-ready.json`（Runway 表隐藏）。用完请删除。

### 致谢与许可

- 设置持久化参考了 [crmne/omastats](https://github.com/crmne/omastats)（MIT）。
- 端点行为和交互参考了
  [slkiser/opencode-quota](https://github.com/slkiser/opencode-quota)、
  [mryll/claudebar](https://github.com/mryll/claudebar)、
  [othavi0/omarchy-agent-bar](https://github.com/othavi0/omarchy-agent-bar)。
- MIT License，见 [LICENSE](LICENSE)。
