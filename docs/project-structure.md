<!-- Last Updated: 2026-05-09 | Status: Active | Audience: All users -->
# 專案結構

ASP v4.0 採用 **User-level 架構**：核心一次安裝到 `~/.claude/`，所有專案共用。每個專案只需三個輕量檔案。

---

## User-level（~/.claude/）— 所有專案共用

```
~/.claude/
├── CLAUDE.md                    # ASP user-level 鐵則（所有專案繼承）
├── scripts/
│   └── asp-sync.sh              # 同步更新腳本（bash ~/.claude/scripts/asp-sync.sh）
├── skills/asp/                  # ASP Claude Code Skills（23 個）
│   ├── SKILL.md                 # 意圖路由器
│   ├── asp-plan.md              # 功能規劃工作流
│   ├── asp-ship.md              # 提交前驗證（10 步）
│   ├── asp-gate.md              # Pipeline gates G1-G6
│   ├── asp-audit.md             # 專案健康審計
│   ├── asp-review.md            # 程式碼審查
│   ├── asp-autopilot.md         # ROADMAP 執行引擎
│   ├── asp-reality-check.md     # 懷疑主義驗收
│   ├── asp-external-review.md   # Layer 3 跨廠商審查
│   └── ...（共 23 個）
└── asp/                         # ASP 核心（profiles/hooks/templates）
    ├── hooks/
    │   ├── session-audit.sh     # SessionStart hook（審計 + BLOCKER）
    │   ├── clean-allow-list.sh  # 清理危險 allow 規則
    │   └── denied-commands.json # 動態 deny 黑名單
    ├── profiles/
    │   ├── global_core.md       # 全域準則（所有專案必載）
    │   ├── system_dev.md        # 系統開發（ADR/TDD/Docker）
    │   ├── content_creative.md  # 文字專案
    │   ├── task_orchestrator.md # 任務分治（v4.3 起含 multi-agent Part G）
    │   ├── autonomous_dev.md    # AI 全自動開發
    │   ├── guardrail.md         # 範疇限制
    │   └── ...（共 15 個）
    ├── templates/
    │   ├── ADR_Template.md
    │   ├── SPEC_Template.md
    │   ├── example-profile-spike.yaml
    │   └── ...
    ├── levels/
    │   ├── level-0.yaml         # L0 Spike
    │   ├── level-1.yaml         # L1 Starter
    │   └── ...（level-0 ~ level-5）
    ├── agents/                  # 角色定義 + 團隊組成
    ├── config/                  # 量化品質閾值
    └── VERSION                  # ASP 版本號
```

---

## 每個專案（輕量層）

```
your-project/
├── .ai_profile                  # 專案設定（type/level/mode/hitl）
├── CLAUDE.md                    # 精簡版行為設定（≤15 行，引用 user-level）
│
├── .claude/
│   └── settings.json            # SessionStart hooks（指向 ~/.claude/asp/hooks/）
│
└── docs/
    ├── adr/                     # 架構決策紀錄（使用者撰寫）
    └── specs/                   # 功能規格書（使用者撰寫）
```

### .ai_profile 範例

```yaml
type: system          # system | content | architecture
level: 2              # L0-L5 成熟度等級
mode: auto            # auto | multi-agent
workflow: standard    # standard | vibe-coding
hitl: standard        # strict | standard | minimal
guardrail: enabled
coding_style: enabled
name: my-project
```

### CLAUDE.md 精簡版範例

```markdown
# my-project — AI 行為設定

> ASP v4.0 | 讀取順序：本檔案 → `.ai_profile` → `~/.claude/CLAUDE.md`（user-level 鐵則）
> Profile 邏輯與 ASP skills 詳見 `~/.claude/asp/profiles/` 與 `~/.claude/skills/asp/`

## 特殊規則（選填）

[例如：禁止修改 legacy/ 目錄]
```

---

## 安裝與移除

```bash
# 安裝（一次性，所有專案共用）
bash <(curl -fsSL https://raw.githubusercontent.com/astroicers/AI-SOP-Protocol/main/.asp/scripts/install.sh)

# 更新 ASP（同步到最新版本）
bash ~/.claude/scripts/asp-sync.sh

# 移除當前專案的 ASP 設定
bash <(curl -fsSL https://raw.githubusercontent.com/astroicers/AI-SOP-Protocol/main/.asp/scripts/uninstall.sh)

# 移除 user-level ASP（~/.claude/）
bash <(curl -fsSL https://raw.githubusercontent.com/astroicers/AI-SOP-Protocol/main/.asp/scripts/uninstall.sh) --user-level
```

---

## Profile 表達方式

Profiles 使用分層混合的表達格式，依內容性質選用最適合的格式：

| 層級 | 格式 | 範例 |
|------|------|------|
| 設計哲學 | 自然語言 | CLAUDE.md 鐵則、profiles 開頭說明 |
| 決策流程 | **Pseudocode** | guardrail 三層策略、HITL 暫停矩陣、RAG 查詢 |
| 技術執行 | Bash / Make | session-audit.sh、Makefile |
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
