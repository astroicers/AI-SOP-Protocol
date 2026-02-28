# AI-SOP-Protocol (ASP)

> 把開發文化寫成機器可讀的約束，讓 AI 自動遵守。

不需要每次都提醒 AI「記得寫測試」「不要亂推版」「更新文件」。

---

## ASP 做什麼，不做什麼

ASP 規範的是**怎麼做**——ADR 先於實作、測試先於代碼、部署必須確認、文件同步更新。

ASP **不管你做什麼**。產品方向、功能優先序、時程規劃不在 ASP 範圍內。
你的專案應該有一份 **Roadmap**（或類似的規劃文件）來決定做什麼、先做什麼。

> **你決定蓋什麼房子，ASP 確保施工流程不出錯。**

---

## 前置需求（選配，非必須）

以下工具安裝在**使用者層**（`~/.claude/`），與 ASP 互補但獨立：

| 工具 | 用途 | 安裝方式 |
|------|------|----------|
| [Superpowers](https://github.com/obra/superpowers) | 全域工作流（brainstorm → plan → execute） | `cp -r superpowers ~/.claude/plugins/` |
| [antigravity-awesome-skills](https://github.com/sickn33/antigravity-awesome-skills) | 進階技能擴充 | `cp -r skills ~/.claude/skills/` |

```
使用者層（~/.claude/）     ← Superpowers、skills 裝在這
  └── 所有專案共享，裝一次就好

專案層（./）               ← ASP 裝在這
  └── 每個 repo 各自有
```

> ASP 本身**不依賴**上述工具，可單獨使用。

---

## 快速安裝

```bash
curl -sSL https://raw.githubusercontent.com/astroicers/AI-SOP-Protocol/main/.asp/scripts/install.sh | bash
```

安裝腳本會自動：
- 複製 `CLAUDE.md`、`.asp/`、`Makefile`、`.gitignore`
- 建立 `.claude/settings.json` 並註冊 SessionStart Hook（若已存在會合併）
- 舊版 ASP（profiles 散落在根目錄）會自動遷移至 `.asp/`

或手動複製：

```bash
cp CLAUDE.md /your-project/
cp -r .asp/ /your-project/.asp/
cp -r .claude/ /your-project/.claude/  # SessionStart Hook 設定
cp Makefile /your-project/             # 若無衝突
cp .gitignore /your-project/           # 若無衝突
```

---

## 啟動

安裝後，在 Claude Code 輸入：

```
請讀取 CLAUDE.md，依照 .ai_profile 載入對應 Profile，後續遵循 ASP 協議。
```

---

## .ai_profile 設定

```yaml
type: system          # system | content | architecture
mode: single          # single | multi-agent | committee
workflow: standard    # standard | vibe-coding
rag: disabled         # enabled | disabled
guardrail: disabled   # enabled | disabled
hitl: standard        # minimal | standard | strict
design: disabled      # enabled | disabled
name: your-project
```

### HITL 等級（Human-in-the-Loop）

`hitl` 控制 AI 自律行為的粒度（由 Profile 定義，AI 自行遵循）：

| 等級 | 行為 |
|------|------|
| `minimal` | 僅對副作用操作主動說明「等待確認」 |
| `standard` | + 原始碼修改前確認 SPEC 存在性 |
| `strict` | + 所有檔案修改前主動暫停確認 |

> 危險操作（git push/rebase、docker push、rm -rf 等）由 Claude Code 內建權限系統彈出確認框，不依賴 HITL 等級。

---

## 常用指令

```bash
make help              # 顯示所有指令

# 開發
make build             # 建立 Docker Image
make test              # 執行測試
make test-filter FILTER=xxx   # 局部測試
make deploy            # 部署（需確認）

# 文件
make adr-new TITLE="選型理由"
make spec-new TITLE="功能名稱"

# RAG（需 rag: enabled）
make rag-index         # 建立向量索引
make rag-search Q="問題"

# Multi-Agent
make agent-done TASK=TASK-001 STATUS=success
make agent-status
make agent-lock-gc     # 清理逾時鎖定

# Session
make session-checkpoint NEXT="下一步"
```

---

## SPEC 驅動開發

ASP 的 SPEC（規格書）不只是文件——它定義了**需求、邊界條件、測試驗收標準**，是一體的。

```
SPEC 定義「Done When」（驗收標準）
  → TDD 先寫測試（基於 Done When）
    → 實作讓測試通過
      → 驗收
```

| 情境 | 是否需要 SPEC |
|------|-------------|
| 新功能開發 | **是**（預設），Done When 必須含測試條件 |
| 非 trivial Bug 修復 | **是**（`make spec-new TITLE="BUG-..."`) |
| trivial（單行/typo/配置） | 可跳過，需說明理由 |
| 原型驗證 | 可延後，需標記 `tech-debt: test-pending` |

**ADR↔SPEC 連動**（架構變更時）：

```
ADR（Accepted）→ SPEC（關聯 ADR-NNN）→ TDD → 實作
                    ↑ ADR 為 Draft 時不建 SPEC、不寫生產代碼
```

- SPEC 的「關聯 ADR」欄位必須填入對應 ADR 編號
- 非架構變更的 SPEC 不需要關聯 ADR

SPEC 模板中的 **✅ Done When** 區塊就是測試定義（**必須含至少一項測試條件**）：

```markdown
## ✅ Done When
> 必須包含至少一項可驗證的測試條件。

- [ ] `make test-filter FILTER=spec-000` all pass
- [ ] `make lint` has no errors
- [ ] Response time < ____ms
- [ ] Updated CHANGELOG.md
```

SPEC 最低必填欄位：**Goal、Inputs、Expected Output、Done When（含測試條件）、Edge Cases**。

> 測試不是另外寫的文件，而是 SPEC 的一部分。SPEC 完成 = 驗收標準已定義。

---

## 專案結構

```
your-project/
├── CLAUDE.md                    # Claude Code 主入口（鐵則 + Profile 對應表）
├── Makefile                     # 指令封裝
├── .ai_profile                  # 專案設定（type/mode/workflow/hitl）
├── .gitignore
│
├── .claude/
│   └── settings.json            # SessionStart Hook 設定（install.sh 自動建立）
│
├── .asp/                        # ← ASP 所有靜態檔案收在這裡
│   ├── hooks/
│   │   └── clean-allow-list.sh     # SessionStart hook（清理危險 allow 規則）
│   ├── profiles/
│   │   ├── global_core.md       # 全域準則（所有專案必載）
│   │   ├── system_dev.md        # 系統開發（ADR/TDD/Docker）
│   │   ├── content_creative.md  # 文字專案（排版/Markdown）
│   │   ├── multi_agent.md       # 任務分治（實作期並行）
│   │   ├── committee.md         # 角色委員會（決策期辯論）
│   │   ├── vibe_coding.md       # 規格驅動工作流
│   │   ├── rag_context.md       # Local RAG 整合
│   │   ├── guardrail.md         # 範疇限制與敏感資訊保護
│   │   └── design_dev.md        # UI/UX 設計治理
│   ├── templates/
│   │   ├── ADR_Template.md
│   │   ├── SPEC_Template.md
│   │   ├── architecture_spec.md
│   │   └── workflow-design.md   # 設計工作流範本
│   ├── scripts/
│   │   ├── install.sh           # 一鍵安裝（含 SessionStart Hook 設定）
│   │   └── rag/
│   │       ├── build_index.py   # 建立向量索引
│   │       ├── search.py        # 查詢知識庫
│   │       └── stats.py         # 統計資訊
│   └── advanced/
│       └── spectra_integration.md
│
└── docs/
    ├── adr/                     # 架構決策紀錄
    └── specs/                   # 功能規格書
```

---

## Profile 分層設計

```
鐵則（CLAUDE.md）
  ↓ 所有專案，不可覆蓋
全域準則（global_core.md）
  ↓ 溝通規範、破壞性操作防護、連帶修復
專案類型 Profile（system / content）
  ↓ 依 .ai_profile type 載入
作業模式 Profile（multi-agent / committee）
  ↓ 依 .ai_profile mode 載入（可選）
開發策略 Profile（vibe-coding）
  ↓ 依 .ai_profile workflow 載入（可選）
選配 Profile（rag / guardrail / design）
  ↓ 依 .ai_profile 各欄位載入（可選）
```

**RAG 模式的作用**：當 Profiles 太多時，不再全部塞進 context，
改由 AI 主動查詢 `make rag-search` 按需召回相關規則，解決 context 飽和問題。

---

## Profile 表達方式

Profiles 使用分層混合的表達格式，依內容性質選用最適合的格式：

| 層級 | 格式 | 範例 |
|------|------|------|
| 設計哲學 | 自然語言 | CLAUDE.md 鐵則、profiles 開頭說明 |
| 決策流程 | **Pseudocode** | guardrail 三層策略、HITL 暫停矩陣、RAG 查詢 |
| 技術執行 | Bash / Make | clean-allow-list.sh、Makefile |
| 靜態規則 | 表格 / YAML | ADR 分類、模型選擇、排版規範 |

Pseudocode 語法慣例：

```
FUNCTION name(params):        // 決策流程入口
  IF condition:               // 分支判斷
    RETURN action(...)        // 回傳行為
  MATCH (var1, var2):         // 多條件矩陣
    (a, b) → RETURN x
  INVARIANT: 不可違反的約束    // 對應鐵則
  CALL other.function(...)    // 跨 profile 委派
```

> 核心邏輯：只在「AI 需要做判斷」的地方用 pseudocode，在「人類需要理解」的地方保留散文。

---

## 技術強制層（Hooks + 內建權限）

ASP 使用 Claude Code **內建權限系統** + **SessionStart Hook** 保護危險操作：

```
.claude/settings.json
  └── SessionStart hook → clean-allow-list.sh（清理 allow list）

每次 session 啟動 → 自動清理 allow list 中的危險規則
  → 危險指令不在 allow list → 內建權限系統彈出「Allow this bash command?」確認框
```

| 機制 | 說明 |
|------|------|
| **內建權限系統** | 危險指令（git push/rebase, docker push, rm -rf 等）不在 allow list 中時，Claude Code 自動彈出確認框 |
| **SessionStart Hook** | `clean-allow-list.sh` 每次 session 啟動時自動清理 allow list 中的危險規則，確保內建權限系統持續生效 |

> 使用者可在確認框中選擇 "Allow"（一次性）或 "Always allow"（永久），但後者會在下次 session 啟動時被自動清理。
> 設定檔位於 `.claude/settings.json`，hook 腳本位於 `.asp/hooks/`。

---

## 設計哲學

**從「規則替代判斷」到「規則賦能判斷」；從「提示詞約束」到「技術強制」。**

- 鐵則（不可繞過）只有 3 條，由內建權限系統 + SessionStart Hook 技術輔助
- 預設值可跳過，但必須說明理由——這讓 Claude 學會判斷，而不只是服從
- 護欄預設「詢問與引導」，不是「拒絕」
- 一條有條件的規則，勝過三條無條件的規則

---

## 延伸閱讀

| 資源 | 說明 |
|------|------|
| [Agent-Skills-for-Context-Engineering](https://github.com/muratcankoylan/Agent-Skills-for-Context-Engineering) | Context engineering 教學庫：壓縮策略、衰退模式、multi-agent token 經濟學。ASP 已吸收其核心精髓，有興趣深入可參閱原始 skills |
| [UI UX Pro Max Skill](https://github.com/nicobailon/ui-ux-pro-max-skill) | AI 驅動的 Design System 產生器：50 種 UI 風格、21 組色彩系統、支援 React/Next.js/Tailwind/shadcn 等 9 種技術棧。搭配 ASP `design: enabled` 使用效果最佳 |
| [Interface Design Skill](https://github.com/mcsimw/Interface-Design) | 設計決策累積工具：自動儲存 spacing/depth/surface pattern 到 `.interface-design/system.md`，維持跨 session 的設計一致性 |
