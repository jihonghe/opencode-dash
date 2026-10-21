# 02 · 数据源、口径与查询

> **2026-10-21 范围变更**：本地用量/模型明细/cost 已移除。插件只使用官方 `/zen/go/v1/usage`（账号级，覆盖所有客户端）；`opencode.db` 仅用于读取 credential key。趋势图已移除；面板改为 Runway 表（Period / Avg pace / Lasts）：只保留按实际时间、含空闲的 Avg 估算；样本不足（<3 点或 <1h）或最新样本过期时整块隐藏。`showModelDetail`、`renewOverride` 已删除。


> 本文是实现 `scripts/quota.py` 的唯一依据。所有数字都要能在这里找到来源。

---

## 1. 官方用量端点

```
GET https://opencode.ai/zen/go/v1/usage
Authorization: Bearer <opencode-go key>
User-Agent: opencode-quota/1.0
```

- 这是**官方但未文档化**的端点；`opencode-quota`（1041★）等工具也用它。
- 只读，无副作用。
- 需要走代理：`https_proxy=http://127.0.0.1:10801`。

### 1.1 响应（实测 2026-10-20）

```json
{
  "usage": {
    "rolling": {
      "status": "ok",
      "percent": 2,
      "resetsAt": "2026-10-20T16:08:43.000Z"
    },
    "weekly": {
      "status": "ok",
      "percent": 20,
      "resetsAt": "2026-10-26T00:00:00.000Z"
    },
    "monthly": {
      "status": "ok",
      "percent": 13,
      "resetsAt": "2026-11-17T14:35:30.000Z"
    }
  }
}
```

### 1.2 字段语义

| 字段 | 含义 |
|---|---|
| `percent` | **已用**百分比（0–100，整数） |
| `resetsAt` | ISO 8601 UTC；该窗口的重置时刻 |
| `status` | `ok`；其它值按“不可用”处理 |

窗口：
- `rolling`：**5 小时滚动窗口**；重置时间 = 窗口内最早一条用量 + 5h（所以会随时间滑动）
- `weekly`：**固定自然周**；实测重置为**周一 00:00 UTC**（不是滚动 7 天）
- `monthly`：**订阅月**（从订阅日开始的一个月）；实测 `2026-11-17T14:35:30Z`

**注意**：端点**不支持按模型查询**（`?model=` 会被忽略），返回的是账号级聚合。

### 1.3 与 console 的差异

console 显示 3% / 20% / 14%，API 同一时刻可能显示 2% / 20% / 13% —— 差 1% 属于**采样时间 + 整数取整**。以 API 实时值为准，展示时允许 ±1%。

### 1.4 与本地 cost 的差异（重要）

本机本地 `opencode stats` 的 cost 约 **$3.83**，若按文档 $80 月上限算只有 4.8%；但 API/console 的 monthly 是 **13–14%**。

→ **不要用本地 cost 反推配额百分比，也不要把 percent 换算成美元。**
本地 cost 只用于“按模型用量”展示，并在 UI 上标注“本地”。

---

## 2. key 从哪里来

### 2.1 OpenCode v2（本机现状）

`~/.local/share/opencode/opencode.db` → `credential` 表：

```sql
select value
from credential
where integration_id = 'opencode-go'
limit 1;
```

`value` 是 JSON 字符串：

```json
{"type":"api","key":"…"}
```

只取 `.key`；**不要打印、不要写日志、不要写缓存**。

Python 读取示例（不打印）：

```python
import json, sqlite3, os

db = os.path.expanduser("~/.local/share/opencode/opencode.db")
con = sqlite3.connect(f"file:{db}?mode=ro", uri=True)
row = con.execute(
    "select value from credential where integration_id='opencode-go' limit 1"
).fetchone()
con.close()
key = json.loads(row[0])["key"] if row else None
```

### 2.2 OpenCode v1（回退）

`~/.local/share/opencode/auth.json`：

```json
{"opencode-go": {"type": "api", "key": "…"}}
```

本机 **不存在** 这个文件；实现时保留回退即可。

### 2.3 调用示例

```bash
# 不要把 key 放到命令行参数里（会进 shell 历史/进程列表）
https_proxy=http://127.0.0.1:10801 \
curl -sS --max-time 15 \
  -H "Authorization: Bearer $KEY" \
  -H "User-Agent: opencode-quota/1.0" \
  https://opencode.ai/zen/go/v1/usage
```

Python 用 `urllib.request` 即可；尊重 `https_proxy` 环境变量。禁止把 key 拼进 URL。

### 2.4 失败分类

| 情况 | 处理 |
|---|---|
| 没有 key | `state = "no-key"` |
| HTTP 401/403 | `state = "auth-expired"` |
| 超时 / 网络错误 | `state = "stale"`，用缓存 |
| 非 JSON / 缺字段 | `state = "stale"`，用缓存 |
| `status != ok` | 该窗口标记不可用 |

---

## 3. 本地 DB：只读 credential

插件只从 `credential` 表读取 key（见 2.1），**不再**查询 `session_message` / `message`，
也不展示按模型/cost/按天的本地用量。原因：

- 官方百分比是账号级，覆盖所有客户端；本地 DB 只记录 OpenCode CLI/TUI。
- 本地 cost 与官方配额口径不一致，不能互相换算。
- DB 以 `mode=ro` 打开，除 `credential` 外不读取其它表。

---

## 4. 订阅周期

- 权威来源：`monthly.resetsAt`
- 周期 = `[resetsAt - 1 个月, resetsAt)`
- 例：`2026-11-17T14:35:30Z` → 周期 `2026-10-17T14:35:30Z` 至 `2026-11-17T14:35:30Z`（本机首次使用是 10-18，所以不影响当前统计）
- 到期后 API 会给出新的 `resetsAt`，无需自己加一个月；缓存里的旧值过期即丢弃

---

## 5. 输出 JSON（给 QML 用）

`quota.py --json` 输出（示例）：

```json
{
  "ok": true,
  "state": "ok",
  "stale": false,
  "updatedAt": "2026-10-21T14:36:35+08:00",
  "planLabel": "OpenCode Go",
  "windows": {
    "rolling": {"available": true, "status": "ok", "percent": 7, "remaining": 93,
                "resetsAt": "2026-10-21T09:13:49Z", "resetInSec": 9395},
    "weekly":  {"available": true, "status": "ok", "percent": 31, "remaining": 69,
                "resetsAt": "2026-10-26T00:00:00Z", "resetInSec": 408166},
    "monthly": {"available": true, "status": "ok", "percent": 19, "remaining": 81,
                "resetsAt": "2026-11-17T14:35:30Z", "resetInSec": 2361496}
  },
  "runway": {
    "rolling": {"seconds": 9395, "ratePerHour": 0.24, "reason": "ok"},
    "weekly":  {"seconds": 408166, "ratePerHour": 0.55, "reason": "ok"},
    "monthly": {"seconds": 1103576, "ratePerHour": 0.26, "reason": "ok"}
  },
  "samples": [{"t": "2026-10-21T14:31:35Z", "rolling": 7, "weekly": 31, "monthly": 19}],
  "alerts": []
}
```

- `state`: `ok` | `no-key` | `auth-expired` | `stale` | `no-data`
- `stale=true` 时 `windows` 来自缓存，`updatedAt` 是缓存时间
- `runway.<period>.reason`: `ok` | `flat` | `insufficient` | `unavailable`
- `samples` 只保留最近 30 天；`alerts` 由插件用于发通知

---

## 6. 安全

- key 只存在内存；不写 `state.json`、不写日志、不进异常信息
- DB 用 `mode=ro`；只读 `credential` / `session_message` / `message`
- 不读取其它凭据表；不发送 key 到 `opencode.ai` 以外的地址
- 调试输出只打印“key 存在/长度”之类的元信息，永不打印值
- 缓存里只放百分比/时间/本地用量，不放 key

---

## 7. 验收基准（本机 2026-10-20）

- API 返回：rolling 2–3%、weekly 20%、monthly 13–14%
- monthly `resetsAt` = `2026-11-17T14:35:30Z`
- weekly `resetsAt` = 周一 `00:00:00Z`
- 本地模型：`deepseek-v4.1-flash`（$3.85 / 1196 条）、`nemotron-3.5-super-vl-free`（$0 / 24 条）
- `auth.json` 不存在；key 在 DB `credential`
