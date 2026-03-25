# 開發模式

### mode: auto（預設）

`mode: auto` 是 v3.0 的預設模式。AI 根據任務複雜度自動選擇：

- **簡單任務**（單一模組、<5 檔案）：等同 `mode: single`
- **複雜任務**（多個獨立子任務、>2 模組）：自動切換為 multi-agent 並行

使用者無需手動判斷。如需強制行為，明確設定 `mode: single` 或 `mode: multi-agent`。

---

ASP 的開發分為兩個階段，每個階段有不同的模式可選：

```
                    決策期                              實作期
              （產出 ADR / 設計方向）              （產出代碼 / 測試 / 文件）

          ┌─────────────────────┐          ┌─────────────────────────┐
  預設 →  │  auto / single      │   ADR    │  auto / single          │ ← 預設
          │  AI 獨立分析產出 ADR │─Accepted─▶│  人類逐步確認每個計畫    │
          └─────────────────────┘          └─────────────────────────┘
                  或                               或
          ┌─────────────────────┐          ┌─────────────────────────┐
          │  committee          │          │  autonomous             │
          │  多角色辯論（高風險） │          │  AI 在精確邊界內自主執行  │
          └─────────────────────┘          └─────────────────────────┘
                                                   或
                                           ┌─────────────────────────┐
                                           │  multi-agent            │
                                           │  多 agent 並行分治       │
                                           └─────────────────────────┘
                                                   或
                                           ┌─────────────────────────┐
                                           │  multi-agent+autonomous │
                                           │  多 Worker 各自自主開發  │
                                           └─────────────────────────┘
```

---

## 決策期模式

| 模式 | 設定 | 適用場景 | AI 行為 |
|------|------|----------|---------|
| **auto**（預設） | `mode: auto` | 大多數專案 | AI 獨立分析，產出 ADR Draft → 人類審核 Accepted |
| **committee** | `mode: committee` | 換 DB、重構核心架構等高風險決策 | 多角色（architect/security/devops/qa）辯論 → 產出 ADR Draft → 人類審核 |

> ADR 不強制使用 committee。`mode: single` 下 AI 就能獨立產出 ADR，只是少了多角色交叉質疑。

---

## 實作期模式

| 模式 | 設定 | 適用場景 | AI 行為 |
|------|------|----------|---------|
| **auto**（預設） | `mode: auto` | 一般開發 | AI 自動判斷：簡單任務逐步確認，複雜任務自動拆分並行 |
| **autonomous** | `autonomous: enabled` | 需求明確、想讓 AI 高速推進 | AI 在精確邊界內自主執行，僅在刪除檔案、新增依賴、超出範圍時暫停 |
| **multi-agent** | `mode: multi-agent` | 大量低耦合任務 | Orchestrator 拆分任務，多 Worker 並行（token 消耗約 15 倍） |
| **multi-agent + autonomous** | 兩者同時啟用 | 大規模自主開發 | 每個 Worker 在 scope 內自主執行 + 自動修復，Orchestrator 協調與驗證 |

**autonomous 前提**：所有 ADR 已 Accepted。缺少 SPEC 時 AI 會自動產生後再實作。詳見 `autonomous_dev.md`。

> **Autopilot**（`autopilot: enabled`）是 autonomous 的上層調度。它讀取 `ROADMAP.yaml`，自動執行所有任務直到完成或 token 耗盡，並支援跨 session 自動續接。詳見 [Autopilot 模式](autopilot.md)。

---

## 模式切換

修改 `.ai_profile` 對應欄位，**開新 session** 生效。常見的階段切換範例：

```yaml
# ── 決策期：選擇 ADR 產出方式 ──

# 一般專案（預設）— AI 自動判斷
mode: auto
autonomous: disabled

# 高風險決策 — 多角色辯論產出 ADR
mode: committee
autonomous: disabled

# ── 實作期：ADR Accepted 後，選擇實作方式 ──

# 一般實作 — AI 自動判斷（簡單任務逐步確認，複雜任務自動並行）
mode: auto
autonomous: disabled

# 高速自主 — AI 全自動推進
mode: auto
autonomous: enabled

# 大規模並行 — 任務拆分（人類確認每個合併）
mode: multi-agent
autonomous: disabled

# 大規模自主 — 多 Worker 各自自主開發
mode: multi-agent
autonomous: enabled
```

---

## 限制

- **committee** 可與任何實作期模式搭配（committee 是決策期模式）
- **autonomous + multi-agent**：可同時啟用。autonomous 規則分層套用——Orchestrator 協調全專案，Worker 在 Task Manifest scope 內自主執行（見 `autonomous_dev.md`「Multi-Agent 整合」）
- **切換不自動化**：沒有「ADR Accepted 後自動切換模式」的機制，需人工修改 `.ai_profile`
- **鐵則不受模式影響**：git push/rebase、docker push、rm -rf 在任何模式下都由內建權限系統彈確認框
