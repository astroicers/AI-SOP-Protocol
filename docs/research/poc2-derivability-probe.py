#!/usr/bin/env python3
# POC-2 spike: 「可推導性」能否以「跨檔近似重複義務偵測」這個便宜機械代理近似？
# 探索性，非生產代碼。回答：mechanical proxy 撈不撈得出「同義務多處重述」的病 + 估誤報率。
import glob, re, sys
from itertools import combinations

CORPUS = (
    ["/home/ubuntu/AI-SOP-Protocol/CLAUDE.md"]
    + glob.glob("/home/ubuntu/.claude/asp/profiles/*.md")
    + glob.glob("/home/ubuntu/AI-SOP-Protocol/.claude/skills/asp/*.md")
)

# 義務句啟發式：含義務標記的行
OBLIG = re.compile(r"(必須|須|禁止|不可|一律|應|跳過|deny|must\b|required|MUST|前必|不得)")
# 雜訊行：純標題/表格分隔/程式碼圍欄
NOISE = re.compile(r"^\s*(#{1,6}\s|\|[-:\s|]+\||```|---|\* \* \*)")

def norm(s: str) -> str:
    s = re.sub(r"`[^`]*`", " ", s)          # 去 inline code
    s = re.sub(r"\[([^\]]*)\]\([^)]*\)", r"\1", s)  # markdown link -> text
    s = re.sub(r"[*_>#|}{\-→—、。（）()\[\]:：，,.。、；;]", "", s)
    s = re.sub(r"ADR-\d+|SPEC-\d+|G[1-6]", "", s)   # 去編號引用（不算語意）
    s = re.sub(r"\s+", "", s).lower()
    return s

def shingles(s: str, n=3):
    return {s[i:i+n] for i in range(max(0, len(s) - n + 1))}

def jac(a, b):
    if not a or not b: return 0.0
    return len(a & b) / len(a | b)

# 收集義務句
items = []  # (file, raw, norm, shingleset)
for path in CORPUS:
    try:
        lines = open(path, encoding="utf-8").read().splitlines()
    except OSError:
        continue
    fname = path.split("/")[-1]
    for ln in lines:
        if not OBLIG.search(ln) or NOISE.match(ln):
            continue
        n = norm(ln)
        if len(n) < 8:   # 太短，無意義
            continue
        items.append((fname, ln.strip(), n, shingles(n)))

print(f"語料: {len(CORPUS)} 檔 | 抽出義務句: {len(items)} 條\n")

# 跨檔近似重複：同義務出現在 >=2 個不同檔
THRESH = 0.55
edges = []
for (fa, ra, na, sa), (fb, rb, nb, sb) in combinations(items, 2):
    if fa == fb:
        continue
    sim = jac(sa, sb)
    if sim >= THRESH:
        edges.append((sim, fa, ra, fb, rb))

edges.sort(reverse=True, key=lambda x: x[0])

# 群聚（簡單 union-find by 連通）
parent = {}
def find(x):
    parent.setdefault(x, x)
    while parent[x] != x:
        parent[x] = parent[parent[x]]; x = parent[x]
    return x
def union(a, b):
    parent[find(a)] = find(b)

idx = {(f, r): i for i, (f, r, *_ ) in enumerate([(it[0], it[1]) for it in items])}
for sim, fa, ra, fb, rb in edges:
    union((fa, ra), (fb, rb))

clusters = {}
for sim, fa, ra, fb, rb in edges:
    root = find((fa, ra))
    clusters.setdefault(root, set()).update([(fa, ra), (fb, rb)])

# 只留「跨 >=2 檔」的群
multi = []
for root, members in clusters.items():
    files = {m[0] for m in members}
    if len(files) >= 2:
        multi.append((len(files), members))
multi.sort(reverse=True, key=lambda x: x[0])

print(f"跨檔近似重複群 (Jaccard>={THRESH}, 跨>=2檔): {len(multi)} 組\n")
print("=== Top 重述義務群（同一義務散在多檔＝可推導/冗餘候選）===")
for nfiles, members in multi[:8]:
    print(f"\n[跨 {nfiles} 檔]")
    seen = set()
    for f, r in sorted(members):
        key = (f, r[:40])
        if key in seen: continue
        seen.add(key)
        print(f"  · {f}: {r[:90]}")

# 誤報抽樣：取相似度剛過門檻的幾條人工眼檢
print("\n=== 邊界相似度樣本（門檻附近，估誤報）===")
border = [e for e in edges if THRESH <= e[0] < THRESH + 0.1][:5]
for sim, fa, ra, fb, rb in border:
    print(f"  sim={sim:.2f}  {fa}: {ra[:55]}  ⇔  {fb}: {rb[:55]}")
