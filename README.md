# AI-SOP-Protocol (ASP)

> 把開發文化寫成機器可讀的約束，讓 AI 自動遵守。

不需要每次都提醒 AI「記得寫測試」「不要亂推版」「更新文件」。

---

## 快速安裝

```bash
curl -sSL https://raw.githubusercontent.com/YOUR_USERNAME/ai-sop-protocol/main/scripts/install.sh | bash
```

或手動複製：

```bash
cp CLAUDE.md /your-project/
cp -r profiles/ templates/ scripts/ /your-project/
cp Makefile /your-project/   # 若無衝突
cp .gitignore /your-project/ # 若無衝突
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
name: your-project
```

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

## 專案結構

```
ai-sop-protocol/
├── CLAUDE.md                    # Claude Code 主入口（壓縮版，~500 tokens）
├── Makefile                     # 指令封裝
├── .gitignore
│
├── profiles/
│   ├── global_core.md           # 全域準則（所有專案必載）
│   ├── system_dev.md            # 系統開發（ADR/TDD/Docker）
│   ├── content_creative.md      # 文字專案（排版/Markdown）
│   ├── multi_agent.md           # 任務分治（實作期並行）
│   ├── committee.md             # 角色委員會（決策期辯論）
│   ├── vibe_coding.md           # 規格驅動工作流
│   ├── rag_context.md           # Local RAG 整合
│   └── guardrail.md             # 範疇限制與敏感資訊保護
│
├── templates/
│   ├── ADR_Template.md
│   ├── SPEC_Template.md
│   ├── architecture_spec.md
│   ├── .ai_profile.system       # 一般系統專案設定範本
│   ├── .ai_profile.full         # 完整功能設定範本
│   └── .ai_profile.content      # 內容專案設定範本
│
├── scripts/
│   ├── install.sh               # 一鍵安裝
│   └── rag/
│       ├── build_index.py       # 建立向量索引
│       ├── search.py            # 查詢知識庫
│       └── stats.py             # 統計資訊
│
├── advanced/
│   └── spectra_integration.md   # Binary Shadowing 進階整合
│
└── docs/
    └── adr/                     # 架構決策紀錄（安裝後自動建立）
```

---

## Profile 分層設計

```
鐵則（CLAUDE.md）
  ↓ 所有專案，不可覆蓋
全域準則（global_core.md）
  ↓ 溝通規範、副作用防護、連帶修復
專案類型 Profile（system / content）
  ↓ 依 .ai_profile type 載入
作業模式 Profile（multi-agent / committee）
  ↓ 依 .ai_profile mode 載入（可選）
開發策略 Profile（vibe-coding）
  ↓ 依 .ai_profile workflow 載入（可選）
選配 Profile（rag / guardrail）
  ↓ 依 .ai_profile 各欄位載入（可選）
```

**RAG 模式的作用**：當 Profiles 太多時，不再全部塞進 context，
改由 AI 主動查詢 `make rag-search` 按需召回相關規則，解決 context 飽和問題。

---

## 設計哲學

**從「規則替代判斷」到「規則賦能判斷」。**

- 鐵則（不可繞過）只有 4 條，其他都是預設值
- 預設值可跳過，但必須說明理由——這讓 Claude 學會判斷，而不只是服從
- 護欄預設「詢問與引導」，不是「拒絕」
- 一條有條件的規則，勝過三條無條件的規則
