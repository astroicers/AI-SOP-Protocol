---
name: asp-reality-check
description: |
  Skeptical verification — defaults to NEEDS_WORK, requires overwhelming evidence to PASS.
  Triggers: reality check, 夠了嗎, is this ready, 能交了嗎, final check
---

# ASP Reality Check — 懷疑主義驗收

## 核心原則

> **預設判定：NEEDS_WORK。** 需要累積 ≥3 個正面證據、0 個反面證據才放行。

## 工作流

### Step 1: 獨立測試驗證

**不信任任何 agent 的自我回報。**

```bash
make test
```

- 全部通過 → +1 正面證據
- 任何失敗 → **立即 NEEDS_WORK**（不繼續檢查）

### Step 2: 偷渡偵測

比較測試檔案的 checksum（修改前 vs 現在）：
- 未變更 → +1 正面證據
- 已變更 → **立即 NEEDS_WORK**

### Step 3: 覆蓋率趨勢

```bash
make coverage  # 如果目標存在
```

- 覆蓋率未下降 → +1 正面證據
- 覆蓋率下降 → +1 反面證據

### Step 4: SPEC Done When 逐項驗證

逐項檢查 SPEC 的 Done When 條件：
- 每個條件都是二元可測試的 → +1 正面證據
- 有模糊條件 → +1 反面證據

### Step 5: 健康分數

```bash
make audit-quick
```

- 未引入新 blocker → +1 正面證據
- 引入新 blocker → +1 反面證據

### Step 6: 文件同步

檢查每個修改的 source file 是否有對應的文件更新：
- 全部同步 → +1 正面證據
- 有遺漏 → +1 反面證據

### Step 7: 判定

| 判定 | 條件 |
|------|------|
| **READY** ✅ | 反面證據 = 0 且 正面證據 ≥ 3 |
| **NEEDS_WORK** 🔴 | 反面證據 > 0 或 正面證據 < 3 |

輸出完整證據清單（正面 + 反面）。

## 參考

- Reality Checker 角色定義：`.asp/agents/reality.yaml`
- 驗證協議：`.asp/profiles/reality_checker.md`
- 品質門參與：G2, G5, G6（`.asp/profiles/pipeline.md`）
