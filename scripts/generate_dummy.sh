#!/usr/bin/env bash
# Generate dummy processed data (one TSV) for an event defined in config/<event>/.
#
# Usage:
#   scripts/generate_dummy.sh --config config/dummy -o data/dummy/small.tsv  -n 40 --seed 0
#   scripts/generate_dummy.sh --config config/dummy -o data/dummy/medium.tsv -n 60 --seed 1
#
# It prints the number of service seats (service slots x people needed per slot) and of members
# who can work a service slot. With more members than seats, someone gets no service slot
# (min_load in the model cannot be met) and the solver slows down.
#
set -euo pipefail

config="" out="" members=40 seed=0
while [ $# -gt 0 ]; do
  case "$1" in
    --config)     config="$2"; shift 2 ;;
    -o|--out)     out="$2"; shift 2 ;;
    -n|--members) members="$2"; shift 2 ;;
    --seed)       seed="$2"; shift 2 ;;
    *) echo "unknown option: $1" >&2; exit 2 ;;
  esac
done
[ -n "$config" ] && [ -n "$out" ] || { echo "usage: $0 --config DIR -o FILE [-n N] [--seed S]" >&2; exit 2; }

mkdir -p "$(dirname "$out")"

LC_ALL=C.UTF-8 awk -F, -v members="$members" -v seed="$seed" -v out="$out" '
BEGIN {
  srand(seed)
  split("B1 B2 B3 B4 M1 M2 D", GRADES, " ")
  split("0.12 0.12 0.30 0.20 0.14 0.08 0.04", GRADE_W, " ")
  # preference weights per rank: "role:w ..."; roles missing get DEFAULT_PREF_W
  PREF[1] = "tea:0.42 coffee:0.25 latte:0.15 cashier:0.10 support:0.05 water:0.03"
  PREF[2] = "tea:0.20 cashier:0.20 coffee:0.18 support:0.18 water:0.12 latte:0.12"
  PREF[3] = "support:0.35 water:0.23 latte:0.12 cashier:0.10 coffee:0.10 tea:0.10"
  DEFAULT_PREF_W = 0.08
  split("0 0.03 0.05", P_PREF_EMPTY, " ")
  SK["B1"] = "0.60 0.30 0.10 0.00"; SK["B2"] = "0.40 0.35 0.20 0.05"; SK["B3"] = "0.20 0.35 0.35 0.10"
  SK_SENIOR = "0.15 0.30 0.35 0.20"
  P_SKILL_UP = 0.5
  P_LOADING = 0.45; P_ALL_DAY = 0.18; P_DAY_OFF = 0.12; P_SAME = 0.35; P_HOLE = 0.10
  P_SETUP_FIRST = 0.6; P_SETUP_ELSE = 0.1; P_CLEAN_LAST = 0.6; P_CLEAN_ELSE = 0.1
  split("0.25 0.25 0.30 0.10 0.10", BLEN, " ")
  nF = split("佐藤 鈴木 高橋 田中 伊藤 渡辺 山本 中村 小林 加藤 吉田 山田 佐々木 山口 松本 井上 木村 林 斎藤 清水 山崎 森 池田 橋本 阿部 石川 山下 中島 石井 小川", FAM, " ")
  nG = split("翔 蓮 陽斗 湊 大和 悠真 颯太 樹 蒼 健太 結衣 陽菜 葵 さくら 美咲 凛 芽依 彩花 優奈 千尋 拓海 直樹 亮 花 真央 遥 奏 光 和也 あかり", GIV, " ")
  if (members > nF * nG) { print "too many members for the name lists" > "/dev/stderr"; exit 1 }
}

# --- read slots.csv (1st file) and roles.csv (2nd file) ---
FILENAME != prevfile { prevfile = FILENAME; fileno++ }
fileno == 1 && FNR > 1 {
  d = $1
  if (!(d in seen)) { seen[d] = 1; dates[++nd] = d }
  k = ++cnt[d]; slot[d, k] = $2; kind[d, k] = $3
  if ($3 == "service") nsvc++
}
fileno == 2 && FNR > 1 {
  roles[++nr] = $1
  need += $4
  if ($3 == "1") skr[++nsr] = $1
}

# pick an index from a list of weights w[1..n]
function pick(w, n,    i, tot, u) {
  for (i = 1; i <= n; i++) tot += w[i]
  u = rand() * tot
  for (i = 1; i <= n; i++) { u -= w[i]; if (u < 0) return i }
  return n
}
function pick_str(s,    a, w, n, i) {
  n = split(s, a, " ")
  for (i = 1; i <= n; i++) w[i] = a[i]
  return pick(w, n) - 1
}
function block_length(n,    i, w, idx) {
  for (i = 1; i <= n; i++) {
    idx = int((i - 1) * 5 / n) + 1; if (idx > 5) idx = 5
    w[i] = BLEN[idx]
  }
  return pick(w, n)
}
# choose a role for preference rank k, excluding already chosen ones (chosen[] set)
function pick_pref(k, chosen,    a, n, i, p, w, name, m, ws) {
  n = split(PREF[k], a, " ")
  for (i = 1; i <= n; i++) { split(a[i], p, ":"); ws[p[1]] = p[2] }
  m = 0
  for (i = 1; i <= nr; i++) {
    if (roles[i] in chosen) continue
    name[++m] = roles[i]
    w[m] = (roles[i] in ws) ? ws[roles[i]] : DEFAULT_PREF_W
  }
  return name[pick(w, m)]
}
# fill on[1..cnt[d]] for date d; returns 1 if "service" present
function day_pattern(d,    n, j, u, ns, nsu, nse, nc, svc, length_, start, hole, p1, p2) {
  n = cnt[d]
  for (j = 1; j <= n; j++) on[j] = 0
  ns = 0
  for (j = 1; j <= n; j++) if (kind[d, j] == "service") svc[++ns] = j
  for (j = 1; j <= n; j++) if (kind[d, j] == "loading" && rand() < P_LOADING) on[j] = 1
  if (ns == 0) return
  u = rand()
  if (u < P_ALL_DAY) {
    for (j = 1; j <= n; j++) if (kind[d, j] != "loading") on[j] = 1
  } else if (u >= P_ALL_DAY + P_DAY_OFF) {
    length_ = block_length(ns)
    start = int(rand() * (ns - length_ + 1))          # 0-based
    for (j = 1; j <= length_; j++) on[svc[start + j]] = 1
    if (length_ >= 3 && rand() < P_HOLE) {
      hole = 1 + int(rand() * (length_ - 2))          # 1..length-2 (0-based)
      on[svc[start + hole + 1]] = 0
    }
    p1 = (start == 0) ? P_SETUP_FIRST : P_SETUP_ELSE
    p2 = (start + length_ == ns) ? P_CLEAN_LAST : P_CLEAN_ELSE
    for (j = 1; j <= n; j++) {
      if (kind[d, j] == "setup"   && rand() < p1) on[j] = 1
      if (kind[d, j] == "cleanup" && rand() < p2) on[j] = 1
    }
  }
}

END {
  if (nd == 0 || nr == 0) { print "empty slots.csv / roles.csv" > "/dev/stderr"; exit 1 }
  header = "member_id\tname\tgrade\tpref\tskill"
  for (i = 1; i <= nd; i++) header = header "\t" dates[i]
  print header > out

  for (m = 1; m <= members; m++) {
    # unique name
    do { name = FAM[int(rand() * nF) + 1] " " GIV[int(rand() * nG) + 1] } while (name in used)
    used[name] = 1

    # preferences
    delete chosen; pref = ""; np = 0
    for (k = 1; k <= 3 && k <= nr; k++) {
      if (np > 0 && rand() < P_PREF_EMPTY[k]) break
      r = pick_pref(k, chosen); chosen[r] = 1; plist[++np] = r
      pref = pref (np > 1 ? " " : "") r
    }
    grade = GRADES[pick(GRADE_W, 7)]

    # availability: retry until at least one slot
    do {
      any = 0; hasprev = 0
      for (di = 1; di <= nd; di++) {
        d = dates[di]; n = cnt[d]
        ks = ""; for (j = 1; j <= n; j++) ks = ks kind[d, j] ","
        if (hasprev && prevks == ks && rand() < P_SAME) {
          for (j = 1; j <= n; j++) on[j] = pon[j]
        } else {
          day_pattern(d)
        }
        s = ""
        for (j = 1; j <= n; j++) if (on[j]) { s = s (s == "" ? "" : " ") slot[d, j]; any = 1; if (kind[d, j] == "service") svc_m[m] = 1 }
        av[di] = s
        if (index(ks, "service,")) { hasprev = 1; prevks = ks; for (j = 1; j <= n; j++) pon[j] = on[j] }
      }
    } while (!any)

    # skills (level 0 omitted)
    sk = ""
    for (i = 1; i <= nsr; i++) {
      r = skr[i]
      level = pick_str((grade in SK) ? SK[grade] : SK_SENIOR)
      if (np > 0 && plist[1] == r && rand() < P_SKILL_UP) { level++; if (level > 3) level = 3 }
      if (level) sk = sk (sk == "" ? "" : " ") r "=" level
    }

    line = sprintf("M%03d\t%s\t%s\t%s\t%s", m, name, grade, pref, sk)
    for (di = 1; di <= nd; di++) line = line "\t" av[di]
    print line > out
    delete plist
  }
  close(out)
  printf "%s: members=%d, dates=%d\n", out, members, nd
  seats = nsvc * need
  printf "service seats=%d (%d slots x %d people), members with a service slot=%d\n", seats, nsvc, need, length(svc_m)
  if (length(svc_m) > seats)
    printf "warning: more members than service seats; some will get no service slot\n" > "/dev/stderr"
}
' "$config/slots.csv" "$config/roles.csv"
