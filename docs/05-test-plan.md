# 05 · 测试计划与验收

> 原则：**不靠“看起来对”**。数据层用 fixture 做单元测试；界面用清单逐项手测。

---

## 1. 数据层（`scripts/quota.py`）单元测试

用临时目录模拟 `$HOME` / XDG，用 fixture 替代真实 API 和 DB。禁止在测试里使用真实 key。

### 1.1 fixture

- `api-ok.json`：`rolling 2 / weekly 20 / monthly 13` + 三个 `resetsAt`
- `api-401.json` / `api-timeout` / `api-malformed.json`
- `db-v2.sqlite`：`credential` 表，`integration_id='opencode-go'`
- `auth-v1.json`：`{"opencode-go":{"type":"api","key":"test"}}`
- `credential-v2`：value = `{"type":"api","key":"test"}`
- `samples.jsonl`：正常增长、空闲、长间隔、周期重置四组样本
- 缓存 `state.json`：上一次成功读数

### 1.2 用例

| # | 用例 | 期望 |
|---|---|---|
| 1 | v2 key + ok API | `state=ok`；window 数值正确；`remaining=100-percent` |
| 2 | v1 auth.json 回退 | 同上 |
| 3 | 无 key | `state=no-key`；不抛异常；不打印 key |
| 4 | 401 | `state=auth-expired` |
| 5 | 超时/断网 | `state=stale`；返回缓存；`stale=true` |
| 6 | 响应缺字段/非 JSON | `state=stale`；保留缓存 |
| 7 | `resetsAt` 解析 | 本地时间与 `resetInSec` 正确；跨时区不偏 |
| 8 | `resetsAt` 钳制 | rolling ≤5h+60s、weekly ≤7d+60s、monthly ≤31d+60s |
| 9 | 周期重置 | weekly/monthly 下降视为重置并清空该段样本；rolling 下降不清空 |
| 10 | 百分比为 0 | Avg `flat`、`Idle` / `≥ <重置>` |
| 11 | 窗口不可用 | `status != ok` → 该窗口 `available=false`，不参与 worst |
| 12 | 输出脱敏 | stdout/stderr/缓存中**不含** key；只允许长度/存在性 |
| 13 | Avg runway | <3 点或 <1h → `null`；否则数值合理 |
| 14 | 采样修剪 / 通知去重 | 样本只留 30 天；同 `窗口+级别+resetsAt` 只产生一个 alert |

运行方式建议：`pytest` 或 Python 内置 `unittest`；测试不需要网络。

---

## 2. 界面手测清单

### 2.1 顶栏显示
- [ ] `worst`：只显示最紧窗口；人为把 5h 用量拉高后，标签自动从 `M` 切到 `5h`
- [ ] `all`：三个都显示，顺序固定 `5h · 7d · M`
- [ ] `month`：只显示月
- [ ] `percentMode=used`：显示已用而非剩余
- [ ] 阈值：剩余 19% 变警告色；9% 变严重色并带 `!`
- [ ] 无数据：显示 `—`
- [ ] 降级：断网后保留上次读数，tooltip 标“缓存于 HH:mm”

### 2.2 布局/主题
- [ ] 顶栏 top / bottom / left / right
- [ ] 垂直顶栏：文字可读、不截断
- [ ] 明/暗主题各一遍（颜色对比度）
- [ ] 多显示器：每个 bar 实例都刷新（`broadcast`）
- [ ] 窄屏：文字不挤爆；必要时自动省略

### 2.3 Tooltip
- [ ] 三个窗口 + 百分比 + 重置倒计时（不显示绝对时间）
- [ ] Runway：`Avg <速度> → <时长>` 一行；样本不足时整列隐藏
- [ ] 降级提示出现（cached at HH:mm）
- [ ] `nowMs` 在显示时刷新，倒计时不使用创建时时钟
- [ ] 鼠标移出后消失；不残留

### 2.4 面板
- [ ] 左键打开/关闭；Esc 关闭；点外部关闭
- [ ] 三个窗口卡片：环形/条形与百分比一致
- [ ] 倒计时每秒/每分钟更新
- [ ] Runway：`Period · Avg pace · Lasts`；样本不足（<3 点 / <1h）时整块隐藏
- [ ] Runway 时长颜色：绿色 / amber（阈值或重置前耗尽）/ 红色（严重或为空）
- [ ] 图例与样本依据行完整，不溢出面板
- [ ] 刷新按钮：立即更新（绕过缓存）
- [ ] 降级/无 key 状态

### 2.5 设置
- [ ] 面板内改：阈值、刷新、barWindows、percentMode、通知
- [ ] Setup → Plugins 改同一字段：两边同步
- [ ] `omarchy restart shell` 后保留
- [ ] `planLabel`：Go / Go Plus 下拉只改显示标签
- [ ] 非法值（阈值 0/100、间隔 10）被限制或拒绝

### 2.6 通知
- [ ] 剩余 20% 发一次警告；10% 发一次严重
- [ ] 同一窗口同一级别在 `resetsAt` 前不重复
- [ ] 窗口重置后重新计
- [ ] 严重通知 urgency=critical
- [ ] 关闭 `notifyEnabled` 后不发
- [ ] `notifyReset` 开启：重置后发一次

### 2.7 边界
- [ ] 无 key（临时改名 credential 或用假 DB）
- [ ] 401（用假 API 返回）
- [ ] 断网（停代理）
- [ ] 空数据（无样本文本）
- [ ] 跨周期：把 `resetsAt` 改成过去 → 不崩，等待新值
- [ ] 长时间运行（>1h）内存不涨、不重复通知

---

## 3. 发布前验收

- [ ] `omarchy plugin validate ~/.config/omarchy/plugins/local.opencode-quota` 通过
- [ ] `omarchy-shell shell ping` → `ok`
- [ ] shell 日志无 QML 报错
- [ ] `omarchy plugin add <临时 git 仓库> --enable` 能从零装上
- [ ] README 按步骤可复现（另一台/清空插件目录）
- [ ] 截图：明/暗各一张，含顶栏 + 面板
- [ ] LICENSE = MIT
- [ ] manifest version = 1.0.0；id 已改为发布 id
- [ ] 仓库无 key、无缓存、无本机绝对路径泄漏

---

## 4. 验收基准（本机）

| 项 | 期望 |
|---|---|
| rolling / weekly / monthly | 与 console 差 ≤1%（取整/采样） |
| monthly reset | `2026-11-17 22:35`（本地） |
| 采样 | 最新样本在 `max(15 min, 2×刷新间隔)` 内；Runway 与手工计算一致 |
| 无 key | `—` + 面板提示，不崩 |
| 断网 | 保留上次读数 + 降级标记 |
| 设置重启 | 保留 |
| 通知 | 每窗口每阈值一次 |

---

## 5. 完成定义

1. 数据层单测全过（无需网络/真实 key）
2. 手测清单全勾
3. `omarchy plugin validate` 通过
4. README + 截图 + LICENSE 齐备
5. 版本 `1.0.0`，可被 `omarchy plugin add/update` 正常安装与更新
