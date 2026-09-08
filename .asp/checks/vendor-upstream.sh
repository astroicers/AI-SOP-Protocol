#!/usr/bin/env bash
# .asp/checks/vendor-upstream.sh — vendored 檔與**上游現況**的同步對帳
# (asp-gate.yaml id: vendor-upstream)
#
# 動機(asp-ng issue #43 AC-3):`vendor-verify.sh` 比的是「本機檔案 vs 本機
# VENDOR.lock」,兩者當然相符——**上游修了、消費端沒同步**這一格它天生看不見。
# 本檢查補的正是那一格:比「lock 記錄 vs 上游現況」。
#
# 判定兩道(兩側共用同一份實作;AC-4):
#   ① 來源真確性:上游在 <ref> 當下的內容 sha256 應等於 lock 記錄值。不等 =
#      這份副本從來不曾是上游 <ref> 的樣子——來源標記造假,或該 ref 已被
#      force-push。**這一道非有第五欄 ref 不可**,只記 sha 驗不出來。
#   ② 同步落後:上游追蹤分支現況的 sha256 與記錄值不同 = 上游已變更而本地未
#      同步。這是 #43 的原始缺口,ref 缺席時仍判得動(只比 sha)。
#
# 取得上游內容的 adapter 可換,判定不換(單一事實源不破):
#   ASP_VENDOR_UPSTREAM_DIR + ASP_VENDOR_UPSTREAM_REPO
#       本機已有上游 checkout。asp-ng 自己對一份消費端 checkout 跑對帳時走這條
#       ——上游即自己,零憑證、零網路。
#   ASP_VENDOR_FETCH=<命令>
#       遠端取檔:`<命令> <repo> <path> <ref>` 把內容印到 stdout,rc 0 = 取得。
#   缺省:`gh api`(裝了 gh 且該 repo 讀得到才可用)。
#
# **取不到 ≠ 通過**:一條都判不成 → exit 200(skip 契約),但輸出會印「本次零
# 比對項」與 lock 上 `# upstream-checked:` 的年齡。對帳沒在跑這件事本身要看得
# 見,否則就退回本票要治的那種靜默(比照 drift-watch 的「前置未備」語意)。
#
# 用法:vendor-upstream.sh [repo 根目錄];缺參數取 ${ASP_GATE_PROJ:-.}
set -u

ROOT="${1:-${ASP_GATE_PROJ:-.}}"
LOCK="$ROOT/.asp/checks/VENDOR.lock"
BRANCH="${ASP_VENDOR_UPSTREAM_BRANCH:-main}"
MAX_AGE="${ASP_VENDOR_STALE_DAYS:-30}"

if [ ! -f "$LOCK" ]; then
  echo "⏭  vendor-upstream: 無 VENDOR.lock($LOCK),略過"
  exit 200
fi

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# ---- adapter:把 <repo>:<path>@<ref> 的內容印到 stdout;rc 0 = 取得,3 = 不可得 ----
fetch_upstream() {
  local repo="$1" path="$2" ref="$3"
  if [ -n "${ASP_VENDOR_UPSTREAM_DIR:-}" ] &&
     [ "$repo" = "${ASP_VENDOR_UPSTREAM_REPO:-}" ]; then
    # 本機 checkout:走 `git show` 而非直接讀工作區檔案——工作區是**當下**的樣子,
    # 不是 <ref> 的樣子;拿工作區冒充 ref 會讓「來源真確性」變成自己對自己。
    if git -C "$ASP_VENDOR_UPSTREAM_DIR" show "$ref:$path" 2>/dev/null; then
      return 0
    fi
    return 3
  fi
  if [ -n "${ASP_VENDOR_FETCH:-}" ]; then
    if "$ASP_VENDOR_FETCH" "$repo" "$path" "$ref" 2>/dev/null; then
      return 0
    fi
    return 3
  fi
  if command -v gh >/dev/null 2>&1; then
    if gh api "repos/$repo/contents/$path?ref=$ref" \
         -H "Accept: application/vnd.github.raw" 2>/dev/null; then
      return 0
    fi
    return 3
  fi
  return 3
}

# 內容一律經檔案取 sha:`$(...)` 會吃掉結尾換行,拿去比 sha256 必然假紅。
sha_of_file() { sha256sum "$1" 2>/dev/null | cut -d' ' -f1; }

FAIL=0
JUDGED=0        # 真的比對成功的次數——0 代表看門沒在看
ENTRIES=0
UNREACHABLE=""

while IFS= read -r line || [ -n "$line" ]; do
  case "$line" in ''|'#'*) continue ;; esac
  read -r f1 f2 f3 f4 f5 _ <<< "$line"
  # 欄數/格式由 vendor-verify 判紅並印明細,本檢查只跳過不可解析的行:同一件事
  # 兩支各報一次,人要修的還是同一行。
  [ -n "$f4" ] || continue
  name="$f1"; repo="$f2"; path="$f3"; want="$f4"; ref="$f5"
  ENTRIES=$((ENTRIES + 1))

  # ---- ① 來源真確性(需 ref)----
  if [ -n "$ref" ]; then
    if fetch_upstream "$repo" "$path" "$ref" > "$TMP/at-ref"; then
      got="$(sha_of_file "$TMP/at-ref")"
      JUDGED=$((JUDGED + 1))
      if [ "$got" != "$want" ]; then
        echo "❌ vendor-upstream: $name 的來源標記對不上上游($repo:$path@$ref)"
        echo "   lock 記錄 $want"
        echo "   上游 @$ref  $got"
        echo "   → 這份副本不曾是上游 $ref 的樣子:來源標記造假,或該 ref 已被 force-push"
        FAIL=1
      fi
    else
      UNREACHABLE="$UNREACHABLE $name@$ref"
    fi
  fi

  # ---- ② 同步落後(#43 的原始缺口)----
  if fetch_upstream "$repo" "$path" "$BRANCH" > "$TMP/at-branch"; then
    head_sha="$(sha_of_file "$TMP/at-branch")"
    JUDGED=$((JUDGED + 1))
    if [ "$head_sha" != "$want" ]; then
      echo "❌ vendor-upstream: $name 上游已變更而本地未同步($repo:$path)"
      echo "   本地停在 ${ref:-<無版本座標>},sha $want"
      echo "   上游 $BRANCH   sha $head_sha"
      echo "   → 重新 vendoring 該檔並更新 VENDOR.lock 的 sha256 與 ref"
      FAIL=1
    fi
  else
    UNREACHABLE="$UNREACHABLE $name@$BRANCH"
  fi
done < "$LOCK"

# ---- 對帳時效:取不到上游時,「多久沒真的對過帳」要看得見 ----
# lock 可帶一行 `# upstream-checked: YYYY-MM-DD`,由實際跑成功的那一趟回填。
last_checked="$(sed -n 's/^# *upstream-checked: *\([0-9-]*\).*/\1/p' "$LOCK" | tail -n1)"
staleness_note() {
  local now_epoch then_epoch age
  if [ -z "$last_checked" ]; then
    echo "   ⚠️  VENDOR.lock 無 \`# upstream-checked:\` 記錄——這份 lock 從未經上游對帳"
    return 0
  fi
  now_epoch="$(date -u -d "${ASP_VENDOR_NOW:-now}" +%s 2>/dev/null || true)"
  then_epoch="$(date -u -d "$last_checked" +%s 2>/dev/null || true)"
  if [ -z "$now_epoch" ] || [ -z "$then_epoch" ]; then
    return 0
  fi
  age=$(((now_epoch - then_epoch) / 86400))
  if [ "$age" -gt "$MAX_AGE" ]; then
    echo "   ⚠️  上次上游對帳為 $last_checked(逾 $age 天,門檻 $MAX_AGE)——看門已停擺"
  else
    echo "   上次上游對帳:$last_checked($age 天前)"
  fi
}

if [ "$JUDGED" -eq 0 ]; then
  # 「取不到」與「通過」必須分開報——混報就是本票開頭那種靜默漂移。
  echo "⏭  vendor-upstream: 本次零比對項($ENTRIES 條記錄皆取不到上游),略過"
  echo "   取得管道:ASP_VENDOR_UPSTREAM_DIR(本機 checkout)/ ASP_VENDOR_FETCH(自備命令)/ gh api"
  staleness_note
  exit 200
fi

if [ "$FAIL" = 0 ]; then
  echo "✅ vendor-upstream: $JUDGED 項與上游($BRANCH)一致"
  echo "   → 回填 VENDOR.lock 檔頭:# upstream-checked: $(date -u -d "${ASP_VENDOR_NOW:-now}" +%Y-%m-%d 2>/dev/null || echo '<今日>')"
fi
if [ -n "$UNREACHABLE" ]; then
  echo "ℹ️  vendor-upstream: 下列取不到上游,未判定:${UNREACHABLE# }"
fi
exit "$FAIL"
