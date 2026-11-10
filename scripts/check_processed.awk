# Check processed data (one TSV) against the event definition. Run after every hand edit.
#
#   gawk -f scripts/check_processed.awk config/2026/roles.csv config/2026/slots.csv data/processed/2026.tsv
#
# Prints "OK" or one line per problem (to stderr) and exits with status 1.

function bad(msg) { print FILENAME ":" FNR ": " msg > "/dev/stderr"; errors++ }

BEGIN { FS = "\t" }

FILENAME == ARGV[1] {                          # roles.csv: role,label,skill
  if (FNR > 1) { split($0, a, ","); isrole[a[1]]; if (a[3] == 1) isskill[a[1]] }
  next
}
FILENAME == ARGV[2] {                          # slots.csv: date,slot,kind,start,end,label
  if (FNR > 1) { split($0, a, ","); isslot[a[1], a[2]]; if (!(a[1] in seendate)) { seendate[a[1]]; nd++ } }
  next
}
FNR == 1 {
  asorti(seendate, dates)
  want = "member_id\tname\tgrade\tpref\tskill"
  for (k = 1; k <= nd; k++) want = want "\t" dates[k]
  if ($0 != want) bad("header must be: " gensub(/\t/, " ", "g", want))
  for (i = 6; i <= NF; i++) date[i] = $i
  next
}
{
  for (i = 1; i <= NF; i++)
    if ($i ~ /^ | $/) { bad("column " i " has leading/trailing spaces (padded for alignment? remove the padding)"); break }
  if (NF != 5 + nd) bad("expected " 5 + nd " columns, got " NF)
  if ($1 !~ /^[^ ]+$/) bad("member_id must be non-empty without spaces: " $1)
  if ($1 in seen) bad("duplicate member_id: " $1); seen[$1]
  if ($2 == "") bad("empty name")
  if ($3 !~ /^(B[1-4]|M[12]|D)$/) bad("unknown grade: " $3)

  m = split($4, v, " ")
  for (j = 1; j <= m; j++) if (!(v[j] in isrole)) bad("unknown role in pref: " v[j])

  m = split($5, v, " "); split("", once)
  for (j = 1; j <= m; j++) {
    if (split(v[j], kv, "=") != 2) { bad("skill must be role=level: " v[j]); continue }
    if (!(kv[1] in isskill)) bad("not a skill role: " kv[1])
    else if (kv[2] !~ /^[0-3]$/) bad("skill level must be 0-3: " v[j])
    if (kv[1] in once) bad("skill given twice: " kv[1]); once[kv[1]]
  }

  for (i = 6; i <= NF; i++) {
    m = split($i, v, " ")
    for (j = 1; j <= m; j++) if (!((date[i], v[j]) in isslot)) bad("unknown slot on " date[i] ": " v[j])
  }
}
END {
  if (errors) { print errors " error(s)" > "/dev/stderr"; exit 1 }
  print "OK"
}
