#!/usr/bin/env bash
# .asp/checks/git-guard.sh — 本地毀資料護欄檢查本體(asp-gate.yaml id: git-guard)
#
# 血緣:v4 pretooluse-git-guardrails.sh(SPEC-016 / ADR-030)M0/M1 謂詞逐行遷出
# (asp-ng issue #32 G1 裁定:檢查本體入單一事實源,hook 留薄觸發器)。
#
# 用法:git-guard.sh [受檢指令]
#   受檢指令取位置參數,次取 env ASP_GATE_COMMAND;兩者皆缺 → exit 200(skip 契約:
#   gate 在 commit 情境以 ASP_GATE_COMMAND 傳入;無指令可驗即自跳過)。
#
# 判定(正向表列,命中下列十類毀滅性 git 即 exit 1 並印命中謂詞):
#   〔本地〕reset --hard|clean(force 且非 dry-run/interactive)|branch 強制刪除|
#   checkout 丟工作區(-f/--/<ref> <pathspec>/.)|restore 丟工作區|
#   switch 強制(-C/-f/--discard-changes)|stash clear/drop|
#   worktree remove --force|rm --force
#   〔遠端〕push 強制(--force/-f/refspec 前綴 +)/刪除遠端分支(--delete/-d/:branch/
#           --mirror/--prune)/直推預設分支(第十類,2026-09-05 新增;+/--mirror/--prune
#           三形態 2026-09-08 補;見 _pred_push)
#   通過 → exit 0。超長(>8192)→ exit 200(GG-SEC-01:純 bash tokenizer O(n²),
#   上限防 DoS;v4 為靜默放行,本版同為 allow 決策、加印跳過訊息)。
#   判定純由指令語法/argv 決定(無狀態);能力邊界見 SPEC-016 與 FC-013
#   (前綴補全/命令替換/checkout 檔路徑屬已知漏擋釘樁)。
#
# GG-SEC-02(2026-09-05):**包裝前綴**自本版起剝離,不再是已知漏擋。
#   原判定要求分段的第一個 token 是 `git`,故任何包裝都能整條穿過。當初評為可接受,
#   前提是「沒有東西會例行地包裝指令」——而 rtk 的 PreToolUse hook 正是把每一條
#   Bash 改寫成 `rtk <cmd>`,前提已不成立。實測(修補前):
#     `git reset --hard HEAD~3`       → 擋
#     `rtk git reset --hard HEAD~3`   → 放行   ← 洞
#     `rtk proxy git reset --hard …`  → 放行   ← 洞(proxy 的定義就是不過濾)
#   同日 `Bash(rtk proxy *)` 由 permissions.ask 移除(使用者裁定),那是這條路徑
#   先前唯一的補償控制——故本剝離不是錦上添花,是接手那個被撤掉的位置。
set -u

# 呼叫端未加引號時只會傳進第一個 token(`git`)而靜默通過——視為誤用直接紅,
# 不讓「引號寫錯」變成無聲關閉護欄(補審 HIGH-6)。
if [ "$#" -gt 1 ]; then
  echo "❌ git-guard: 收到 $# 個參數;受檢指令須為單一字串(呼叫端請加引號)"
  exit 1
fi

CMD="${1:-${ASP_GATE_COMMAND:-}}"
if [ -z "$CMD" ]; then
  echo "⏭  git-guard: 無受檢指令(ASP_GATE_COMMAND 未設),略過"
  exit 200
fi
# GG-SEC-01:純 bash tokenizer 為 O(n²),上限防超長指令 DoS。但**截斷後照常分析**
# 而非略過——略過在 gate 語境等於綠燈,尾隨長註解即可繞過護欄(補審 BLOCKER-1);
# 截斷的計算成本與原上限相同,毀滅性謂詞位於指令前段,判定不受影響。
if [ "${#CMD}" -gt 8192 ]; then
  echo "⚠️  git-guard: 指令超長(>8192),截斷至上限後分析(GG-SEC-01 DoS 防護)"
  CMD="${CMD:0:8192}"
fi

# ══════════════════════════════════════════════════════════════
# M0:分段與 tokenize(引號感知 best-effort)——v4 逐行遷移
# ══════════════════════════════════════════════════════════════

# _split_segments <command> — 引號外的 ; & | 換行 為分段點;保留引號原字元供 tokenize。
_split_segments() {
  local s="$1"; local i=0 n=${#s} c q='' seg=''
  while [ "$i" -lt "$n" ]; do
    c=${s:$i:1}
    if [ -n "$q" ]; then
      seg+=$c; [ "$c" = "$q" ] && q=''
    elif [ "$c" = "'" ] || [ "$c" = '"' ]; then
      q=$c; seg+=$c
    elif [ "$c" = ';' ] || [ "$c" = '&' ] || [ "$c" = '|' ] || [ "$c" = $'\n' ]; then
      printf '%s\n' "$seg"; seg=''
    else
      seg+=$c
    fi
    i=$((i+1))
  done
  printf '%s\n' "$seg"
}

# _load_argv <segment> — 引號感知空白切 token 進全域 ARGV[](去引號)。
_load_argv() {
  local s="$1"; local i=0 n=${#s} c q='' tok='' have=0
  ARGV=()
  while [ "$i" -lt "$n" ]; do
    c=${s:$i:1}
    if [ -n "$q" ]; then
      if [ "$c" = "$q" ]; then q=''; else tok+=$c; fi
    elif [ "$c" = "'" ] || [ "$c" = '"' ]; then
      q=$c; have=1
    elif [[ "$c" =~ [[:space:]] ]]; then
      [ "$have" = 1 ] && { printf -v _ '%s' "$tok"; ARGV+=("$tok"); tok=''; have=0; }
    else
      tok+=$c; have=1
    fi
    i=$((i+1))
  done
  [ "$have" = 1 ] && ARGV+=("$tok")
}

# ══════════════════════════════════════════════════════════════
# M1:謂詞 helper(操作全域 SUBARGS[])——v4 逐行遷移
# ══════════════════════════════════════════════════════════════

_arg_has() {                         # 精確 token 比對(case-sensitive)
  local a
  for a in ${SUBARGS[@]+"${SUBARGS[@]}"}; do [ "$a" = "$1" ] && return 0; done
  return 1
}
_bundle_has() {                      # 短旗標捆綁(-xyz,非 --)含字母 $1
  local a rest
  for a in ${SUBARGS[@]+"${SUBARGS[@]}"}; do
    case "$a" in
      --*) : ;;
      -?*) rest="${a#-}"; case "$rest" in *"$1"*) return 0 ;; esac ;;
    esac
  done
  return 1
}
# _bundle_has_flag <char> <argchars> — 捆綁含「獨立旗標」char;掃到「需參數短旗標」
# (argchars 之一)即停:其後字元是該旗標的參數、非旗標(如 checkout -Bf 的 f=-B 的分支名,
# switch -cf 的 f=-c 的分支名)。用於 -f/-C 這類與「需參數建分支旗標」可能同 token 者。
_bundle_has_flag() {
  local char="$1" argchars="$2" a rest i c
  for a in ${SUBARGS[@]+"${SUBARGS[@]}"}; do
    case "$a" in --*) continue ;; -?*) rest="${a#-}" ;; *) continue ;; esac
    i=0
    while [ "$i" -lt "${#rest}" ]; do
      c="${rest:$i:1}"
      [ "$c" = "$char" ] && return 0
      case "$argchars" in *"$c"*) break ;; esac
      i=$((i+1))
    done
  done
  return 1
}
_positionals() {                     # 子命令後非 - 開頭 token → 全域 POS[]
  local a
  POS=()
  for a in ${SUBARGS[@]+"${SUBARGS[@]}"}; do
    case "$a" in -*) : ;; *) POS+=("$a") ;; esac
  done
}

_pred_reset()  { _arg_has "--hard" && { MATCHED="reset --hard"; return 0; }; return 1; }
_pred_rm()     { { _arg_has "--force" || _bundle_has f; } && { MATCHED="rm --force"; return 0; }; return 1; }

# _pred_push — 第十類(遠端)。**只擋三種不可逆形態,不擋一般推送**:護欄要能長住,
# 擋掉每天要做幾十次的事只會逼人整條關掉。
#
#   1. 強制推送:覆寫遠端歷史,別人已取走的 commit 就此對不上。
#      **`--force-with-lease` 刻意不擋**——它在遠端被人動過時會失敗,正是
#      「別蓋掉別人」的安全變體;擋它只會逼人改用真正的 `--force`。
#      機制上不必特判:`_arg_has` 是精確 token 比對(`--force` ≠ `--force-with-lease`),
#      而 `_bundle_has` 跳過 `--` 開頭者。
#      **refspec 的 `+` 前綴同屬本類**(2026-09-08 補):`git push origin +main` 與
#      `git push --force origin main` 等效,且**無 lease**。它先前整條穿過——
#      `+main` 不以 `-` 開頭,`_arg_has`/`_bundle_has` 都看不到;而 dst 取
#      `${a##*:}` 後為 `+main`,與字面 `main` 不等。不對稱的反證:帶冒號的
#      `+HEAD:main` 反而擋得住(dst 解析後＝`main`)。
#   2. 刪除遠端分支(`--delete` / `-d` / 舊寫法 `origin :branch` / `--mirror` / `--prune`):
#      租約還活著時刪掉 worker 的 ref,下一 tick 的 QA 前置就抓不到分支而誤貼
#      needs-human(#400/#429 兩次實錄)。
#      `--mirror` 把遠端多餘的 ref 一併刪除、`--prune` 刪掉遠端已無本地對應者——
#      兩者都是**成批**刪 ref,損害面比單支 `--delete` 更大卻先前不受檢(2026-09-08 補)。
#   3. 直推預設分支(`main`/`master`):ADR-000 §10「merge main 由人親手」。
#      2026-08-26 實查 GitHub **free** 方案無分支保護/rulesets(私有 repo 拿不到),
#      故這是該規則**唯一的**機械承接——在此之前它只有散文層。
#
# 已知上限(誠實記):本檢查無狀態、不讀 repo,故推不出「現在在哪個分支」。
# 裸 `git push` / `git push origin`(依 push.default 推當前分支)若人正站在 main 上,
# **擋不到**。要擋那個形態得執行 git 去問當前分支,那會讓本檢查從純文字分析變成
# 有狀態、且多出「git 讀失敗時怎麼判」的新失效面——不划算。第 3 條買的是
# 「明確寫出 main 當目的地」這個高訊號形態。
_pred_push() {
  local a dst
  # `--dry-run`/`-n` 什麼都不做,擋它純屬過度攔截(對齊 `_pred_clean` 的既有處理)。
  # 它也是人用來「先看看會推什麼」的手段——擋掉等於逼人直接來真的。
  { _arg_has "--dry-run" || _bundle_has n; } && return 1
  { _arg_has "--force" || _bundle_has f; } && { MATCHED="push --force(覆寫遠端歷史;安全變體請用 --force-with-lease)"; return 0; }
  { _arg_has "--delete" || _bundle_has d; } && { MATCHED="push --delete(刪除遠端分支)"; return 0; }
  _arg_has "--mirror" && { MATCHED="push --mirror(遠端多餘 ref 一併刪除)"; return 0; }
  _arg_has "--prune"  && { MATCHED="push --prune(刪除遠端已無本地對應的分支)"; return 0; }
  _positionals
  for a in ${POS[@]+"${POS[@]}"}; do
    case "$a" in
      # refspec 的 `+` 前綴 = 強制更新該 ref(git 文法),與 `--force` 等效且無 lease。
      # 放在 `:*` 之前:`+:branch` 這種同時帶兩者的寫法,force 是更強的訊號。
      +*) MATCHED="push +<refspec>(前綴 + 即強制更新該 ref,等效 --force;安全變體請用 --force-with-lease)"; return 0 ;;
      :*) MATCHED="push <remote> :<branch>(刪除遠端分支的舊寫法)"; return 0 ;;
    esac
    # refspec 為 `src:dst`,危險的是**目的地**;`main:feature` 不危險,`HEAD:main` 危險。
    case "$a" in *:*) dst="${a##*:}" ;; *) dst="$a" ;; esac
    case "$dst" in
      main|master|refs/heads/main|refs/heads/master)
        MATCHED="push 直推預設分支($a)——ADR-000 §10:main 由人親手"; return 0 ;;
    esac
  done
  return 1
}

_pred_clean() {
  local force=0 dry=0 inter=0
  { _arg_has "--force" || _bundle_has f; } && force=1
  { _arg_has "--dry-run" || _bundle_has n; } && dry=1
  { _arg_has "--interactive" || _bundle_has i; } && inter=1
  [ "$force" = 1 ] && [ "$dry" = 0 ] && [ "$inter" = 0 ] && { MATCHED="clean --force"; return 0; }
  return 1
}

_pred_branch() {
  { _arg_has "-D" || _bundle_has D; } && { MATCHED="branch -D"; return 0; }
  local del=0 frc=0
  { _arg_has "-d" || _arg_has "--delete" || _bundle_has d; } && del=1
  { _arg_has "-f" || _arg_has "--force" || _bundle_has f; } && frc=1
  [ "$del" = 1 ] && [ "$frc" = 1 ] && { MATCHED="branch --delete --force"; return 0; }
  return 1
}

_pred_checkout() {
  # -f/--force/捆綁含 f(獨立旗標;-b/-B 為需參數建分支旗標,其後字母是分支名非旗標)
  { _arg_has "-f" || _arg_has "--force" || _bundle_has_flag f "bB"; } && { MATCHED="checkout --force"; return 0; }
  { _arg_has "-p" || _arg_has "--patch"; } && return 1                       # 先決:互動
  { _arg_has "-b" || _arg_has "-B" || _arg_has "--orphan"; } && return 1     # 先決:建分支
  _arg_has "--" && { MATCHED="checkout -- (pathspec 丟棄)"; return 0; }
  _positionals
  [ "${#POS[@]}" -ge 2 ] && { MATCHED="checkout <ref> <pathspec>"; return 0; }
  [ "${#POS[@]}" = 1 ] && [ "${POS[0]}" = "." ] && { MATCHED="checkout ."; return 0; }
  return 1
}

_pred_restore() {
  { _arg_has "-p" || _arg_has "--patch"; } && return 1                       # 先決:互動
  local hasW=0 hasS=0
  { _arg_has "-W" || _arg_has "--worktree" || _bundle_has W; } && hasW=1
  { _arg_has "-S" || _arg_has "--staged" || _bundle_has S; } && hasS=1
  [ "$hasW" = 1 ] && { MATCHED="restore --worktree"; return 0; }
  [ "$hasS" = 0 ] && [ "$hasW" = 0 ] && { MATCHED="restore (預設工作區)"; return 0; }
  return 1
}

_pred_switch() {
  # -C/捆綁含 C(force-create;-c 為需參數安全建分支,其後字母是分支名)
  { _arg_has "-C" || _bundle_has_flag C "c"; } && { MATCHED="switch --force-create"; return 0; }
  # -f/--force/--discard-changes/--force-create/捆綁含 f(-c/-C 需參數,其後非旗標)
  { _arg_has "--force-create" || _arg_has "--discard-changes" \
    || _arg_has "-f" || _arg_has "--force" || _bundle_has_flag f "cC"; } && { MATCHED="switch (force/discard)"; return 0; }
  return 1
}

_pred_stash() {                      # 第一個 positional 為 clear/drop(-- 後皆 pathspec)
  local a
  for a in ${SUBARGS[@]+"${SUBARGS[@]}"}; do
    case "$a" in
      --) return 1 ;;                # 選項終止符:其後為 pathspec,非子命令(OB-01)
      -*) continue ;;
      clear|drop) MATCHED="stash $a"; return 0 ;;
      *) return 1 ;;
    esac
  done
  return 1
}

_pred_worktree() {                   # 第一個非選項參數 = remove 且有 force
  local a first=""
  for a in ${SUBARGS[@]+"${SUBARGS[@]}"}; do
    case "$a" in -*) continue ;; *) first="$a"; break ;; esac
  done
  [ "$first" = "remove" ] || return 1
  { _arg_has "-f" || _arg_has "--force" || _bundle_has f; } && { MATCHED="worktree remove --force"; return 0; }
  return 1
}

# _strip_redirects — 從 ARGV[] 移除 shell redirect 序列(redirect 是 shell 語法、非
# 命令參數,不得算 positional)。OB-02:修 `git checkout main 2>/dev/null` 的
# `2>/dev/null` 被 _positionals 誤當第二個 positional → checkout 誤判 ≥2 → over-block。
_strip_redirects() {
  local out=() i=0 n=${#ARGV[@]} t
  local pure='^([0-9]*(>>?|<)|&>>?)$' selfc='^([0-9]*>|[0-9]*<|&>)'
  while [ "$i" -lt "$n" ]; do
    t="${ARGV[$i]}"
    if [[ "$t" =~ $pure ]]; then i=$((i+2)); continue; fi   # 純 operator(>, 2>, >>, <, &>)→ 連目標跳
    if [[ "$t" =~ $selfc ]]; then i=$((i+1)); continue; fi  # 自含(2>&1, 2>/dev/null, >file)→ 只跳自己
    out+=("$t"); i=$((i+1))
  done
  if [ "${#out[@]}" -gt 0 ]; then ARGV=("${out[@]}"); else ARGV=(); fi
}

# _analyze_segment <segment> — 命中本地毀滅性 git → return 0(設 MATCHED)
_analyze_segment() {
  _load_argv "$1"
  _strip_redirects
  local n=${#ARGV[@]} i=0 t sub
  [ "$n" -gt 0 ] || return 1
  # M0.3:跳 VAR=val 前綴,並剝離指令包裝器(GG-SEC-02;理由見檔頭)。
  # 兩者同一個迴圈:`sudo FOO=1 git …`、`rtk proxy env X=1 git …` 這類交錯形態
  # 若拆成兩段各跑一次,只會剝掉其中一種排列。
  # **已知上限(誠實記)**:只認**無參數**的簡單前綴形。`sudo -u x git …`、
  # `xargs git …`、`sh -c "git …"`、`eval …` 皆仍可繞——本剝離買的是
  # 「防低努力/半無意」,不是防蓄意規避(同 test-mutex 的裁定記帳)。
  # 剝不出 `git` 的照樣 return 1,故不擴大攔截面。
  while [ "$i" -lt "$n" ]; do
    case "${ARGV[$i]}" in
      [A-Za-z_]*=*) i=$((i+1)) ;;
      rtk)
        i=$((i+1))
        # rtk 的兩個「執行任意指令」子命令:proxy(明示不過濾)與 run
        case "${ARGV[$i]:-}" in proxy|run) i=$((i+1)) ;; esac
        ;;
      sudo|doas|env|command|nice|nohup|stdbuf|time) i=$((i+1)) ;;
      *) break ;;
    esac
  done
  [ "$i" -lt "$n" ] && [ "${ARGV[$i]}" = "git" ] || return 1
  i=$((i+1))
  while [ "$i" -lt "$n" ]; do                # M0.4:跳全域選項
    t="${ARGV[$i]}"
    case "$t" in
      --exec-path) i=$((i+1)) ;;                                             # 不吃下一 token
      -C|-c|--git-dir|--work-tree|--namespace|--super-prefix) i=$((i+2)) ;;  # 吃參數
      --*=*) i=$((i+1)) ;;
      -*) i=$((i+1)) ;;
      *) break ;;
    esac
  done
  [ "$i" -lt "$n" ] || return 1
  sub="${ARGV[$i]}"
  SUBARGS=("${ARGV[@]:$((i+1))}")
  case "$sub" in
    reset)    _pred_reset ;;
    clean)    _pred_clean ;;
    branch)   _pred_branch ;;
    checkout) _pred_checkout ;;
    restore)  _pred_restore ;;
    switch)   _pred_switch ;;
    stash)    _pred_stash ;;
    worktree) _pred_worktree ;;
    rm)       _pred_rm ;;
    push)     _pred_push ;;
    *) return 1 ;;
  esac
}

# ══════════════════════════════════════════════════════════════
# 主流程:命中 → exit 1 + 描述(ASCII 冒號錨點供薄 hook 抽取);通過 → exit 0
# ══════════════════════════════════════════════════════════════
MATCHED=""
while IFS= read -r _seg; do
  [ -n "$_seg" ] || continue
  if _analyze_segment "$_seg"; then
    printf '❌ git-guard: 毀滅性 git 操作: %s\n' "$MATCHED"
    exit 1
  fi
done < <(_split_segments "$CMD")
exit 0
