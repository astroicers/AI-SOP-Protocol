# SPEC-018：asp-autopilot Part1/Part2 雙重編碼去重（消 drift，ADR-031 FIRM）

| 欄位 | 內容 |
|------|------|
| **規格 ID** | SPEC-018 |
| **狀態** | Draft（ADR-031 FIRM 之 POC；結果回填 ADR-031 Verification Evidence） |
| **關聯 ADR** | ADR-031（FIRM 父）、ADR-006（Part 2 為 canonical）、ADR-024、ADR-030 |
| **HITL 等級** | standard |

## 🎯 目標（Goal）
消 asp-autopilot「Part 1 零確認策略」與「Part 2 自主處理策略」對同組行為的雙重編碼（已 drift）：Part 2 為單一 canonical，Part 1 收斂為速覽 + 指向 Part 2。**前提：Part 1 獨有規格先併入 Part 2、canonical 零丟失**。**不做**：asp-plan 反繞過表（ADR-010）；降 R6（去重後仍 >300，屬 ADR-024）。

## 📥 Inputs
asp-autopilot.md Part 1（L202-）+ Part 2（L762-）。

## 📤 Expected Output
1. **Part 2 併入 Part 1 獨有列**（零丟失）：Context 60%→存檔續、Context 75%→存檔退、測試失敗≤3→修復重試（明定上限 3）。
2. **Part 1 收斂**為 3-5 行速覽 + 指向 Part 2；鐵則操作速覽須完整（含 push main/--force/pr merge/rebase/docker）。
3. **Phase 0.5 死碼移除**（agent_memory profile v4.1.1 archive、IF 恆 false、無 downstream 引用）。

## 🔗 Part1∪Part2 合併映射（canonical 零丟失核對）
| Part 1 項 | Part 2 | 判定 |
|---|---|---|
| 缺 SPEC→spec-new | 自動建 SPEC 列 | aligned |
| 測試≤3→修復 | auto_fix（無≤3） | **part1-only→併入** |
| Draft ADR→blocked | ADR 未 Accepted→blocked | aligned |
| FIRM ADR→🟡 | ADR FIRM→🟡 | aligned |
| Context 60%/75% | — | **part1-only→併入** |
| 暫停:push main/force/pr merge | Part 2 對應（--force 本 SPEC 補） | aligned |
| **暫停:失敗>3 次** | **auto_fix 失敗→跳過** | **🔴 CONFLICT-1** |
| **暫停:docker push/deploy** | **跳過記 tech-debt** | **🔴 CONFLICT-2**（獨立審查揪出，原誤判 aligned） |

### 🔴 衝突解決（人類 Accept 時確認）
**兩處衝突**，暫定皆依 ADR-006 以 Part 2 canonical 為準，Accept 時須確認：
- **CONFLICT-1（失敗>3）**：Part 1「暫停問人類」vs Part 2「跳過繼續」→ 依 canonical 跳過不暫停；可見性由 briefing+failed 標記承載。
- **CONFLICT-2（docker deploy）**：Part 1「暫停」vs Part 2「跳過記 tech-debt」→ 依 canonical 跳過；⚠️ 意味 deploy 被靜默跳過、task 可能標完成但未部署。**此項風險較高**（部署動作不該靜默略過？），人類 Accept 時特別確認；若認為「deploy 應暫停」則此列改以 Part 1 為 canonical。

> **Auto-PR 去重（ADR-031 決議提及）不在本 SPEC 範圍**：Part 1 的 Auto-PR 4 步是**操作序**（非情境重複表），與 Part 2 執行迴圈 pseudocode 內容一致、**無 drift**（非本 ADR 要消的問題來源）。保留於收斂後速覽供快速執行參考；若要進一步縮為單行指向，另立 follow-up。

## ⚠️ Edge Cases
- 合併須確保 Part 1 每個獨有規格在 Part 2 有對應列（獨立審查核對本映射）。
- Part 1 收斂後仍讓讀者掌握大致行為 + 知去哪看完整（非純刪）。

## ✅ Done When
- [ ] Part 2 含 Context 60%/75%/測試≤3/--force（零丟失）
- [ ] Part 1 收斂 + 指向 Part 2 + 鐵則速覽完整
- [ ] Phase 0.5 死碼除，agent_memory 引用歸零
- [ ] 衝突顯式標記、以 Part 2 canonical、PR 提請人類確認
- [ ] lint R1/R2 過、advisory 不增；make test 全綠
- [ ] 獨立 read-only 審查：canonical 零丟失 + 行為語意（除衝突）不變
- [ ] ADR-031 Verification Evidence 回填

## 🔗 追溯性（實作後回填）
- commit：TBD｜檔：asp-autopilot.md｜審查：TBD
