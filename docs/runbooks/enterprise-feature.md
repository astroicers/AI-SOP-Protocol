# Runbook：企業級功能開發

> **模式**：ASP L3-L4，mode: multi-agent | **週期**：3-8 週 | **團隊**：NEW_FEATURE_complex + MODIFICATION_L3_L4

---

## 場景說明

中大型專案的新功能開發，具備以下特徵之一：
- 跨越 2 個以上模組的架構影響
- 需要資料庫 schema 變更
- 涉及外部系統整合（API、第三方服務）
- 需要多個並行開發軌道

---

## Agent 團隊

| 角色 | ASP Agent | 主要階段 |
|------|-----------|---------|
| 架構師 | `arch` | Phase 1（ADR） |
| 依賴分析師 | `dep-analyst` | Phase 1（DAG） |
| SPEC 撰寫者 | `spec` | Phase 2（SPEC） |
| 測試作者 | `tdd` | Phase 3（Test-First） |
| 實作者（多實例） | `impl` | Phase 4（並行軌道） |
| 整合工程師 | `integ` | Phase 4 末（軌道匯流） |
| 安全審查員 | `sec` | Phase 4-5 |
| QA 驗證者 | `qa` | Phase 4-5（每任務） |
| Reality Checker | `reality` | Phase 5（最終驗收） |
| 文件撰寫者 | `doc` | Phase 5-6 |

---

## 六階段執行計劃

### Phase 1：探索與架構決策（Week 1）

```
/asp-gate G1 檢查點：
├── arch → 評估架構影響（跨模組影響 → 必須建立 ADR）
├── arch → 建立 ADR，等待 Accepted 狀態（不得繞過）
│   └── ⚠️ ADR 未 Accepted = git commit 被動態阻擋
├── dep-analyst → 建立模組依賴圖
└── 產出：ADR（Accepted）+ 影響評估報告
```

### Phase 2：規格化（Week 1-2）

```
/asp-gate G2 檢查點：
├── spec → 建立 SPEC（7 欄位全部完成）
│   ├── Done When：每條必須二元可測試
│   ├── Observability：API 必填、純 UI 標注 N/A
│   └── Traceability：連結至 ADR
├── dep-analyst → 任務依賴 DAG + 並行軌道規劃
│   └── 標記 [P] 可並行 / [S] 必須順序
└── 產出：SPEC 文件 + sprint backlog（RICE 優先排序）
```

### Phase 3：測試先行（Week 2）

```
/asp-gate G3 檢查點（必須 FAIL）：
├── tdd → 為每個 Done When 撰寫測試
│   └── 所有測試必須 FAIL（否則 G3 不通過）
├── tdd → 撰寫 Gherkin 場景（非 trivial 功能必須）
└── 產出：失敗的測試集合（已存入 checksums）
```

### Phase 4：並行實作（Week 2-5）

```
多軌道並行（dep-analyst 定義）：
├── Track A：核心業務邏輯（impl-A）
├── Track B：API 層與路由（impl-B）
├── Track C：資料層（impl-C）
└── 每個軌道的 Dev↔QA loop：
    impl → qa 驗證 → PASS/FAIL（max 2 重派，第 3 次升級）

/asp-gate G4 檢查點（每個軌道）：
├── make test-filter FILTER={track_scope} 100%
├── make lint 無錯誤
└── scope 未超出 Task Manifest

軌道匯流：
├── integ → 解決跨模組 API contract 衝突
├── integ → 確保整合後 make test 全套通過
└── /asp-gate G5.5 — 跨元件 parity 驗證（防止下游不變量違反）
```

### Phase 5：強化與驗收（Week 5-6）

```
/asp-gate G5 檢查點（獨立再驗證）：
├── qa → 獨立執行測試（不信任 impl 自報）
├── qa → checksum 比對（偵測 test smuggling）
├── sec → 完整安全審查（OWASP + credential scan）
└── reality → /asp-reality-check（≥3 正向證據，0 阻斷問題）

/asp-gate G6.5 — Post-Deploy SIT（staging 環境）：
├── 在 staging 執行 round-trip 測試
├── 確認 staging/prod 環境 parity
└── 人類確認後才進入 Phase 6
```

### Phase 6：交付（Week 6-8）

```
/asp-ship（10 步驟）：
├── Step 1-3：測試、lint、scope 確認
├── Step 4-6：文件同步（doc agent）
├── Step 7-8：安全、secret 掃描
├── Step 9：hardcoded credential 掃描
└── Step 10：人類最終確認

doc → 更新：
├── CHANGELOG.md（新功能條目）
├── docs/architecture.md（如有架構變更）
└── SPEC Traceability 欄位填寫

git push（人類明確同意後執行）
```

---

## 並行軌道協議

當 dep-analyst 定義多個 [P] 並行軌道時：

```yaml
# .agent-lock.yaml 範例
locked_files:
  src/api/routes.go:
    locked_by: impl-B
    track: B
    expires: 2026-XX-XXTXX:XX:XXZ
  src/store/user.go:
    locked_by: impl-C
    track: C
    expires: 2026-XX-XXTXX:XX:XXZ
```

規則：
- 不同軌道的 impl 不得修改對方鎖定的檔案
- 鎖超時由 `make agent-lock-gc` 自動清除
- 軌道完成後由 integ 統一匯流

---

## G5.5 跨元件驗證觸發條件

以下任一情況必須執行 /asp-gate G5.5：
- 修改了 2 個以上模組的公開 API 簽名
- 資料庫 schema 有 breaking change
- 新增了跨服務的事件/訊息格式
- 修改了共享的 utility/helper 函數

---

## 關鍵決策點

| 決策 | 時機 | 決策者 |
|------|------|--------|
| ADR 必要性 | Phase 1 Day 1 | arch（若架構影響 → 必須） |
| 並行軌道劃分 | Phase 2 末 | dep-analyst + orchestrator |
| 軌道匯流策略 | Phase 4 中期 | integ + arch |
| Staging 驗收 | G6.5 | reality + 人類 |
| 正式上線 | Phase 6 | 人類（必須明確同意） |

---

## 成功指標

| 指標 | 目標 |
|------|------|
| ADR 接受率 | > 90% |
| First-pass QA rate | ≥ 65%（多軌道較低為正常） |
| Make test 通過率 | 100% |
| SPEC Done When 覆蓋 | 100% |
| Security bugs shipped | 0 |
| Doc audit warnings | 0 |

---

## 相關指令

```bash
make adr-new TITLE="..."              # 建立 ADR
make spec-new TITLE="..."            # 建立 SPEC
make agent-tracks                    # 查看並行軌道狀態
make agent-handoff-list              # 查看待處理交接單
make agent-locks                     # 確認文件鎖定狀態
make agent-lock-gc                   # 清理過期鎖定
make asp-enforcement-status          # 確認阻擋狀態
```

> 參考：`.asp/agents/team_compositions.yaml` → `NEW_FEATURE_complex`, `MODIFICATION_L3_L4`
> 參考：`.asp/profiles/pipeline.md` G1-G6 完整定義
> 參考：`.asp/profiles/multi_agent.md` 並行軌道協議
