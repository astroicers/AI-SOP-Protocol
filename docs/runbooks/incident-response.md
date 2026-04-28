# Runbook：生產事故應變

> **模式**：ASP 緊急響應 | **適用**：P0/P1 生產事故 | **團隊**：BUGFIX_hotfix

---

## 場景說明

生產環境發生服務中斷或重大功能異常，需在最短時間內恢復服務，並在事後完成 postmortem。

---

## 嚴重性分級（對應 ASP escalation.md）

| 等級 | 定義 | 響應時限 | 人類確認 |
|------|------|---------|---------|
| **P0** | 全服務中斷 / 資料損毀風險 | 立即（< 15 分鐘） | 必須，但不阻擋緊急緩解 |
| **P1** | 核心功能受損 / 大量用戶受影響 | < 1 小時 | 必須 |
| **P2** | 非核心功能異常 | < 4 小時 | 建議 |
| **P3** | 輕微問題 / 有 workaround | < 24 小時 | 可非同步 |

---

## 應變時間軸

### 第一階段：偵測與分級（0-15 分鐘）

```
T+0    偵測到異常（監控告警 / 使用者回報）
T+5    確認影響範圍 → 定義 P 等級
T+10   P0/P1：立即通知人類確認
T+15   啟動 BUGFIX_hotfix 場景（impl + sec）
```

### 第二階段：緩解（15-60 分鐘）

```
T+15   impl → 識別根因（不超出 hotfix scope）
T+20   impl → 撰寫最小修復（不引入新功能）
T+30   qa → 獨立驗證修復（Dev↔QA loop，max 2 次）
       → P0 時 qa 驗證可與 impl 同步進行（平行軌道）
T+45   sec → 快速安全掃描（是否引入新漏洞）
T+55   reality → 緊急 reality check（P0 接受較低門檻，但不得為零）
T+60   /asp-ship 執行（緊急模式：標記 BYPASS 理由）
```

> **緊急 BYPASS 規則**：若在 /asp-ship 中跳過步驟，必須輸出：
> ```
> ⚠️ ASP BYPASS: 跳過 [步驟]，理由：P0 緊急緩解，BLOCKER 待修。
> ```

### 第三階段：恢復後確認（60-240 分鐘）

```
T+60   人工確認 git push → 部署
T+90   確認服務恢復正常（監控指標回穩）
T+120  補充跳過的 /asp-ship 步驟
T+240  開始 postmortem 撰寫（make postmortem-new）
```

### 第四階段：事後分析（24-72 小時內）

```
Day 1  make postmortem-new TITLE="[事故日期]-[簡述]"
Day 2  arch → 評估是否需要新 ADR（若根因是架構問題）
Day 3  建立 tech-debt 項目（tag: HIGH 緊急修復遺留的技術債）
```

---

## Agent 分工

| 角色 | ASP Agent | 任務 |
|------|-----------|------|
| 主修復者 | `impl` | 最小範疇 hotfix |
| 獨立驗證 | `qa` | 不信任 impl 自報，親自跑測試 |
| 安全確認 | `sec` | 確認修復未引入新漏洞 |
| 最終驗收 | `reality` | 緊急門檻（≥2 正向證據，0 阻斷問題） |
| 文件補齊 | `doc` | 事後補 CHANGELOG + postmortem 連結 |

---

## P0 快速指令序列

```bash
# 1. 確認當前 ASP 阻擋狀態
make asp-enforcement-status

# 2. 啟動任務追蹤
make task-start DESC="P0 事故：[簡述]"

# 3. 緊急修復後（跳過 ADR 門檻，需記錄 bypass）
make asp-bypass-record SKILL=asp-gate STEP=G1 REASON="P0 緊急緩解"

# 4. 解除動態 commit 阻擋（如有）
make asp-unlock-commit

# 5. 事後建立 postmortem
make postmortem-new TITLE="2026-XX-XX-service-outage"

# 6. 補記技術債
# 在修復的 commit 或 SPEC 中加入：
# tech-debt: HIGH architecture [需要的架構修正]
```

---

## 不可妥協的底線

即使在 P0 緊急情況下：

- **禁止**：git push --force
- **禁止**：跳過 qa 獨立驗證（可縮短，但不可省略）
- **禁止**：部署後不追蹤技術債
- **必須**：在同一個 session 結束前補齊文件

---

## 相關指令

```bash
make postmortem-new TITLE="..."     # 建立事後分析
make asp-bypass-record SKILL=... STEP=... REASON="..."  # 記錄緊急 bypass
make asp-bypass-review              # 審核所有 bypass 記錄
make guardrail-log                  # 檢視護欄記錄
```

> 參考：`.asp/profiles/escalation.md` P0-P3 路由
> 參考：`.asp/agents/team_compositions.yaml` → `BUGFIX_hotfix`
