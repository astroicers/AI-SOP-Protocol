# SPEC-016：PreToolUse git-guardrails — 擋本地毀滅性 git（借鏡 mattpocock/git-guardrails-claude-code）

| 欄位 | 內容 |
|------|------|
| **規格 ID** | SPEC-016 |
| **關聯 ADR** | ADR-030（Accepted，分層 hybrid 借用；本 SPEC 為其首個 POC，回填其 Verification Evidence） |
| **估算複雜度** | 中高（比對謂詞的旗標語義比 ship-gate 細緻，見「比對判定規範」） |
| **建議模型** | Sonnet（有下方精確謂詞表即可；無表則升 Opus） |
| **HITL 等級** | standard |

---

## 🎯 目標（Goal）

新增 PreToolUse hook `.asp/hooks/pretooluse-git-guardrails.sh`，於 Bash 執行**前**攔截**本地毀滅性 git 操作**——會**不可逆銷毀未提交／未合併／未追蹤本地成果**的 git 子命令變體（`reset --hard`、`clean` 帶 force 且非 dry-run、`branch` force-delete、`checkout/restore/switch` 丟棄工作區、`stash clear/drop`、`worktree remove --force`、`git rm` 帶 force）。判定為毀滅性 → `permissionDecision:deny` + ASP 口吻 reason，並提供 escape hatch（`ASP_GIT_OK=1`，留 `GIT-GUARD` 遙測）。把「破壞性操作前須人類確認」鐵則（CLAUDE-IR-1）**本地 git 毀資料**這個目前**無機制**的子集，從散文升為硬強制。

> **借鏡定位（ADR-030 摘要處置表「VENDOR / BUILD-NATIVE」；細部分析＝研究文件 §2，「BUILD-ASP-NATIVE」一詞出處；一手行為基準＝FC-011）**：mattpocock `git-guardrails-claude-code` 的核心即「裝一個 PreToolUse hook 讓危險 git 機械上被擋」——**這就是 ASP enforcement substrate 思想的縮影**，不該是「不保證裝了」的外部依賴。故採 **BUILD-ASP-NATIVE**：依既有 `pretooluse-ship-gate.sh`（SPEC-013）樣板自寫，訊息用 ASP 鐵則語氣、過 shellcheck lint、納入 Iron Rule A、掛在 **CLAUDE-IR-1** 鐵則之下（本 hook＝該鐵則的 local git operationalization）。

### 為何要 script，而非純 `denied-commands.json` 資料（誠實 delta，回應 ADR-010）

先誠實承認：本 hook 攔截的 7 類中，**4 類的簡單形**（`reset --hard`、`branch -D`、`stash clear`、`stash drop`）**確實可**用既有的 `Bash(...)` 前綴 deny 表達——ASP 已有兩個此類機制在用：靜態 `denied-commands.json`（前綴比對）與 `session-audit.sh` 動態注入（[session-audit.sh:337](../../.asp/hooks/session-audit.sh#L337) 即以 `Bash(git commit *)` 注入 settings.local.json；行號隨版本漂移，以 `grep -n "Bash(git commit"` 定位——G2 review D2-1 改符號錨）。所以「純資料做不到」是**假命題**，不作為理由。

script 的**不可替代價值**在**前綴 deny 無法精確表達**的部分（下述 BLOCKER 級 false-positive 全出在這）：

| 需求 | 為何前綴 deny 做不到 |
|------|---------------------|
| **clean 的 dry-run 例外** | `Bash(git clean -f*)` 會誤擋安全的 `git clean -nfd`（dry-run+force 同存＝git 只印不刪）；需檢查「有 force **且無** dry-run」 |
| **restore 的 staged/worktree 判別** | `git restore --staged x`（安全 unstage）是 `git restore x`（毀工作區）的**字串超集**；前綴無法「擋後者放前者」 |
| **checkout 的 branch/pathspec 判別** | `git checkout hardening`（切到名為 hardening 的分支，安全）vs `git checkout .`（毀工作區）；子字串比對會誤擋含 `hard` 的分支名 |
| **branch 的大小寫判別** | `-d`（安全刪已合併）vs `-D`（force 刪未合併）僅差大小寫；前綴表無法保證 case-sensitive |
| **global option 跳過** | `git -C /other reset --hard`：git 全域選項在子命令前，前綴 `git reset` 比對不到 |

外加三個**橫切**價值：統一 **`GIT-GUARD` 遙測**（rule-stats 可見嘗試率）、**可稽核 escape hatch**（bypass 留痕，非無聲放行）、**單一內聚護欄**（而非散落多條 deny 字串）。

> **一個誠實的替代**：若團隊只要最小防護，可只把上述 4 類簡單形寫進 `denied-commands.json`，跳過本 hook。本 SPEC 選 script＝為了那 3 類無法用資料精確表達者 + 橫切價值；此權衡明列於此，供審查裁量（ADR-010）。

### 覆蓋範圍的誠實界定（回應「勿宣稱全貌」）

`denied-commands.json` 以**粗前綴**覆蓋 **檔案系統毀滅（`rm -rf`）＋ 遠端／共享歷史（`push --force/-f`、`push origin main`、`rebase`、`gh pr merge`、`docker push`）**。本 hook 以**旗標精確**覆蓋 **本地 git 工作區／分支／stash 毀滅**。二者合起來覆蓋 CLAUDE-IR-1 的**核心子集**，**非全貌**——殘留邊界（`push --force-with-lease`、歷史重寫冷門者、alias/`-c`/`update-ref -d` 注入）明列於「誠實能力邊界」與「Out of Scope」，**不宣稱已擋**。

---

## 📥 輸入規格（Inputs）

| 參數名稱 | 型別 | 來源 | 限制條件 |
|----------|------|------|----------|
| hook stdin | JSON | Claude Code PreToolUse（FC-002） | 含 `tool_name`、`tool_input.command` |
| `ASP_GIT_OK` | **環境變數** | hook 自身執行環境 | escape hatch：`${ASP_GIT_OK:-}` = `1` 放行。**語義同 ship-gate 之 `ASP_SHIP_OK`**（[ship-gate:71](../../.asp/hooks/pretooluse-ship-gate.sh#L71) 讀自身 env，不解析 command 字串；行號隨版本漂移，以 `grep -n ASP_SHIP_OK` 定位） |

> **escape hatch 語義（修正 D1 矛盾）**：`ASP_GIT_OK` 由 hook **從自身環境**讀取，**不是**去解析 `tool_input.command` 裡的內嵌賦值。故測試放行案例必須以 **env 前綴於 hook 呼叫**（`ASP_GIT_OK=1 run_hook "git reset --hard"`），而非把 `ASP_GIT_OK=1 git reset --hard` 當成 command 字串傳入（後者的賦值只會進「將被執行的 Bash」env，不進 hook env）。deny reason 的 UX 措辭沿用 ship-gate 慣例（見輸出規格），其「inline 前綴是否入 hook env」之 harness 行為**與 ship-gate 同源**——若 ship-gate 的 inline escape 在此環境可用，本 hook 亦然（此 harness 行為屬 ship-gate 既有假設，非本 SPEC 新增宣稱）。
> 本 hook **無狀態**（不讀 `.asp-test-result.json` 之類痕跡）——判定純由 `tool_input.command` 的**語法/argv**決定。

---

## 📤 輸出規格（Expected Output）

hook 解析 `tool_input.command`，輸出 **方式 A**（FC-002：`exit 0` + JSON）：

| 情境 | permissionDecision | 遙測 |
|------|-------------------|------|
| command 不含本地毀滅性 git（含所有安全變體：見 Edge Cases） | `defer`（交回預設，不干擾） | 不寫 |
| command 含本地毀滅性 git + `ASP_GIT_OK=1`（hook env） | `defer`（放行） | `GIT-GUARD` bypass |
| command 含本地毀滅性 git（指令位置、謂詞命中） | **`deny`** + reason（見下） | `GIT-GUARD` block |
| jq 缺 | `defer`（**fail-open**：機制異常放行＋stderr WARN 留痕，符合 CONTEXT.md fail-open 語意） | 不寫 |
| stdin 空／無法解析／無 command | `defer`（**no-op**：無輸入可判定、非 fail-open 事件，**靜默**沿 ship-gate L20 慣例——CONTEXT.md fail-open 之「留痕」子句僅適用機制異常路徑，G2 review D6-2 釐清） | 不寫 |

> deny reason（ASP 口吻）：`「ASP git-guardrails：偵測到本地毀滅性操作 <matched>，將不可逆銷毀本地成果（未提交變更/未合併分支/未追蹤檔）。破壞性操作前須人類確認（鐵則 CLAUDE-IR-1）。確認要執行 → 在 Claude Code 啟動環境設 ASP_GIT_OK=1 後重試（會留 GIT-GUARD 遙測）；否則請改用非破壞替代（git stash 代 reset --hard、git clean -n 先預覽、git branch -d 代 -D）。」`
> deny 用 `{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"..."}}`，`exit 0`。

---

## 🧭 比對判定規範（Matching Predicate Spec — 本 SPEC 之核心）

> 審查證明「粗略字串 contains」會同時 **over-block**（誤擋日常）與 **under-block**（漏危險）。以下謂詞為**規範性**（實作 hook 必須符合），測試矩陣逐條對應。

### M0. 分段與 tokenize（前置）
1. **命令分段**：以 shell 邊界 `;`、`&&`、`||`、`|`、換行 切成 segment；**引號內的邊界字元不算分段**（best-effort：辨識成對 `'...'` / `"..."`，使 `git commit -m "a && git reset --hard"` 的 `&&` **不**被當分段點）。→ 逐 segment 套 M1。
2. **argv tokenize**：每個 segment 以空白切為 token 序列（best-effort，尊重引號）。
2b. **redirect 剝除（OB-02，實作審查後補規範）**：tokenize 後須移除 shell redirect 序列（`>`/`>>`/`<`/`2>`/`2>&1`/`&>` 等，含黏著目標 `2>/dev/null` 與分開形 `> file`）——redirect 是 **shell 語法、非命令參數**，不得進入 argv 參與 positional 計數。否則 `git checkout main 2>/dev/null` 的 `2>/dev/null` 會被當第二個 positional → checkout 誤判 `<ref> <pathspec>` → **over-block** 極常見的日常命令。純 operator（結尾為 `>`/`<`）連同下一個 token（目標）一併剝除；自含 operator（`2>&1`/`2>/dev/null`）剝除自身。
3. **git 起始判定**：segment 首個非賦值 token（跳過 `VAR=val` 前綴）須為 `git`，否則該 segment 非 git、跳過。
4. **global option 跳過（修正 B1）**：`git` 之後、子命令之前的**全域選項**必須跳過再取子命令：跳過任何 `-*` token；其中 `-C`、`-c`、以及 `--git-dir`/`--work-tree`/`--namespace`/`--super-prefix` 之**空白分隔形**（無 `=`，如 `git --git-dir /x.git reset --hard`）**各再吃掉下一個 token**（其參數）；含 `=` 者（`--git-dir=/x`）為單 token。（**`--exec-path` 刻意不列入空白分隔集**：git 對裸 `--exec-path` 為「印出 exec-path 後即 `exit 0`」、僅 `=` 形設值，**永不**吃空白下一 token（**FC-013 一手實測**：`git --exec-path reset --hard` 僅印路徑、不執行 reset）；若誤列，`git --exec-path reset --hard` 會把 `reset` 當其參數吃掉致漏解析——雖 git 本身此式也不執行 `reset`，仍屬對 git 文法的錯述，故剔除。）跳完的第一個非選項 token＝**子命令**。→ `git -C /x reset --hard`、`git --git-dir /x.git reset --hard`、`git --git-dir=/x.git reset --hard` 的子命令均正確解析為 `reset`（修正 Probe 揪出的空白分隔形漏解析）。
5. **比對規則**：所有旗標比對 **case-sensitive**（`-d`≠`-D`、`-c`≠`-C`、`-n`≠`-N`）、**以 token 為單位**（非子字串）。短旗標**捆綁**（如 `-fd`）視為其字母集合 `{f,d}`；長旗標整 token 比對。**位置參數**（positional）＝非 `-` 開頭且非選項參數的 token。
   > **已知限制（見「誠實能力邊界」）**：git 長選項接受**唯一前綴自動補全**（`git reset --har`＝`--hard`、`--f`＝`--force`），本規範以**字面 token** 比對、不做前綴正規化 → 這類縮寫會漏擋，屬明列的能力邊界而非隱性缺陷。
   > **捆綁 force 的順序感知（G2-impl review UB-01 補強，rule #5 之具體化）**：短旗標捆綁展開適用於 `-f`/force 判定，但**需參數的短旗標**（checkout/switch 的 `-b`/`-B`/`-c`/`-C`）其後字母是**參數**非旗標——`git checkout -Bf origin`＝建分支「f」（放行），`git checkout -qf`＝quiet+force（**擋**）。故 switch/checkout 的 force 捆綁比對須**掃到需參數旗標即停**（其後為參數）。此為 rule #5 對「需參數旗標」的正確詮釋，非例外。

### M1. 逐子命令謂詞

| 子命令 | **DENY 當** | **ALLOW（defer）** |
|--------|-------------|-------------------|
| `reset` | argv 含 token `--hard` | `--soft` / `--mixed`（預設）/ `--keep` / `reset HEAD <f>` / `reset <ref>` / `reset hard`（`hard` 是 ref 名，非旗標） |
| `clean` | 有 force（token `--force` 或短捆綁含 `f`）**且無** dry-run（token `--dry-run` 或捆綁含 `n`）**且無** interactive（`--interactive` 或捆綁含 `i`） | `-n`/`--dry-run`（含 `-nfd`）、`-i`/`--interactive`、無 `-f`（git 自身拒絕） |
| `branch` | token `-D`；或捆綁含 `D`；或（delete 意圖 `-d`/`--delete`/捆綁含 `d`）**且**（force 意圖 `-f`/`--force`/捆綁含 `f`） | `-d`/`--delete` 單獨（僅刪已合併，git 拒未合併）、`branch <name>`、`-m`/`-M`（改名，另議見邊界） |
| `checkout` | token `-f`/`--force`**或捆綁含 `f` 獨立旗標**（順序感知：掃到 `-b`/`-B` 即停，UB-01）；**或**〔先決：**不含** `-p`/`--patch` 互動、**且不含** `-b`/`-B`/`--orphan` 建分支〕下：出現 `--`（顯式 pathspec 丟棄）／跳選項後**唯一** positional 為 `.`（不再字面比對「恰為 `checkout .`」，修正 `-q .` 破解）／跳選項後 **≥2 個 positional**（`<ref> <pathspec>` 還原路徑） | 單一 positional（分支切換，如 `checkout hardening`）、`-b`/`-B`/`--orphan`（建立分支：**先決條件已整體排除此類**，故其後 branch-name／start-point 從不進入 positional 計數；`-Bf origin` 的 `f`＝分支名非旗標，不誤命中）、`-`、`-p`/`--patch`（互動 hunk，user-in-loop）；`-B`/`--orphan` 覆蓋 ref 之議見 Out of Scope |
| `restore` | 〔先決：**不含** `-p`/`--patch` 互動〕**工作區受影響**：有 `-W`/`--worktree`（含捆綁 `-SW`/`-WS`）；**或** 既無 `-S`/`--staged` 亦無 `-W`（預設 target＝工作區） | `-S`/`--staged` 單獨（僅 unstage，不動工作區）、`-p`/`--patch`（互動：git 逐 hunk 提示、user-in-loop → defer，不論 `-S`/`-W`，修正 Probe 揪出的 `restore -p` 誤擋） |
| `switch` | token `-C` **或捆綁含 `C`**（force-create，順序感知：掃到 `-c` 即停）**或 `--force-create`**（≠`-c`）；或 `--discard-changes`；或 `-f`/`--force`**或捆綁含 `f` 獨立旗標**（順序感知：掃到 `-c`/`-C` 即停，UB-01；`--discard-changes` 別名） | `-c`（建立）、`-cf origin` 的 `f`＝分支名非旗標、`-`（回上一分支）、`switch <branch>` |
| `stash` | 子命令參數為 `clear` 或 `drop` | `push`/`save`/`pop`/`apply`/`list`/`show`/無參數 |
| `worktree` | **子命令**為 `remove`（`worktree` 後**第一個非選項參數**）**且** 有 `-f`/`--force`（含 `-ff`） | `remove` 無 force（git 拒 dirty）、`add`/`list`/`prune`/`move`/`lock`；`add … remove`（`remove` 為 commit-ish/路徑字面、非子命令位置 → **不誤擋**，修正 Probe 揪出的字面誤命中） |
| `rm` | 有 force（token `--force` 或短捆綁含 `f`，如 `-f`/`-rf`/`-fr`） | `--cached`（僅 unstage）、`git rm <f>` 無 force（git 拒已改動；且已提交者可復原） |

> 未列於上表的子命令（`add`/`commit`/`status`/`log`/`push`/`fetch`/`pull`/`merge`/…）一律 **defer**。`push` 家族由 `denied-commands.json` 既有層處理，本 hook 不重複。

---

## 🔗 副作用與連動（Side Effects）

| 副作用 | 觸發條件 | 影響的系統/模組 | **驗證方式** |
|--------|---------|----------------|------------|
| `.claude/settings.json` `PreToolUse`（matcher `Bash`）增列本 hook（**與 ship-gate 並存**） | 安裝後每次 Bash 呼叫 | Claude Code hook 系統（本地開發者） | `jq '.hooks.PreToolUse'` 含兩支 hook |
| **`hooks/hooks.json`（plugin manifest）`PreToolUse[0].hooks[]` 增列本 hook 為第二項**（ship-gate 仍居 `[0].hooks[0]`） | plugin 安裝（ADR-021 `/plugin marketplace add`）者 | Claude Code plugin 分發通道 | `test_plugin_manifest.sh`：`PreToolUse[0].hooks[0]`=ship-gate 不變、`refs≥4`、新增 git-guardrails 存在斷言 |
| 新 hook 腳本 `.asp/hooks/pretooluse-git-guardrails.sh` | 每次 Bash 呼叫 | 本地毀資料強制力 | `tests/test_pretooluse_git_guardrails.sh` |
| 寫 `GIT-GUARD` 至 `rule-hits.jsonl` | 命中 block/bypass 時 | 遙測（rule-stats） | `make rule-stats` 含 GIT-GUARD |
| hook 納入 Iron Rule A `CRITICAL_FILE` | session-audit 每次 | **偵測**「改 hook 繞過」（tamper-evidence：下次 SessionStart hash 比對→BLOCKER，非即時阻擋） | `tests/test_iron_rule_a_coverage.sh` 含此 hook |
| rule-registry 登記 `GIT-GUARD`（**`exempt: true`**、**`observed_by: pretooluse-git-guardrails`**——比照 SHIP-GATE 前例；registry 檔頭 enum 未含 hook 值屬既有漂移，修檔頭列 follow-up 非本 SPEC，G2 review D6-1），掛 CLAUDE-IR-1 之下 | 一次性 | 規則治理 | `tests/test_rule_registry.sh` **新增 GIT-GUARD 顯式斷言**（見 Done When D2） |

> **`exempt: true` 之必要（ADR-018 規則存留治理）**：安全護欄「90 天零命中」代表**期間無人嘗試危險操作＝成功**，非死規則。`GIT-GUARD` 實作 CLAUDE-IR-1（破壞性操作防護鐵則）的 local 子集，與鐵則同類，豁免「零命中即評估移除」。

---

## ⚠️ 邊界條件（Edge Cases）

**必須擋（DENY）** — 見「比對判定規範」M1；補列易漏變體：
- global option 前綴：`git -C /path reset --hard`、`git -c x=y clean -fd` → 跳全域選項後仍命中。
- `git switch -f` / `--force` / `--discard-changes`（`-f` 是 `--discard-changes` 別名，勿只擋長式）。
- `git worktree remove -f <path>`（ASP 為 worktree-centric，此比 `reset --hard` 更不可逆——毀整個 linked worktree 的未提交+未追蹤）。
- `git rm -f` / `-rf`（**注意**：`git rm` 起始為 `git` 非 `rm`，故 `denied-commands.json` 的 `rm -rf` **擋不到**它）。
- `git restore -SW file` / `-WS file`（`-W` 在捆綁內 → 工作區受影響 → DENY，勿被 `-S` 誤放行）。
- `git checkout main src/` / `git checkout HEAD~1 -- f`（≥2 positional 或 `--` → pathspec 還原 → DENY）。

**必須放行（DEFER，防過度攔截／開發者日常）：**
- **`git clean -nfd` / `-nf`（BLOCKER 修正）**：dry-run 與 force 同存 → git 只印 `Would remove`、**不刪** → 必須 ALLOW（「先預覽再執行」是每日首步）。
- `git checkout hardening` / `git switch hotfix`（分支名含 `hard`/`fix` 子字串 → token 比對＝分支切換 → ALLOW）。
- `git reset hard`（`hard` 是 ref 名、非 `--hard` 旗標 → mixed reset → ALLOW）。
- `git clean -n` / `--dry-run` / `-i`；`git reset` / `--soft` / `reset HEAD <f>`；`git checkout <branch>` / `-b` / `-`；`git switch <branch>` / `-c` / `-`；`git restore --staged <f>` / `-S`；`git branch -d <merged>`；`git rm --cached`；`git worktree remove`（無 force）；`git stash` / `pop` / `apply`。
- **互動模式**（`git clean -i`、`git checkout -p`、`git restore -p`）→ ALLOW：git 逐項提示、使用者在迴圈中確認，非無聲毀滅（一致原則：interactive = user-in-loop）。列為**已知較寬邊界**。
- **字串內誤判**：`git log --grep="reset --hard"`、`git commit -m "wip: git reset --hard 筆記"` → M0 引號感知分段使 **defer**（非指令位置）。
- `push --force`/`-f`/`rebase`/`gh pr merge` 等 → `denied-commands.json` 既有層職責，本 hook 命中與否皆 defer（避免雙重維護）。

**指令位置偵測**：見 M0（引號感知分段 + argv tokenize）。複合 `git add . && git reset --hard` → `&&` 後 segment 命中 DENY。

**escape hatch**：`ASP_GIT_OK=1`（hook env）→ 放行 + 記 `GIT-GUARD` bypass。

**fail-open**：jq 缺 → defer + WARN（留痕）；stdin 空/無法解析 → defer 靜默（no-op、非 fail-open 事件，同 ship-gate）。**絕不死鎖**。

**hook 自身被改繞過** → Iron Rule A **偵測**（CRITICAL_FILE hash 比對，下次 SessionStart 出 BLOCKER；tamper-evidence 非即時阻擋——同 session 內改 hook 要到下次 SessionStart 才被偵測。ADR-019「看守者的看守者」）。

### 🕳️ 誠實能力邊界（本 hook 明確**不宣稱**擋得住，B7/ADR-019）

- **user alias 注入**：`git -c alias.x='!git reset --hard' x`、或既存 `~/.gitconfig` 別名解析成毀滅操作 → tokenize 看到的是 `x`，擋不到。
- **底層 ref 操作繞過**：`git update-ref -d refs/heads/x`（繞 branch -D 偵測）、`git reflog expire --expire=now`、`filter-branch`、`gc --prune=now`。
- **極端引號/heredoc**：M0 為 best-effort，巢狀引號或 heredoc 內的分段可能殘留誤判 → 此時 escape hatch + fail-open 兜底。
- **寫檔再執行**：AI 寫一個含危險 git 的 `.sh` 再 `bash x.sh` → 本 hook 只看單一 Bash command，不追檔內容。
- **redirect 無空白黏 token（OB-02 修復後獨立審查揭示的既有 tokenizer 邊界）**：`git reset --hard>out.txt`（`>` 無空白緊黏旗標）→ tokenize 得單一 token `--hard>out.txt`，`_arg_has "--hard"` 精確比對失敗 → 漏擋。**有空白形式（`--hard >out.txt`、`--hard 2>/dev/null`）由 `_strip_redirects` 正確剝除、正常擋下**；僅完全無空白黏著這種罕見寫法漏。緩解＝正規寫法皆有空白；徹底修需 tokenizer 在 metachar 邊界二次分段（POC 不納，避免 over-engineering）。
- **harness 攔截語義（G2 review D5-1 補聲明，對齊 FC-011 unknown #1）**：本 hook 採**方式 A**（`exit 0` + JSON `permissionDecision:deny`，FC-002 官方介面 + ship-gate 生產實證），**不依賴**原生 skill 的 `exit 2` 語義（後者對 harness 的實際效果未一手實證，FC-011 unknown #1）；方式 A 之 deny 若因 harness 版本變動失效，本 hook 退化為無強制力的 no-op（fail-open 家族），不會誤擋。

**（以下 5 類由本 session 對抗式 Probe 稽核揪出、實測確認，明列為能力邊界而非隱性缺陷）**

- **長選項前綴自動補全**：git 接受唯一前綴（`git reset --har`＝`--hard`、`git clean --for`＝`--force`、`git branch --delet`＝`--delete`；**FC-013 一手實測：`reset --har` 真的以 `--hard` 執行並毀 dirty 變更**）。M0.5 以字面 token 比對、不做前綴正規化 → 這類縮寫漏擋。此為跨子命令問題；緩解僅靠 escape hatch 不受影響 + 未來可加「每子命令選項唯一前綴白名單」正規化（POC 不納，避免 FP-prone 的前綴消歧）。
- **命令替換／子 shell 內的巢狀 git**：`git commit -m "$(git reset --hard)"`、反引號同理——雙引號內 `$(...)` **先於**外層執行，外層 `commit` 不在 DENY 表 → defer。本 hook **不遞迴解析**命令替換內容（遞迴會顯著增加剖析複雜度，且此形態偏向蓄意而非意外）。
- **執行檔包裝前綴**：`\git reset --hard`（反斜線抑制 shell 別名）、`env git …`、`command git …`、`sudo git …`、`nice/time/nohup git …`。M0.3 以字面**首 token** `git` 判定，這類包裝的首 token 非 `git` → 漏判。
- **單一 positional 為「已追蹤檔路徑」而非分支**：`git checkout <trackedfile>`（無 `--`、無 `-b`）git 會**靜默丟棄該檔工作區改動**；本 hook **無法查 repo state** 分辨「positional 是分支還是檔路徑」，一律當分支切換 defer → 這類漏擋。（對照：`git restore <path>` 已由「既無 `-S` 亦無 `-W`」擋下；`checkout <path>` 因「單 positional＝分支」假設而漏，屬同根因的殘留。）
- **`git branch -f <name> [<start>]` 移動既有 ref**：可孤立未合併 commit。因 hook 無法由字串分辨 `create`（對不存在分支＝安全建立）vs `move`（對既有分支＝毀 ref），且此操作 **reflog 可復原**，選擇**不擋**——避免對常見的 `branch -f <新名>` 建立/冪等式**誤擋**（本 SPEC 核心即在杜絕 false-positive）。對照 `switch -C`／`--force-create` 採**保守擋下**，因其**另含工作區切換**（風險面較 `branch -f` 純 ref 移動大）。此不對稱為刻意、已揭露之取捨。

> **威脅模型定位**：本 hook 針對**意外的**AI/人毀滅操作（最常見面）；**蓄意**繞過者非威脅模型（escape hatch 本就存在）。上列邊界是誠實揭露，不是缺陷偽裝成覆蓋。

### 🔄 Rollback Plan

| 項目 | 說明 |
|------|------|
| **回滾步驟** | 移除 `.claude/settings.json` 與 `hooks/hooks.json` 內本 hook 的 `PreToolUse` 項（腳本留著無害；ship-gate 不受影響）→ 退回鐵則散文義務 |
| **資料影響** | 無（hook 唯讀 command 字串 + 寫遙測；不改 repo 內容、不執行任何 git） |
| **回滾驗證** | 移除後危險 git 不再被攔；`make test` 綠（`test_plugin_manifest.sh` 需同步回退 refs 斷言） |
| **回滾已測試** | ☑ 是（等效）：test 的「fail-open / 安全變體 defer」案例證明 hook 不存在/失效時行為等同無 hook |

---

## 🧪 測試矩陣（Test Matrix）

> POC 核心證據：**每個危險操作一條 DENY、每個安全同胞一條 ALLOW**——回填 ADR-030 Verification Evidence。所有 escape-hatch 案例以 **env 前綴於 run_hook**（非 command 字串）。

| # | 類型 | 輸入條件 | 預期結果 | 場景 |
|---|------|---------|---------|------|
| P1 | ✅ 正向 | `git status` / `git checkout main` / `git switch -c feat` | defer | S1 |
| P2 | ✅ 正向 | `git clean -n` / `git clean --dry-run` / `git clean -i` / `git clean -fi`（force+interactive：interactive 仍放行，驗 `!interactive` 合取） | defer | S1 |
| P3 | ✅ 正向 | `git reset --soft HEAD~1` / `git reset HEAD file` / `git reset hard`（ref 名） | defer | S1 |
| P4 | ✅ 正向 | `git restore --staged file` / `git branch -d merged` / `git rm --cached f` | defer | S1 |
| P5 | ✅ 正向 | `git checkout hardening`（分支名含 hard） / `git switch hotfix` | defer（token 比對，不誤擋） | S1 |
| P6 | ✅ 正向 | `git clean -nfd` / `git clean -nf`（**BLOCKER**：dry-run+force） | defer（git 不刪，**FC-013 一手實測**） | S1 |
| P7 | ✅ 正向 | `git worktree remove wt`（無 force） / `git stash pop` / `git stash push -m "clear cache before drop"`（訊息含 `clear`/`drop` 字串但子命令為 `push` → 驗非 substring、看子命令 token） | defer | S1 |
| P8 | ✅ 正向 | `run_hook` env `ASP_GIT_OK=1` + `git reset --hard` | defer + GIT-GUARD bypass | S1 |
| P9 | ✅ 正向 | `git checkout -b feat origin/main`（建分支+start-point，`-b` 之操作元不計 positional，故不誤命中 ≥2） | defer | S1 |
| P10 | ✅ 正向 | `git checkout -p` / `git restore -p file` / `git checkout -p HEAD~1 -- src/f`（互動 hunk，user-in-loop；`-p` 免除 `--`/≥2-positional DENY） | defer | S1 |
| P11 | ✅ 正向 | `git worktree add -f wt2 remove`（`remove` 為 commit-ish 字面、非子命令位置；`add -f` 非毀資料） | defer | S1 |
| P12 | ✅ 正向 | `git checkout --orphan gh-pages` / `git checkout -B main origin/main`（建/force-建分支，操作元不計 positional，見 Out of Scope） | defer | S1 |
| N1 | ❌ 負向 | `git reset --hard` / `git reset --hard HEAD~3` | **deny** + GIT-GUARD block | S2 |
| N2 | ❌ 負向 | `git clean -fd` / `git clean -xf` / `git clean --force` / `git clean -fdx` | **deny** | S2 |
| N3 | ❌ 負向 | `git branch -D x` / `--delete --force x` / `-Df x` / `-df x`（小寫捆綁 {d,f}，走 clause(b) 短旗標路徑） | **deny** | S2 |
| N4 | ❌ 負向 | `git checkout .` / `git checkout -q .`（`-q` 破字面「恰為 checkout .」→ 須跳選項後唯一 positional 判定） / `git checkout -- src/` / `git checkout -f` / `git checkout main foo` | **deny** | S2 |
| N5 | ❌ 負向 | `git restore .` / `git restore --worktree x` / `git restore -SW f` / `git restore -WS f`（`-W` 在捆綁兩序皆須命中） | **deny** | S2 |
| N6 | ❌ 負向 | `git stash clear` / `git stash drop` / `git switch -C main` / `git switch --discard-changes` | **deny** | S2 |
| N7 | ❌ 負向 | `git switch -f main`（`--discard-changes` 別名） / `git switch --force main` | **deny**（勿只擋長式） | S2 |
| N8 | ❌ 負向 | `git worktree remove -f wt` / `git worktree remove --force wt` / `git worktree remove -ff wt`（長式與雙 force 同擋；worktree-centric，比 reset --hard 更不可逆） | **deny** | S2 |
| N9 | ❌ 負向 | `git rm -f f` / `git rm -rf dir`（`git rm` 非 `rm`，denied-commands 擋不到） | **deny** | S2 |
| N10 | ❌ 負向 | `git -C /other reset --hard` / `git -c user.name=x clean -fd`（`-c` 帶 `=` 參數，各再吃一 token 後仍命中子命令） | **deny**（跳全域選項） | S2 |
| N11 | ❌ 負向 | `git add . && git reset --hard` / `git status; git reset --hard` / `git x || git reset --hard` / `git status \| git reset --hard`（管線）/ 多行貼上（換行分隔）（複合分隔 `&&`/`;`/`\|\|`/`\|`/換行 皆須分段偵測，見 M0.1） | **deny**（指令位置偵測） | S2 |
| N12 | ❌ 負向 | `git switch --force-create x master`（`-C` 長式，勿只擋短式，比照 N7） | **deny** | S2 |
| N13 | ❌ 負向 | `git --git-dir /tmp/o.git reset --hard`（空白分隔全域選項須吃下一 token）/ `git --git-dir=/tmp/o.git reset --hard`（`=` 形） | **deny**（跳全域選項後命中 `reset`） | S2 |
| N14 | ❌ 負向 | `FOO=bar git reset --hard`（M0.3 `VAR=val` 前綴須跳過後仍抓到 `git reset --hard`） | **deny** | S2 |
| B1 | 🔶 邊界 | `git log --grep="reset --hard"`（字串內） | defer（引號感知） | S3 |
| B2 | 🔶 邊界 | `git commit -m "wip: git reset --hard notes"`（引號內 && / 危險字串） | defer（**不 false-positive**，修正 C2） | S3 |
| B3 | 🔶 邊界 | jq 缺 | defer + WARN（harness 若有 jq 則 SKIP 此格） | S3 |
| B4 | 🔶 邊界 | stdin 空 / 無法解析 JSON | defer（**靜默**，無 WARN，同 ship-gate） | S3 |
| B5 | 🔶 邊界 | `git push --force`（既有層職責） | defer（本 hook 不重複） | S3 |
| B6 | 🔶 邊界 | `git reset --har`（長選項唯一前綴補全＝`--hard`） | defer（**已知漏擋釘樁**，非安全宣稱；見誠實能力邊界） | S3 |
| B7 | 🔶 邊界 | `git commit -m "$(git reset --hard)"`（命令替換內巢狀，`$()` 先執行、外層 `commit` 不在 DENY） | defer（**已知漏擋釘樁**，非安全宣稱） | S3 |
| B8 | 🔶 邊界 | `\git reset --hard` / `env git reset --hard`（執行檔包裝前綴，首 token 非 `git`） | defer（**已知漏擋釘樁**，非安全宣稱） | S3 |
| B9 | 🔶 邊界 | `git checkout f2.txt`（單 positional 為已追蹤檔而非分支，git 靜默丟工作區改動） | defer（**已知漏擋釘樁**，無法查 repo state 分辨；非安全宣稱） | S3 |

## 🎭 驗收場景（Acceptance Scenarios）

```gherkin
Feature: PreToolUse git-guardrails（本地毀資料操作硬強制）
  作為 ASP 強制力架構
  我想要 在偵測到本地毀滅性 git 時擋下 Bash 呼叫
  以便 防止 AI（或人）不可逆銷毀未提交/未合併的本地成果（CLAUDE-IR-1）

  Background:
    Given hook 已 wire 進 .claude/settings.json 與 hooks/hooks.json PreToolUse（matcher Bash，ship-gate 之後）

  # --- 正向 ---
  Scenario Outline: S1 - 安全操作與 escape hatch 放行
    When PreToolUse hook 判定 command "<cmd>"
    Then permissionDecision 為 defer

    Examples:
      | cmd                              |
      | git checkout main                |
      | git checkout hardening           |
      | git clean -nfd                   |
      | git reset --soft HEAD~1          |
      | git restore --staged file        |
      | git worktree remove wt           |
      | git checkout -b feat origin/main |
      | git checkout -p                  |
      | git checkout --orphan gh-pages   |

  Scenario: S1b - escape hatch（env 前綴於 hook，非 command 字串）
    Given hook 環境設 ASP_GIT_OK=1
    When PreToolUse hook 判定 command "git reset --hard"
    Then permissionDecision 為 defer
    And 寫一筆 GIT-GUARD bypass 遙測

  # --- 負向 ---
  Scenario Outline: S2 - 本地毀滅性操作被擋
    Given 未設 ASP_GIT_OK
    When AI 對 "<cmd>" 發起 Bash 呼叫
    Then permissionDecision 為 deny 且 reason 指出替代方案
    And 寫一筆 GIT-GUARD block 遙測

    Examples:
      | cmd                                   |
      | git reset --hard                      |
      | git clean -fd                         |
      | git branch -D feat                    |
      | git checkout .                        |
      | git restore --worktree x              |
      | git switch -f main                    |
      | git switch --force-create x           |
      | git worktree remove -f wt             |
      | git rm -rf dir                        |
      | git -C /other reset --hard            |
      | git --git-dir /tmp/o.git reset --hard |
      | git stash clear                       |
      | git add . && git reset --hard         |
      | FOO=bar git reset --hard              |

  # --- 邊界 ---
  Scenario Outline: S3 - 邊界不誤擋、不死鎖、不重複
    When hook 遇到 "<cond>"
    Then 結果為 "<result>"

    Examples:
      | cond                                  | result       |
      | commit -m 含引號內 git reset --hard   | defer        |
      | jq 缺                                 | defer+WARN   |
      | stdin 空                              | defer（靜默）|
      | git push --force                      | defer（既有層）|
      | git reset --har（前綴補全，B6 釘樁）  | defer（已知漏擋非安全宣稱）|
      | $(git reset --hard) 巢狀（B7 釘樁）   | defer（已知漏擋非安全宣稱）|
      | \git / env git 包裝前綴（B8 釘樁）    | defer（已知漏擋非安全宣稱）|
      | git checkout 已追蹤檔（B9 釘樁）      | defer（已知漏擋非安全宣稱）|
```

---

## ✅ 驗收標準（Done When）

- [x] `bash tests/test_pretooluse_git_guardrails.sh` 全綠（P1-12 / N1-14 / B1-9，含 BLOCKER 案 P6、global-option N10/N13、C2 案 B2、建分支不誤擋 P9/P12、互動 -p 放行 P10、--force-create N12、已知漏擋釘樁 B6-9 非安全宣稱）
- [x] hook 納入 Iron Rule A → `tests/test_iron_rule_a_coverage.sh` 含 `pretooluse-git-guardrails.sh`
- [x] **（D2）** `GIT-GUARD` 登記於 rule-registry 且 `exempt: true`，**且** `tests/test_rule_registry.sh` **新增對 GIT-GUARD 的顯式斷言**（id 存在 + `exempt:true`）——不可只靠既有泛化斷言（現況該測試對 GIT-GUARD/SHIP-GATE 皆零斷言）
- [x] **（D3）** `hooks/hooks.json` 已 wire git-guardrails 為 `PreToolUse[0].hooks[1]`（ship-gate 仍 `[0].hooks[0]`）；`tests/test_plugin_manifest.sh` 更新：`refs≥4`、`PreToolUse[0].hooks[0]`=ship-gate 不變、**新增 git-guardrails 存在斷言**
- [x] `make test` 全綠（既有零回歸）+ `make lint`（hook 過 shellcheck）
- [x] `.claude/settings.json` PreToolUse 與 ship-gate 並存（`jq` 驗證兩支皆在）
- [x] 手動驗證：`git reset --hard` 擋、`git clean -nfd` 放行、`git -C /x reset --hard` 擋、`ASP_GIT_OK=1`(env) 放行且留 bypass 遙測
- [x] **（D6）** 回填 ADR-030 `## Verification Evidence` **四欄齊全**：POC 分支/測試結果、驗證日期、驗證者、驗證摘要
- [x] CHANGELOG 更新

---

## 📊 可觀測性（Observability）

| 面向 | 說明 |
|------|------|
| **關鍵指標** | `GIT-GUARD` block/bypass 計數（`make rule-stats`）——block 高＝AI 常試危險操作（好護欄）；bypass 高＝可能過度攔截或 escape hatch 濫用，需檢視謂詞 |
| **日誌** | block/bypass 各寫一筆 jsonl；fail-open 走 stderr WARN（僅 jq 缺） |
| **告警** | 無自動告警（護欄性質）；bypass 突增由 rule-stats 人工檢視 |
| **如何偵測故障** | 危險 git 未被擋 → test 紅；hook 誤擋日常 git → 開發者回報 + rule-stats block 異常高 |
| **（C7）escape hatch 濫用防護** | 若 `ASP_GIT_OK=1` 被**永久 export**，護欄形同關閉。建議 inline/session-scoped 使用；每次 bypass 均留 `GIT-GUARD` 遙測，使「長期 export」在 rule-stats 呈現高 bypass 比而**可見**（誠實留痕優於無聲關閉） |

---

## 🚫 禁止事項（Out of Scope）

- **不重複** `denied-commands.json` 既有 push/publish + `rm -rf` 組——本 hook 只管本地 git 毀資料，避免雙重維護。
- **`git push --force-with-lease`**（目前不在 `denied-commands.json`）→ 屬 push 家族，建議另行追加至 `denied-commands.json` **並同步 rule-registry 增 DENY-13**（`test_rule_registry.sh` T3 斷言 DENY-NN 條數 == denied-commands.json 長度，單改一檔會紅——G2 review D2-1 修正「一行 trivial」低估），不納本 hook。
- **歷史重寫/底層 ref 冷門者**（`filter-branch`、`reflog expire`、`update-ref -d`、`gc --prune=now`）→ 「誠實能力邊界」已列為**不擋**；交獨立審查評估後續是否納入，守 ADR-010 先證核心集。
- **`checkout -B` / `--orphan` / `branch -m`/`-M`（改名／建分支）**：非典型「毀工作區」但可覆蓋 ref；首個 POC **不納**＝**defer**。M1 checkout 謂詞已將 `-b`/`-B`/`--orphan` 之 branch-name／start-point 排除於 positional 計數（故 `checkout -B main origin/main` 不再被 `≥2 positional` **靜默誤擋**——修正 Probe MEDIUM 發現）。`branch -m`/`-M` 同列 review-decide，未來若納須另證不 false-positive。
- **user alias / `git -c alias`**：見「誠實能力邊界」，不宣稱擋得住。
- **不改鐵則文字**：本 hook **operationalize** CLAUDE-IR-1 的本地子集；是否在 `CLAUDE.md` 鐵則明列本地毀資料操作＝憲法變更，屬另案（follow-up ADR），非本 SPEC 範圍。
- **不與 ship-gate 合併**：分離關注點（ship-gate＝commit/測試紀律；git-guardrails＝毀資料安全），各自獨立可測。
- **（A4 follow-up，非本 SPEC）** 兩 hook（ship-gate + git-guardrails）開始共用 stdin 解析/方式-A/遙測 plumbing；**第三個 PreToolUse hook 出現前**，宜抽共用函式至 **`.asp/scripts/lib/`**（位置慣例已由 SPEC-017 的 `worktree.sh` 確立——ship-gate 已 source 該目錄，**勿另建 `.asp/hooks/lib/` 第二個 lib 目錄**；G2 review D7-1 更新）。本 SPEC 先複製樣板、不預先抽象（避免過早抽象），僅記此觸發條件。

---

## 🔗 追溯性（實作後回填）

> G2 review D1-1（HIGH）修入：補齊七必填欄位之第七欄（佔位表，比照 SPEC-014/015/017 慣例，實作後回填）。

- 實作 commit：分支 `asp/spec-016-impl` → PR merge commit（2026-07-29）
- 實作檔：`.asp/hooks/pretooluse-git-guardrails.sh`（新，M0 tokenize + M1 謂詞引擎）、`.claude/settings.json` ＋ `hooks/hooks.json`（wire `PreToolUse[0].hooks[1]`，D3）、`.asp/config/rule-registry.yaml`（`GIT-GUARD` 登記 exempt+observed_by，D2）、`.asp/Makefile.inc`（lint 清單加 hook）
- 測試檔：`tests/test_pretooluse_git_guardrails.sh`（新，80 斷言：P1-12／N1-14／B1-9）、`tests/test_iron_rule_a_coverage.sh`（+2 斷言）、`tests/test_rule_registry.sh`（+3 GIT-GUARD 顯式斷言，D2）、`tests/test_plugin_manifest.sh`（refs≥4 + hooks[1] 綁定，D3）
- Iron Rule A 納入：`session-audit.sh` CRITICAL_FILE 清單已加（commit 進 HEAD 即 hash 自愈）
- ADR-030 Verification Evidence 回填（D6 四欄）：已回填（POC #1 完成）
- git CLI 行為前提一手實測：FC-013（`.asp-fact-check.md`）

---

## 📎 參考資料（References）

- **ADR-030**（Accepted：分層 hybrid 借鏡 mattpocock/skills；其**摘要處置表**將 git-guardrails 列「VENDOR / BUILD-NATIVE」）— 本 SPEC 為其**首個 POC**，結果回填其 Verification Evidence。（「§2」與「BUILD-ASP-NATIVE」一詞出自下列研究文件，非 ADR-030 章節——G2 review D8-1 更正指標落點）
- `docs/research/2026-07-24-mattpocock-skills-deep-borrow.md` §2（git-guardrails-claude-code 逐項分析；BUILD-ASP-NATIVE 一詞出處）。
- **FC-011**（`.asp-fact-check.md`：git-guardrails 一手行為查證——原生機制 exit 2/unanchored substring/靜默 fail-OPEN、(a)-(g) 刻意偏離對照、3 項 unknown）＋ **FC-013**（本 SPEC 依賴的 git CLI 行為一手實測：clean -nfd 不刪／長選項前綴補全屬實／--exec-path 語義／clean -fi interactive 蓋過 force）。
- **SPEC-013**（PreToolUse commit gate）— 本 hook 的**結構樣板**（stdin 解析、方式 A deny、指令位置正則、escape hatch、fail-open、Iron Rule A、遙測）。
- **ADR-021**（plugin marketplace 分發）— `hooks/hooks.json` 為 plugin 安裝者的 hook 承載，故本 SPEC 必須同步 wire（Side Effects D3）。
- ADR-020（強制力架構 / 遺忘威脅模型 / 機械化決策）、FC-002（PreToolUse hook 介面）、ADR-018（規則存留治理 → `exempt` 依據）、ADR-019（hook 納入 Iron Rule A + 誠實能力邊界）、ADR-010（最小採納 → delta 反重疊、誠實替代方案論證）。
- `.asp/hooks/denied-commands.json`（既有 push/publish + rm 毀滅組，本 hook 之正交補集）、`.asp/hooks/session-audit.sh`（動態 `Bash(...)` deny 注入，證「前綴 deny 是既有機制」）。

---

## 🔖 範圍註記（對 ADR-030 (g) 舉例分組的偏離）

ADR-030 決策 (g) 曾以 `spec: borrow-grilling-and-git-guardrails` **舉例**（"e.g."）將 grilling 與 git-guardrails 併於一 SPEC。本 SPEC **刻意只涵蓋 git-guardrails**，理由：(1) git-guardrails 是**可機械驗證的 enforcement**，grilling 是**訪談紀律**（process skill），二者內聚性低；(2) 首個 POC 需**能實測**的交付物以回填 ADR-030 Verification Evidence，混入 grilling 會稀釋焦點。grilling 借用另立**姊妹 SPEC**。此偏離符合 ADR-030 (g) 之 "e.g." 非約束性質。
