#!/usr/bin/env bash
# Render a solved schedule as an SVG image (members x slots).
#
# Usage:
#   scripts/render_schedule.sh --config config/2026 --processed data/processed/2026.tsv \
#       --assignment out/assignment.csv -o out/schedule.svg [--title "シフト表 2026"]
#
# Rows are members, columns are slots grouped by date. A cell shows the role a member works,
# "参加" for load-in / setup / cleanup, a dashed outline when the member was available but not
# assigned, and nothing when the member was not available. The last row shows missing people.
# Hovering a cell in a browser shows its details. Requires gawk (mktime / strftime).
set -euo pipefail

config="" processed="" assignment="" out="" title=""
while [ $# -gt 0 ]; do
  case "$1" in
    --config)     config="$2"; shift 2 ;;
    --processed)  processed="$2"; shift 2 ;;
    --assignment) assignment="$2"; shift 2 ;;
    -o|--out)     out="$2"; shift 2 ;;
    --title)      title="$2"; shift 2 ;;
    *) echo "unknown option: $1" >&2; exit 2 ;;
  esac
done
if [ -z "$config" ] || [ -z "$processed" ] || [ -z "$assignment" ] || [ -z "$out" ]; then
  echo "usage: $0 --config DIR --processed FILE --assignment FILE -o FILE [--title T]" >&2
  exit 2
fi
[ -n "$title" ] || title="シフト表 $(basename "${config%/}")"

mkdir -p "$(dirname "$out")"

LC_ALL=C.UTF-8 gawk -v title="$title" -v out="$out" '
BEGIN {
  split("#2a78d6 #eb6834 #1baf7a #eda100 #e87ba4 #008300 #6250d6 #e34948", CAT, " ")
  NCAT = 8
  SURFACE = "#fcfcfb"; TEXT_PRIMARY = "#0b0b0b"; TEXT_SECONDARY = "#52514e"; TEXT_MUTED = "#8a8984"
  GRID = "#e4e3df"; NEUTRAL_FILL = "#d9d8d3"; CRITICAL = "#d03b3b"
  FONT = "\x27Noto Sans JP\x27, \x27Hiragino Sans\x27, \x27Yu Gothic\x27, sans-serif"
  CELL_W = 64; CELL_H = 26; GAP = 2; DATE_GAP = 12; NAME_W = 120; COUNT_W = 44; LEFT = 24; TOP = 24
  WEEKDAYS = "月火水木金土日"
  KIND_LABEL["loading"] = "荷運び"; KIND_LABEL["setup"] = "準備"; KIND_LABEL["cleanup"] = "片付け"
}

function esc(s) {
  gsub(/&/, "\\&amp;", s); gsub(/</, "\\&lt;", s); gsub(/>/, "\\&gt;", s)
  gsub(/"/, "\\&quot;", s); gsub(/\x27/, "\\&#x27;", s)
  return s
}
function kl(kind, fallback) { return (kind in KIND_LABEL) ? KIND_LABEL[kind] : fallback }
function chan(hex,    c) {
  c = strtonum("0x" hex) / 255
  return (c <= 0.04045) ? c / 12.92 : ((c + 0.055) / 1.055) ^ 2.4
}
# primary text or white, whichever reads better on the fill (WCAG relative luminance)
function ink_on(fill,    lum) {
  lum = 0.2126 * chan(substr(fill, 2, 2)) + 0.7152 * chan(substr(fill, 4, 2)) + 0.0722 * chan(substr(fill, 6, 2))
  return (1.05 / (lum + 0.05) >= (lum + 0.05) / 0.05) ? "#ffffff" : TEXT_PRIMARY
}
function w(s) { lines[++nl] = s }

# file 1: slots.csv  2: roles.csv  3: processed tsv  4: assignment csv
FILENAME != prevfile { prevfile = FILENAME; fileno++ }

fileno == 1 && FNR > 1 {
  split($0, a, ",")
  ns++; sdate[ns] = a[1]; sslot[ns] = a[2]; skind[ns] = a[3]; sstart[ns] = a[4]; send[ns] = a[5]; slabel[ns] = a[6]
  if (!(a[1] in seen)) { seen[a[1]] = 1; dlist[++nd0] = a[1] }
  next
}
fileno == 2 && FNR > 1 {
  split($0, a, ",")
  nr++; rrole[nr] = a[1]; rlabel[a[1]] = a[2]; need[a[1]] = a[4] + 0
  if (nr > NCAT) { print "at most " NCAT " roles can be colored" > "/dev/stderr"; fail = 1; exit 1 }
  rcolor[a[1]] = CAT[nr]
  next
}
fileno == 3 {
  n = split($0, a, "\t")
  if (FNR == 1) { for (i = 1; i <= n; i++) hcol[i] = a[i]; nh = n; next }
  nm++; mid[nm] = a[1]; mname[nm] = a[2]; mgrade[nm] = a[3]
  for (i = 6; i <= nh; i++) {
    k = split(a[i], sl, " ")
    for (j = 1; j <= k; j++) avail[a[1], hcol[i], sl[j]] = 1
  }
  next
}
fileno == 4 && FNR > 1 {
  split($0, a, ",")
  asg[a[1], a[3], a[4]] = 1; arole[a[1], a[3], a[4]] = a[5]
  next
}

END {
  if (fail) exit 1
  # sorted dates
  nd = asort(dlist, dates)

  # column x positions, grouped by date
  nc = 0; x = LEFT + NAME_W
  for (i = 1; i <= nd; i++) {
    if (i > 1) x += DATE_GAP
    for (s = 1; s <= ns; s++) if (sdate[s] == dates[i]) {
      nc++; cx[nc] = x; cs[nc] = s; x += CELL_W + GAP
    }
  }
  grid_right = x - GAP
  width = grid_right + COUNT_W + LEFT
  legend_y = TOP + 36
  head_y = legend_y + 40
  rows_y = head_y + 50
  height = rows_y + (nm + 1) * (CELL_H + GAP) + 16 + 24

  w(sprintf("<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"%d\" height=\"%d\" viewBox=\"0 0 %d %d\" font-family=\"%s\" font-size=\"12\">", width, height, width, height, FONT))
  w(sprintf("<rect width=\"100%%\" height=\"100%%\" fill=\"%s\"/>", SURFACE))

  # shortage per service slot / role
  total_short = 0
  for (c = 1; c <= nc; c++) {
    s = cs[c]
    if (skind[s] != "service") continue
    detail = ""; tot = 0
    for (r = 1; r <= nr; r++) {
      role = rrole[r]; cntr = 0
      for (m = 1; m <= nm; m++)
        if (((mid[m], sdate[s], sslot[s]) in asg) && arole[mid[m], sdate[s], sslot[s]] == role) cntr++
      if (cntr < need[role]) {
        d = need[role] - cntr; tot += d
        detail = detail (detail == "" ? "" : "、") rlabel[role] " " d "人"
      }
    }
    if (tot) { mdetail[c] = detail; mtot[c] = tot; total_short += tot }
  }
  w(sprintf("<text x=\"%d\" y=\"%d\" font-size=\"18\" font-weight=\"700\" fill=\"%s\">%s</text>", LEFT, TOP + 4, TEXT_PRIMARY, esc(title)))
  w(sprintf("<text x=\"%d\" y=\"%d\" fill=\"%s\">%d人 · 営業中の不足 %d人</text>", LEFT, TOP + 24, TEXT_SECONDARY, nm, total_short))

  # legend
  lx = LEFT
  for (r = 1; r <= nr + 2; r++) {
    if (r <= nr) {
      label = rlabel[rrole[r]]
      w(sprintf("<rect x=\"%d\" y=\"%d\" width=\"16\" height=\"16\" rx=\"4\" fill=\"%s\"/>", lx, legend_y, rcolor[rrole[r]]))
    } else if (r == nr + 1) {
      label = "荷運び・準備・片付け"
      w(sprintf("<rect x=\"%d\" y=\"%d\" width=\"16\" height=\"16\" rx=\"4\" fill=\"%s\"/>", lx, legend_y, NEUTRAL_FILL))
    } else {
      label = "参加可（割り当てなし）"
      w(sprintf("<rect x=\"%s\" y=\"%s\" width=\"15\" height=\"15\" rx=\"4\" fill=\"none\" stroke=\"%s\" stroke-dasharray=\"3 2\"/>", lx + 0.5, legend_y + 0.5, TEXT_MUTED))
    }
    w(sprintf("<text x=\"%d\" y=\"%d\" fill=\"%s\">%s</text>", lx + 22, legend_y + 12, TEXT_SECONDARY, esc(label)))
    lx += 22 + 13 * length(label) + 18
  }

  # column headers: date, then slot
  for (i = 1; i <= nd; i++) {
    d = dates[i]; first = ""; last = ""
    for (c = 1; c <= nc; c++) if (sdate[cs[c]] == d) { if (first == "") first = cx[c]; last = cx[c] }
    split(d, ymd, "-")
    wd = strftime("%u", mktime(ymd[1] " " ymd[2] + 0 " " ymd[3] + 0 " 12 0 0"))
    label = sprintf("%d/%d（%s）", ymd[2], ymd[3], substr(WEEKDAYS, wd, 1))
    w(sprintf("<text x=\"%d\" y=\"%d\" font-weight=\"700\" fill=\"%s\">%s</text>", first, head_y + 12, TEXT_PRIMARY, label))
    w(sprintf("<line x1=\"%d\" y1=\"%d\" x2=\"%d\" y2=\"%d\" stroke=\"%s\"/>", first, head_y + 18, last + CELL_W, head_y + 18, GRID))
  }
  for (c = 1; c <= nc; c++) {
    s = cs[c]
    top = kl(skind[s], sstart[s])
    if (skind[s] != "service" && sstart[s] != "") bottom = sstart[s] "–" send[s]
    else bottom = (send[s] != "") ? "–" send[s] : ""
    w(sprintf("<text x=\"%s\" y=\"%d\" text-anchor=\"middle\" fill=\"%s\">%s</text>", cx[c] + CELL_W / 2, head_y + 32, TEXT_SECONDARY, esc(top)))
    w(sprintf("<text x=\"%s\" y=\"%d\" text-anchor=\"middle\" font-size=\"10\" fill=\"%s\">%s</text>", cx[c] + CELL_W / 2, head_y + 45, TEXT_MUTED, esc(bottom)))
  }
  w(sprintf("<text x=\"%d\" y=\"%d\" text-anchor=\"end\" fill=\"%s\">担当</text>", grid_right + COUNT_W - 4, head_y + 32, TEXT_SECONDARY))
  w(sprintf("<text x=\"%d\" y=\"%d\" text-anchor=\"end\" font-size=\"10\" fill=\"%s\">営業中</text>", grid_right + COUNT_W - 4, head_y + 45, TEXT_MUTED))

  # member rows
  for (m = 1; m <= nm; m++) {
    y0 = rows_y + (m - 1) * (CELL_H + GAP)
    if ((m - 1) % 2)
      w(sprintf("<rect x=\"%d\" y=\"%d\" width=\"%d\" height=\"%d\" fill=\"#f4f3f0\"/>", LEFT, y0 - 1, grid_right + COUNT_W - LEFT, CELL_H + 2))
    w(sprintf("<text x=\"%d\" y=\"%d\" fill=\"%s\">%s<tspan dx=\"6\" font-size=\"10\" fill=\"%s\">%s</tspan></text>", LEFT, y0 + 17, TEXT_PRIMARY, esc(mname[m]), TEXT_MUTED, esc(mgrade[m])))
    n_service = 0
    for (c = 1; c <= nc; c++) {
      s = cs[c]; x0 = cx[c]
      key = mid[m] SUBSEP sdate[s] SUBSEP sslot[s]
      when = sdate[s] " " kl(skind[s], slabel[s])
      if ((key in asg) && skind[s] == "service") {
        role = arole[key]; n_service++; fill = rcolor[role]
        w(sprintf("<g><title>%s · %s · %s</title><rect x=\"%d\" y=\"%d\" width=\"%d\" height=\"%d\" rx=\"4\" fill=\"%s\"/><text x=\"%s\" y=\"%d\" text-anchor=\"middle\" fill=\"%s\">%s</text></g>",
          esc(mname[m]), esc(when), esc(rlabel[role]), x0, y0, CELL_W, CELL_H, fill, x0 + CELL_W / 2, y0 + 17, ink_on(fill), esc(rlabel[role])))
      } else if (key in asg) {
        w(sprintf("<g><title>%s · %s</title><rect x=\"%d\" y=\"%d\" width=\"%d\" height=\"%d\" rx=\"4\" fill=\"%s\"/><text x=\"%s\" y=\"%d\" text-anchor=\"middle\" fill=\"%s\">参加</text></g>",
          esc(mname[m]), esc(when), x0, y0, CELL_W, CELL_H, NEUTRAL_FILL, x0 + CELL_W / 2, y0 + 17, TEXT_SECONDARY))
      } else if (key in avail) {
        w(sprintf("<g><title>%s · %s · 参加可（割り当てなし）</title><rect x=\"%s\" y=\"%s\" width=\"%d\" height=\"%d\" rx=\"4\" fill=\"%s\" stroke=\"%s\" stroke-dasharray=\"3 2\"/></g>",
          esc(mname[m]), esc(when), x0 + 0.5, y0 + 0.5, CELL_W - 1, CELL_H - 1, SURFACE, TEXT_MUTED))
      }
    }
    w(sprintf("<text x=\"%d\" y=\"%d\" text-anchor=\"end\" fill=\"%s\">%d</text>", grid_right + COUNT_W - 4, y0 + 17, TEXT_SECONDARY, n_service))
  }

  # missing people row
  y0 = rows_y + nm * (CELL_H + GAP) + 8
  w(sprintf("<line x1=\"%d\" y1=\"%d\" x2=\"%d\" y2=\"%d\" stroke=\"%s\"/>", LEFT, y0 - 5, grid_right + COUNT_W, y0 - 5, GRID))
  w(sprintf("<text x=\"%d\" y=\"%d\" font-weight=\"700\" fill=\"%s\">不足</text>", LEFT, y0 + 17, TEXT_PRIMARY))
  for (c = 1; c <= nc; c++) if (c in mtot) {
    s = cs[c]
    w(sprintf("<g><title>%s %s 不足: %s</title><text x=\"%s\" y=\"%d\" text-anchor=\"middle\" font-weight=\"700\" fill=\"%s\">▲%d</text></g>",
      esc(sdate[s]), esc(slabel[s]), esc(mdetail[c]), cx[c] + CELL_W / 2, y0 + 17, CRITICAL, mtot[c]))
  }
  w(sprintf("<text x=\"%d\" y=\"%d\" font-size=\"10\" fill=\"%s\">▲ = その枠で足りない人数（セルにカーソルを合わせると内訳）</text>", LEFT, height - 12, TEXT_MUTED))
  w("</svg>")

  for (i = 1; i <= nl; i++) print lines[i] > out
  close(out)
  printf "%s: %d members, %d slots, missing %d\n", out, nm, nc, total_short
}
' "$config/slots.csv" "$config/roles.csv" "$processed" "$assignment"
