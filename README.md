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

安裝只問兩題：**專案類型** → **開發風格**，全按 Enter 即可完成。

| 開發風格 | 設定 | 適合 |
|----------|------|------|
| **標準**（預設） | `hitl: standard` | 大多數專案 |
| **高速自主** | `autonomous: enabled` / `hitl: minimal` | 需求明確的快速迭代 |
| **完整治理** | guardrail / coding_style / design / openapi / frontend_quality 全開 | 正式環境 |
| **高速自主+多Agent** | `autonomous: enabled` / `mode: multi-agent` | 大規模並行自主開發 |
| **Autopilot** | `autopilot: enabled` | ROADMAP 驅動持續執行至 token 耗盡 |

> 安裝後隨時可編輯 `.ai_profile` 微調，開新 session 生效。

---

## 啟動

安裝後，在 Claude Code 輸入：

```
請讀取 CLAUDE.md，依照 .ai_profile 載入對應 Profile，後續遵循 ASP 協議。
```

---

## .ai_profile 設定

安裝時 `install.sh` 會在專案根目錄建立 `.ai_profile`，這是 ASP 唯一讀取的設定檔。
直接編輯此檔案即可調整所有行為。

> `.asp/templates/example-profile-*.yaml` 是不同專案類型的預設範例，供參考用。
> 不需要複製或重命名——`install.sh` 已根據你的選擇產生了正確的 `.ai_profile`。

```yaml
type: system              # system | content | architecture
mode: single              # single | multi-agent | committee
workflow: standard        # standard | vibe-coding
rag: disabled             # enabled | disabled
guardrail: disabled       # enabled | disabled
hitl: standard            # minimal | standard | strict
autonomous: disabled      # enabled | disabled
orchestrator: disabled    # enabled | disabled（autonomous: enabled 時自動載入）
design: disabled          # enabled | disabled
coding_style: disabled    # enabled | disabled
openapi: disabled         # enabled | disabled
frontend_quality: disabled  # enabled | disabled（design: enabled 時自動載入）
autopilot: disabled       # enabled | disabled（ROADMAP 驅動持續執行）
name: your-project
```

### HITL 等級（Human-in-the-Loop）

`hitl` 控制 AI 自律行為的粒度（由 Profile 定義，AI 自行遵循）：

| 等級 | 行為 |
|------|------|
| `minimal` | 明確定義的暫停條件（刪除檔案、新增依賴、DB Schema 變更、範圍超出、自動修復失敗 ≥3 次） |
| `standard` | + 原始碼修改前確認 SPEC 存在性 |
| `strict` | + 所有檔案修改前主動暫停確認 |

> 危險操作（git push/rebase、docker push、rm -rf 等）由 Claude Code 內建權限系統彈出確認框，不依賴 HITL 等級。詳見 [技術強制層](docs/technical-enforcement.md)。

---

## 開發模式

ASP 分為**決策期**（ADR 產出）和**實作期**（代碼產出），各有不同模式可選：
single → autonomous → multi-agent → autopilot，逐步提升 AI 自主權。

| 階段 | 模式 | 設定 | AI 行為 |
|------|------|------|---------|
| 決策期 | **single**（預設） | `mode: single` | AI 獨立產出 ADR Draft → 人類審核 |
| 決策期 | **committee** | `mode: committee` | 多角色辯論 → ADR Draft → 人類審核 |
| 實作期 | **single**（預設） | `mode: single` | 人類逐步確認 |
| 實作期 | **autonomous** | `autonomous: enabled` | AI 在精確邊界內自主執行 |
| 實作期 | **multi-agent** | `mode: multi-agent` | Orchestrator 拆分，多 Worker 並行 |
| 實作期 | **autopilot** | `autopilot: enabled` | ROADMAP 驅動，持續執行至 token 耗盡 |

> 📖 [完整模式說明、切換範例與限制](docs/development-modes.md)

---

## 常用指令

```bash
make help              # 顯示所有指令

make adr-new TITLE="選型理由"    # 建立 ADR
make spec-new TITLE="功能名稱"   # 建立 SPEC
make test                        # 執行測試
make audit-health                # 專案健康審計（7 維度）
make autopilot-init              # 建立 ROADMAP.yaml
make srs-new / sds-new / uiux-spec-new / deploy-spec-new  # 前置文件
```

> 完整指令列表請執行 `make help`。

---

## SPEC 驅動開發

SPEC 定義需求、邊界條件、測試驗收標準，是 ASP 開發的核心單位。

```
SPEC「Done When」→ TDD 先寫測試 → 實作讓測試通過 → 驗收
```

| 情境 | 是否需要 SPEC |
|------|-------------|
| 新功能開發 | **是**（預設） |
| 非 trivial Bug 修復 | **是** |
| trivial（單行/typo/配置） | 可跳過，需說明理由 |

> 📖 [Done When 模板、ADR↔SPEC 連動](docs/spec-driven-dev.md)

---

## 任務協調與專案健康審計

`orchestrator: enabled` 時，ASP 自動掃描專案健康度（7 維度）並將任務分類路由到對應工作流（5 種類型）。

> 📖 [健康審計維度、任務路由規則](docs/task-orchestration.md)

---

## Autopilot 模式

`autopilot: enabled` 讓 AI 讀取 `ROADMAP.yaml`，零確認持續執行所有任務，直到完成或 token 耗盡。支援跨 session 自動續接。

```
安裝 ASP → 建前置文件 → autopilot-init → 填寫 ROADMAP
→ autopilot-validate（自動產生 CLAUDE.md 專案描述）→ 啟動 → 持續執行
```

`make autopilot-validate` 會從 ROADMAP.yaml + `.ai_profile` + SRS 自動產生 CLAUDE.md 的「專案概覽」區塊，讓 AI 首次讀取時即掌握專案全貌。

> 📖 [完整 onboarding 流程、ROADMAP 結構、零確認策略](docs/autopilot.md)

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
自主開發 Profile（autonomous_dev）
  ↓ 依 .ai_profile autonomous 載入（可選）
Autopilot Profile（autopilot）
  ↓ 依 .ai_profile autopilot 載入（可選，為 autonomous 的上層調度）
選配 Profile（rag / guardrail / design / coding_style / openapi / frontend_quality）
  ↓ 依 .ai_profile 各欄位載入（可選）
```

**RAG 模式的作用**：當 Profiles 太多時，不再全部塞進 context，
改由 AI 主動查詢 `make rag-search` 按需召回相關規則，解決 context 飽和問題。

> 📖 [專案結構、Profile 表達方式](docs/project-structure.md)

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
