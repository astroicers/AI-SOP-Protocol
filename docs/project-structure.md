# 專案結構

```
your-project/
├── CLAUDE.md                    # Claude Code 主入口（鐵則 + Profile 對應表）
├── Makefile                     # 指令封裝
├── .ai_profile                  # 專案設定（type/mode/workflow/hitl）
├── .gitignore
│
├── .claude/
│   ├── settings.json            # SessionStart Hook 設定（install.sh 自動建立）
│   └── skills/asp/              # Claude Code 原生 Skills（5 個）
│       ├── SKILL.md             # 意圖路由器
│       ├── asp-plan.md          # 功能規劃工作流
│       ├── asp-ship.md          # 提交前驗證
│       ├── asp-audit.md         # 專案健康審計
│       ├── asp-review.md        # 程式碼審查
│       └── asp-autopilot.md     # ROADMAP 執行引擎
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
│   │   ├── autonomous_dev.md    # AI 全自動開發模式
│   │   ├── rag_context.md       # Local RAG 整合
│   │   ├── guardrail.md         # 範疇限制與敏感資訊保護
│   │   ├── design_dev.md        # UI/UX 設計治理
│   │   ├── coding_style.md      # 程式碼風格治理
│   │   ├── openapi.md           # API-First 工作流
│   │   ├── frontend_quality.md  # 前端工程品質驗證
│   │   ├── task_orchestrator.md # 任務協調 + 專案健康審計
│   │   └── autopilot.md        # ROADMAP 驅動持續執行（零確認）
│   ├── templates/
│   │   ├── ADR_Template.md
│   │   ├── SPEC_Template.md
│   │   ├── Postmortem_Template.md
│   │   ├── architecture_spec.md
│   │   ├── workflow-design.md              # 設計工作流範本
│   │   ├── ROADMAP_Template.yaml           # Autopilot ROADMAP 模板
│   │   ├── SRS_Template.md                # 需求規格模板
│   │   ├── SDS_Template.md                # 設計規格模板
│   │   ├── UIUX_SPEC_Template.md          # UI/UX 規格模板
│   │   ├── DEPLOY_SPEC_Template.md        # 部署規格模板
│   │   ├── example-profile-system.yaml     # .ai_profile 範例（system 專案）
│   │   ├── example-profile-content.yaml    # .ai_profile 範例（content 專案）
│   │   └── example-profile-full.yaml       # .ai_profile 範例（全功能）
│   ├── scripts/
│   │   ├── install.sh           # 一鍵安裝（含 SessionStart Hook 設定）
│   │   └── rag/
│   │       ├── build_index.py   # 建立向量索引
│   │       ├── search.py        # 查詢知識庫
│   │       └── stats.py         # 統計資訊
│   ├── Makefile.inc               # Autopilot + 文件 targets（非破壞性 include）
│   ├── VERSION                    # ASP 版本號
│   └── advanced/
│       └── spectra_integration.md
│
└── docs/
    ├── adr/                     # 架構決策紀錄
    └── specs/                   # 功能規格書
```

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
