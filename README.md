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

- Bar display: `worst` (least remaining), `all` windows, or `month` only.
- Remaining percentage by default; switch to used in the settings.
- Status colors: healthy green, remaining ≤ 20% amber, ≤ 10% red with `!`.
- Only the percentage is colored; the window label and `%` stay in the
  foreground.
- Panel: three quota windows, reset times/countdowns, runway, and a
  remaining-percentage trend.
- Trend ranges: `24h`, `7d`, and `Cycle`; three lines for 5h / 7d / M.
- Threshold notifications through `notify-send`, deduplicated per window,
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
| `notifyReset` | boolean | `false` | Notify when a window starts over |
| `planLabel` | string | `OpenCode Go` | Label shown in the panel and notifications |

The bar text uses short labels: `5h` (rolling), `7d` (weekly), and `M`
(subscription month). In a vertical bar the widget shows the worst window as
two lines (`7d` / `79%`) to stay readable.

### Trend and runway

The official endpoint only returns the **current** percentages. The trend and
runway are built from samples the plugin records each time it refreshes:

- At least **3 samples** spanning **1 hour** are required.
- Until then, the trend section and runway values are **not displayed at all**
  — no `—` placeholders and no "collecting samples" noise.
- Runway is a slope estimate capped at the next reset. If usage is flat or a
  window just reset, that window has no runway until enough new samples
  accumulate.
- The trend is built from official readings, so it also covers every client.

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
- **No trend or runway**: wait until the plugin has at least 3 samples over
  1 hour. They appear automatically; nothing is shown before that.
- **No notifications**: check `notify-send`, your notification daemon, and
  Do Not Disturb. Alerts are deduplicated per window/level/reset.
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
`report-no-key.json`, `report-auth-expired.json`, and
`report-not-ready.json` (trend/runway hidden). Remove the setting when done.

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

- 顶栏显示：`worst`（剩余最少）、`all`（三个窗口）、`month`（只看订阅月）。
- 默认显示剩余百分比，可在设置里切换为已用。
- 状态颜色：健康绿色、剩余 ≤ 20% amber、≤ 10% 红色并带 `!`。
- 只有百分比本身着色，窗口标签和 `%` 保持前景色。
- 面板：三个额度窗口、重置时间和倒计时、runway、剩余百分比趋势。
- 趋势范围：`24h` / `7d` / `Cycle`，画 5h / 7d / M 三条线。
- 阈值通知由 `notify-send` 发送；按“窗口 + 级别 + 重置时间”去重。
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
| `notifyReset` | boolean | `false` | 窗口重置时通知 |
| `planLabel` | string | `OpenCode Go` | 面板和通知里的套餐标签 |

顶栏短标签：`5h`（滚动窗口）、`7d`（自然周）、`M`（订阅月）。垂直顶栏只显示
最紧窗口，分两行显示（`7d` / `79%`），避免文字被截断。

### 趋势与 Runway

官方端点只返回**当前**百分比。趋势和 runway 来自插件每次刷新时记录的采样：

- 至少需要 **3 个样本**、跨度至少 **1 小时**。
- 在此之前，趋势区和 runway 值**完全不显示**——没有 `—` 占位，也没有
  “Collecting samples…” 之类的提示。
- Runway 是百分比斜率的估算，并封顶到下一次重置；如果用量平稳或窗口刚重置，该
  窗口暂时没有 runway，直到积累足够的新样本。
- 趋势来自官方读数，因此同样覆盖所有客户端。

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
- **没有趋势或 runway**：等插件积累至少 3 个样本、跨度 1 小时，它们会自动出现；
  在此之前不显示任何占位内容。
- **没有通知**：检查 `notify-send`、通知守护进程和勿扰模式。通知按窗口/级别/
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
`report-auth-expired.json`、`report-not-ready.json`（趋势/runway 隐藏）。用完请删除。

### 致谢与许可

- 设置持久化参考了 [crmne/omastats](https://github.com/crmne/omastats)（MIT）。
- 端点行为和交互参考了
  [slkiser/opencode-quota](https://github.com/slkiser/opencode-quota)、
  [mryll/claudebar](https://github.com/mryll/claudebar)、
  [othavi0/omarchy-agent-bar](https://github.com/othavi0/omarchy-agent-bar)。
- MIT License，见 [LICENSE](LICENSE)。
