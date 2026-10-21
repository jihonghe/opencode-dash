# 03 · Omarchy 插件开发指南（本项目相关部分）

> 目标：让实现者不用重新摸索 Omarchy 的插件机制。所有命令都在本机验证过（Omarchy 4.0.6 / Quattro）。

---

## 1. 插件是什么

一个插件 = 一个 **git 仓库**，根目录有 `manifest.json`；安装时克隆到：

```
~/.config/omarchy/plugins/<plugin-id>/
```

插件种类（`manifest.kinds`）：

| kind | 用途 |
|---|---|
| `bar-widget` | 顶栏组件（本项目） |
| `service` | 常驻无 UI 单例 |
| `panel` | 浮动面板（OSD 等） |
| `overlay` | 全屏覆盖层 |
| `menu` | 菜单 |
| `bar` | 整个顶栏的替代品 |

本项目只需要 `bar-widget`；**不要**加 `service`（通知在 widget 内做，避免常驻单例复杂性）。

---

## 2. manifest.json（最小可用）

```json
{
  "schemaVersion": 1,
  "id": "local.opencode-quota",
  "name": "OpenCode Quota",
  "version": "0.1.0",
  "author": "…",
  "license": "MIT",
  "description": "OpenCode subscription quota in the Omarchy bar: remaining percentages, reset countdowns, and runway projections.",
  "kinds": ["bar-widget"],
  "entryPoints": { "barWidget": "BarWidget.qml" },
  "barWidget": {
    "displayName": "OpenCode Quota",
    "description": "OpenCode Go / Go Plus usage and remaining quota.",
    "category": "AI",
    "aliases": ["opencode", "quota", "usage", "go"],
    "allowMultiple": false,
    "defaultSection": "right",
    "defaults": {
      "refreshIntervalSec": 300,
      "barWindows": "worst",
      "percentMode": "remaining",
      "warnRemaining": 20,
      "critRemaining": 10,
      "notifyEnabled": true,
      "notifyReset": false,
      "planLabel": "OpenCode Go"
    },
    "schema": [
      { "key": "refreshIntervalSec", "type": "integer", "label": "Refresh interval (seconds)", "min": 60, "max": 3600, "step": 60, "defaultValue": 300 },
      { "key": "barWindows", "type": "enum", "label": "Bar display", "options": ["worst", "all", "month"], "defaultValue": "worst" },
      { "key": "percentMode", "type": "enum", "label": "Percent meaning", "options": ["remaining", "used"], "defaultValue": "remaining" },
      { "key": "warnRemaining", "type": "integer", "label": "Warn below remaining %", "min": 1, "max": 99, "defaultValue": 20 },
      { "key": "critRemaining", "type": "integer", "label": "Critical below remaining %", "min": 1, "max": 99, "defaultValue": 10 },
      { "key": "notifyEnabled", "type": "boolean", "label": "Notify on thresholds", "defaultValue": true },
      { "key": "notifyReset", "type": "boolean", "label": "Notify on reset", "defaultValue": false },
      { "key": "planLabel", "type": "enum", "label": "Plan", "options": ["OpenCode Go", "OpenCode Go Plus"], "defaultValue": "OpenCode Go" }
    ]
  }
}
```

**schema 类型**（本机实测支持）：`boolean`、`enum`、`integer`、`path`、`string`。
设置项会自动出现在 **Setup → Plugins** 的通用表单里；面板里也应能改同一组字段。

---

## 3. 设置怎么存

- 设置是 `~/.config/omarchy/shell.json` 里**本 widget 的 entry 内联字段**（没有单独的 config 文件）
- 例：`{"id":"local.opencode-quota","barWindows":"worst","warnRemaining":20}`
- 不要建 `~/.config/opencode-quota/config.json`；那会绕开 Setup UI 和热重载

### 从 QML 写设置

本机 omastats 的做法（推荐参考）：

- 读：`Model.savedBarSettings(barConfig, moduleName, locateSelf())`
- 写：`bar.shell.pluginRegistry.setBarWidget(...)`
- `locateSelf()` 通过 `bar.moduleSlots` / `bar.layoutEntries` 定位自己
- 写后立即更新本地 `settings`，并挂 `pendingSettings` 防 shell 回灌旧值

参考实现：`~/.config/omarchy/plugins/crmne.omastats/OmaStatsWidget.qml` 第 174–240 行；`Model.js` 的 `savedBarSettings`。

> 简化方案（v1 可用）：面板调用 `bar.run("omarchy bar set local.opencode-quota warnRemaining 15")`。
> 但它会走 CLI/IPC，错误处理不如 registry API；**推荐 registry**。

---

## 4. 顶栏 widget 写法

基类：`/usr/share/omarchy/shell/Ui/BarWidget.qml`

注入属性：
- `bar`：顶栏宿主（`barForeground`、`fontFamily`、`run()`、`showTooltip()`、`hideTooltip()`）
- `moduleName`：本 widget 的 id
- `settings`：本 entry 的内联设置
- `vertical`、`barSize`
- `setting(name, fallback)`：读设置

最小骨架：

```qml
import QtQuick
import qs.Commons
import qs.Ui

BarWidget {
  id: root
  moduleName: "local.opencode-quota"

  readonly property string text: "M 86%"

  implicitWidth: label.implicitWidth + Style.space(16)
  implicitHeight: barSize

  Text {
    id: label
    anchors.centerIn: parent
    text: root.text
    color: root.bar ? root.bar.barForeground : Commons.Color.foreground
    font.family: root.bar ? root.bar.fontFamily : Style.font.family
    font.pixelSize: Style.font.body
  }

  MouseArea {
    anchors.fill: parent
    hoverEnabled: true
    acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
    cursorShape: Qt.PointingHandCursor
    onClicked: function(mouse) {
      if (mouse.button === Qt.LeftButton) root.togglePanel()
      else if (mouse.button === Qt.RightButton) root.openSettings()
      else root.refreshNow()
    }
    onEntered: if (root.bar) root.bar.showTooltip(root, root.tooltipText)
    onExited: if (root.bar) root.bar.hideTooltip(root)
  }
}
```

**要点**
- tooltip 用 `bar.showTooltip(root, text)` / `bar.hideTooltip(root)`（参考 `plugins/bar/widgets/ActiveWindow.qml`）
- 明暗主题都用 `bar.barForeground` / `Commons.Color`，不要写死颜色
- 垂直顶栏要单独排版（文本可堆叠）
- `allowMultiple: false`，避免多实例重复刷新

---

## 5. 面板写法

基类：`/usr/share/omarchy/shell/Ui/Panel.qml`（提供 `open()` / `close()`；参考 `plugins/agents/Panel.qml`）

结构建议：
- 头部：标题 + 刷新 + 设置 + 关闭
- 三个窗口卡片（`RingGauge` 或自绘进度条）
- Runway 表（`Period / Avg pace / Lasts`）
- 设置页（与 schema 字段同名）

面板打开方式：`root.panel.open()`；Esc / 点击外部关闭。

**参考**：
- `~/.config/omarchy/plugins/crmne.omastats/ui/`（SettingsPage、RingGauge、HistoryGraph、StatRow）
- `/usr/share/omarchy/shell/plugins/agents/Panel.qml`（多 provider 面板）

不要照抄整份代码；按 MIT 许可借鉴思路，必要时在 README 致谢。

---

## 6. 开发循环

```bash
# 1) 放到插件目录（开发期可用软链；注意热重载）
ln -sfn ~/code/opencode-quota ~/.config/omarchy/plugins/local.opencode-quota

# 2) 让 shell 发现/重载
omarchy-shell shell rescanPlugins
omarchy-shell shell ping          # 应返回 ok

# 3) 校验 manifest
omarchy plugin validate ~/.config/omarchy/plugins/local.opencode-quota

# 4) 看状态
omarchy plugin list
omarchy-shell shell listPlugins

# 5) 重启 shell（改 QML 结构后）
omarchy restart shell
```

- 保存 `~/.config/omarchy/plugins/` 下的文件会自动重载
- 失败时看 shell 日志（`journalctl --user -u omarchy-shell` 或终端输出）
- **不要**直接改 `/usr/share/omarchy/shell/plugins/`（更新会覆盖）

---

## 7. 发布

1. 仓库根目录放 `manifest.json` + 代码 + README + LICENSE
2. id 用 `<你的 GitHub 用户名>.opencode-quota`（本地开发可用 `local.opencode-quota`，发布前改）
3. README 必含：截图、依赖、安装命令、配置表、数据源、隐私、排障
4. 安装：
   ```bash
   omarchy plugin add https://github.com/<user>/opencode-quota --enable
   ```
5. 更新：`omarchy plugin update <id>`（fast-forward pull）
6. 校验：`omarchy plugin validate <目录>`
7. 曝光：GitHub topic `omarchy-plugin`；`plugins.omarchy.org`（按其页面说明提交）；Omarchy 论坛/Discord
8. 版本：manifest `version` 用 semver；打 tag；Release notes

**发布检查单**
- [ ] README 有截图和安装命令
- [ ] `omarchy plugin validate` 通过
- [ ] 明/暗主题、top/bottom/left/right、垂直顶栏
- [ ] 无 key / 断网 / 401 / 空数据
- [ ] 设置持久化（重启 shell）
- [ ] 通知去重
- [ ] LICENSE（MIT）
- [ ] 仓库根有 manifest，无凭据/缓存文件

---

## 8. 坑（本机踩过）

- `shell.json` **不深合并**：自定义过就以你的文件为准
- 第三方 QML 跑在 `omarchy-shell` 进程里、有用户权限；只装可信代码
- `keepLoaded` 的 service 改动要重启 shell 才生效
- 顶栏布局没有“查询” IPC；以 `shell.json` 为准，改完用眼睛确认
- `omarchy bar` 只有 `put/move/set`，没有 `remove`；删除条目要改 `shell.json`
- 不要用 `pgrep -f` 判断进程（会自匹配）
- 改系统配置前 `oma-backup`
