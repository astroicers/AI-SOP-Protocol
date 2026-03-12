# Autopilot Profile — Roadmap 驅動持續執行

<!-- requires: global_core, system_dev, autonomous_dev, task_orchestrator -->
<!-- optional: multi_agent, vibe_coding, design_dev, openapi, frontend_quality, coding_style, rag_context -->
<!-- conflicts: (none) -->

適用：AI 讀取 ROADMAP.yaml 持續執行任務，直到全部完成或 context 預算耗盡。
載入條件：`.ai_profile` 中 `autopilot: enabled`

> **設計原則**：Autopilot 是外層迴圈，不重新發明內層邏輯。
> 每個任務仍走 `task_orchestrator.on_task_received()` 的完整流程（ADR → SPEC → TDD → 實作 → 文件）。
> Autopilot 只負責：讀 Roadmap → 排序 → 逐一餵入 → 管理跨 session 狀態。

---

## 啟用前提

必須同時滿足：
1. `.ai_profile` 設定 `autopilot: enabled`
2. 專案根目錄存在 `ROADMAP.yaml`（可透過 `make autopilot-init` 建立）
3. `autonomous_dev.md` 和 `task_orchestrator.md` 已載入（自動載入）

---

## 前置文件動態探測

Autopilot 根據 ROADMAP.yaml 的 `stack` 和 `requires` 欄位自動判斷哪些前置文件是必要的：

```
FUNCTION detect_required_documents(roadmap):

  required = ["ROADMAP.yaml", roadmap.documents.srs]  // SRS 永遠必要

  IF roadmap.stack.backend != "none" OR roadmap.stack.database != "none":
    required.append(roadmap.documents.sds)  // 後端/資料層需 SDS

  IF roadmap.requires.uiux OR roadmap.stack.frontend != "none":
    required.append(roadmap.documents.uiux_spec)  // 前端需 UI/UX Spec

  IF roadmap.requires.api:
    IF roadmap.documents.sds NOT IN required:
      required.append(roadmap.documents.sds)  // API 需 SDS 的合約段落

  IF roadmap.stack.infra != "none":
    required.append(roadmap.documents.deploy_spec)  // 部署需 Deploy Spec

  missing = [doc FOR doc IN required IF NOT exists(doc)]
  IF missing:
    PRESENT("⚠️ 缺少必要前置文件：")
    FOR doc IN missing:
      reason = infer_reason(doc, roadmap)
      PRESENT("  - {doc}（原因：{reason}）")
    suggest_commands(missing)  // 建議 make srs-new / sds-new / ...
    PAUSE("請建立必要前置文件後再啟動 autopilot")

  RETURN required
```

---

## Profile 自動載入

Autopilot 根據 ROADMAP.yaml 的 `requires` 欄位補充載入 profile：

```
FUNCTION auto_configure_profiles(roadmap):

  IF roadmap.requires.uiux:
    ENSURE_LOADED("design_dev")
    ENSURE_LOADED("frontend_quality")

  IF roadmap.requires.api:
    ENSURE_LOADED("openapi")

  IF roadmap.requires.multi_agent:
    ENSURE_LOADED("multi_agent")

  IF roadmap.requires.rag:
    ENSURE_LOADED("rag_context")

  IF roadmap.requires.coding_style:
    ENSURE_LOADED("coding_style")

  LOG("Auto-loaded profiles: {newly_loaded_profiles}")
```

> `ENSURE_LOADED` 檢查 profile 是否已由 `.ai_profile` 載入，若未載入則動態載入。
> 這讓 ROADMAP.yaml 的 `requires` 欄位能補充 `.ai_profile` 未設定的 profile。

---

## 核心流程

```
FUNCTION autopilot_main():

  // ═══ Phase 0: Resume or Fresh Start ═══
  state = LOAD_FILE(".asp-autopilot-state.json")

  IF state AND state.status == "in_progress":
    PRESENT("🤖 Autopilot 偵測到未完成的執行")
    PRESENT("  已完成: {LEN(state.completed)}/{state.total_tasks}")
    PRESENT("  中斷於: {state.current_task}（{state.exit_reason}）")
    PRESENT("  剩餘: {state.total_tasks - LEN(state.completed)} 個任務")
    PAUSE("確認續接？")
    state.session_count += 1
    // 重讀檔案系統，不信任上個 session 的 context
    VALIDATE_ENVIRONMENT()
  ELSE:
    state = {
      version: 1,
      status: "init",
      started_at: NOW(),
      session_count: 1,
      completed: [],
      failed: [],
      blocked: []
    }

  // ═══ Phase 1: Load ROADMAP & Auto-Configure ═══
  roadmap = PARSE("ROADMAP.yaml")

  // 自動載入 profile
  auto_configure_profiles(roadmap)

  // 記錄技術棧資訊（供後續任務使用）
  LOG("Tech stack: {roadmap.stack}")
  LOG("Conventions: {roadmap.conventions}")
  LOG("Architecture: {roadmap.architecture}")

  // ═══ Phase 2: Validate Prerequisites ═══
  errors = []

  // 驗證前置文件
  detect_required_documents(roadmap)  // 缺少時會 PAUSE

  // 驗證 ADR 狀態
  FOR task IN roadmap.all_tasks():
    IF task.adr:
      adr = FIND_ADR(task.adr)
      IF NOT adr:
        errors.append("Task {task.id}: ADR {task.adr} 不存在")
      ELIF adr.status != "Accepted":
        errors.append("Task {task.id}: {task.adr} 狀態為 {adr.status}（需 Accepted）")

  // 驗證依賴圖無環
  IF has_cycle(roadmap.dependency_graph()):
    errors.append("ROADMAP 任務依賴存在循環")

  IF errors:
    PRESENT("❌ 前置驗證失敗：")
    FOR err IN errors:
      PRESENT("  - {err}")
    PAUSE("請修正後重新啟動 autopilot")
    RETURN

  // ═══ Phase 3: Build Task Queue ═══
  pending = roadmap.all_tasks().filter(t => t.status IN ["pending", "blocked"])
  queue = topological_sort(pending, key=(depends_on, priority))
  state.total_tasks = LEN(roadmap.all_tasks())

  IF queue.empty:
    PRESENT("✅ 所有任務已完成！")
    state.status = "completed"
    SAVE_STATE(state)
    RETURN

  PRESENT("🤖 Autopilot 任務佇列（{LEN(queue)} 個待執行）：")
  FOR task IN queue:
    deps = task.depends_on or "none"
    PRESENT("  {task.id}: [{task.type}] {task.title} (deps: {deps})")

  IF state.status == "init":
    PAUSE("確認後開始自動執行")  // 首次啟動：一次確認

  // ═══ Phase 4: Health Audit ═══
  health = project_health_audit()  // 複用 task_orchestrator
  IF health.has_blockers:
    remediate_gaps(health)

  // ═══ Phase 5: Execute Loop ═══
  state.status = "in_progress"
  SAVE_STATE(state)

  FOR task IN queue:

    // ─── Context 預算檢查 ───
    IF context_usage() > 75%:
      state.exit_reason = "context_budget"
      state.exit_detail = "Context 使用率 {context_usage()}%"
      SAVE_STATE(state)
      UPDATE_ROADMAP_STATUSES(roadmap)
      PRESENT("⏸️ Context 預算達上限，已儲存 checkpoint")
      PRESENT("  開新 session 後 autopilot 會自動提示續接")
      RETURN

    // ─── 依賴檢查 ───
    unmet = [d FOR d IN task.depends_on IF d NOT IN state.completed]
    IF unmet:
      task.status = "blocked"
      state.blocked.append(task.id)
      UPDATE_ROADMAP(task)
      LOG("Task {task.id} blocked by: {unmet}")
      CONTINUE

    // ─── 自動建立 SPEC（如果沒有）───
    IF task.spec == null:
      spec = EXECUTE("make spec-new TITLE=\"{task.title}\"")
      // 若有 srs_ref，從 SRS 交叉引用需求填充 SPEC
      IF task.srs_ref AND exists(roadmap.documents.srs):
        srs_content = READ(roadmap.documents.srs)
        fr = extract_fr(srs_content, task.srs_ref)
        FILL spec.goal FROM fr.description
        FILL spec.done_when FROM fr.acceptance_criteria
      ELSE:
        FILL spec FROM task.description
      task.spec = spec.id
      UPDATE_ROADMAP(task)

    // ─── 執行任務 ───
    state.current_task = task.id
    task.status = "in_progress"
    state.last_updated = NOW()
    UPDATE_ROADMAP(task)
    SAVE_STATE(state)

    LOG("═══ Executing: {task.id} [{task.type}] {task.title} ═══")

    // 建構 task_orchestrator 的輸入
    request = {
      title:       task.title,
      type:        task.type,
      spec:        task.spec,
      description: task.description,
      stack:       roadmap.stack,
      conventions: roadmap.conventions,
      architecture: roadmap.architecture
    }

    // 透過 task_orchestrator 入口執行
    result = on_task_received(request)

    IF result.success:
      task.status = "completed"
      state.completed.append(task.id)
      UPDATE_ROADMAP(task)
      SAVE_STATE(state)
      LOG("✅ Task {task.id} completed ({LEN(state.completed)}/{state.total_tasks})")

      // 更新 milestone 狀態
      milestone = get_milestone(task, roadmap)
      IF all_tasks_completed(milestone):
        milestone.status = "completed"
        UPDATE_ROADMAP(milestone)

    ELSE IF result.needs_human:
      task.status = "blocked"
      state.blocked.append(task.id)
      state.exit_reason = "human_intervention"
      state.exit_detail = result.pause_reason
      SAVE_STATE(state)
      UPDATE_ROADMAP(task)
      PRESENT("⏸️ Task {task.id} 需要人類介入: {result.pause_reason}")
      PRESENT("  處理完成後開新 session，autopilot 會自動續接")
      RETURN

    ELSE IF result.failed:
      task.status = "failed"
      state.failed.append(task.id)
      UPDATE_ROADMAP(task)
      SAVE_STATE(state)
      LOG("❌ Task {task.id} failed, continuing to next independent task")
      // 不中斷，繼續下一個不依賴此 task 的任務

    // ─── 階段性 Context 品質自檢 ───
    IF context_usage() > 60%:
      SAVE_STATE(state)  // 預防性 checkpoint

  // ═══ Phase 6: Completion ═══
  state.status = "completed"
  state.exit_reason = "all_done"
  state.last_updated = NOW()
  SAVE_STATE(state)

  EXECUTE("make audit-health")

  PRESENT("═══════════════════════════════════════")
  PRESENT("  🤖 Autopilot 執行完成")
  PRESENT("═══════════════════════════════════════")
  PRESENT("  總任務: {state.total_tasks}")
  PRESENT("  完成:   {LEN(state.completed)}")
  PRESENT("  失敗:   {LEN(state.failed)}")
  PRESENT("  阻塞:   {LEN(state.blocked)}")
  PRESENT("  Sessions: {state.session_count}")
  PRESENT("═══════════════════════════════════════")
```

---

## Session Bridge 狀態檔

檔案：`.asp-autopilot-state.json`（加入 `.gitignore`）

```json
{
  "version": 1,
  "status": "in_progress",
  "started_at": "2026-03-12T10:00:00Z",
  "last_updated": "2026-03-12T14:30:00Z",
  "session_count": 3,
  "total_tasks": 8,
  "roadmap_file": "ROADMAP.yaml",
  "current_task": "T003",
  "completed": ["T001", "T002"],
  "failed": [],
  "blocked": [],
  "exit_reason": "context_budget",
  "exit_detail": "Context at 78% after T002 completion"
}
```

**與現有 session-checkpoint 的差異**：
- 固定 schema，機器可解析（非 narrative markdown）
- 包含確切的 task ID，可精準續接
- ROADMAP.yaml 的 status 變更會 commit（團隊可見），state 檔不 commit（session 暫存）

---

## ROADMAP 更新規則

```
FUNCTION UPDATE_ROADMAP(item):
  // 原地更新 ROADMAP.yaml 中的 task/milestone status
  // 只更新 status 欄位，不修改 task 的定義（title/type/description/depends_on）
  READ "ROADMAP.yaml"
  UPDATE item.status
  WRITE "ROADMAP.yaml"

FUNCTION UPDATE_ROADMAP_STATUSES(roadmap):
  // 批次更新所有 task 的 status
  // 用於 checkpoint 存檔前確保 ROADMAP 與 state 同步
  FOR task IN roadmap.all_tasks():
    IF task.id IN state.completed: task.status = "completed"
    IF task.id IN state.failed: task.status = "failed"
    IF task.id IN state.blocked: task.status = "blocked"
  WRITE "ROADMAP.yaml"
```

---

## 安全邊界

Autopilot 繼承 `autonomous_dev.md` 的所有安全邊界，並增加以下限制：

### 可自主執行（不暫停）

| 類別 | 範圍 | 條件 |
|------|------|------|
| **讀取 ROADMAP** | 解析任務佇列 | 永遠 |
| **自動建立 SPEC** | `make spec-new` + 填寫 | task.spec 為 null 時 |
| **更新 ROADMAP status** | 修改 task/milestone 狀態 | 任務完成/失敗/阻塞時 |
| **更新 state 檔** | 寫入 `.asp-autopilot-state.json` | 每次任務開始/完成時 |
| **動態載入 profile** | `ENSURE_LOADED()` | ROADMAP requires 欄位 |
| **跳過 blocked task** | 繼續下一個獨立任務 | 依賴未滿足時 |

### 必須暫停（等待人類確認）

| 類別 | 觸發條件 |
|------|----------|
| **首次啟動** | 顯示任務佇列後，等待一次確認 |
| **續接確認** | 新 session 偵測到 state 檔時 |
| **前置文件缺失** | 動態探測發現必要文件不存在 |
| **ADR 未 Accepted** | 任務引用的 ADR 狀態非 Accepted |
| **autonomous_dev 暫停** | 繼承所有：git push、刪除檔案、新增依賴、auto_fix 防護觸發等 |

### 禁止（即使 autopilot 模式也不可）

| 類別 | 說明 |
|------|------|
| **修改 ROADMAP task 定義** | 不可修改 title/type/description/depends_on/priority |
| **新增非 ROADMAP 任務** | 不可自行新增 ROADMAP 中不存在的任務 |
| **跳過 SPEC 建立** | 每個 task 必須有對應 SPEC |
| **ADR 狀態變更** | 繼承 autonomous_dev 鐵則 |
| **跳過 TDD** | 繼承 autonomous_dev 鐵則 |

---

## Context 管理

Autopilot session 通常很長，context 管理尤其重要：

| 觸發條件 | 動作 |
|----------|------|
| 完成一個 task | 輸出 task 完成摘要（修改了哪些檔案、測試結果） |
| context > 60% | 預防性存檔 state |
| context > 75% | 存檔 checkpoint + ROADMAP 更新 + 優雅退出 |
| 偵測到 context decay 信號 | 停止開發，存檔，建議新 session |

---

## 與其他 Profile 的關係

```
autopilot.md
  ├── 依賴 autonomous_dev.md（安全邊界 + auto_fix_loop）
  ├── 依賴 task_orchestrator.md（on_task_received() 入口 + 健康審計）
  ├── 依賴 system_dev.md（ADR/SPEC/TDD 流程）
  ├── 依賴 global_core.md（鐵則 + 連帶修復）
  ├── 可選 multi_agent.md（並行任務執行，由 ROADMAP.requires 觸發）
  ├── 可選 vibe_coding.md（context 衰退偵測）
  ├── 可選 design_dev.md（Design Gate，由 ROADMAP.requires.uiux 觸發）
  ├── 可選 openapi.md（OpenAPI Gate，由 ROADMAP.requires.api 觸發）
  ├── 可選 frontend_quality.md（前端品質，由 ROADMAP.requires.uiux 觸發）
  ├── 可選 coding_style.md（程式碼風格，由 ROADMAP.requires.coding_style 觸發）
  └── 可選 rag_context.md（知識庫查詢，由 ROADMAP.requires.rag 觸發）
```

Autopilot 是最外層的調度 profile，包裹所有其他 profile 的功能。
不啟用 autopilot 時，所有既有行為完全不變。
