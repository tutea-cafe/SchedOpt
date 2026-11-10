# Check an assignment written by model/schedule.mod against the processed data:
#   - every assignment is in a slot the member answered on the form
#   - no member is assigned twice to one slot
#   - (with -v max_consecutive=N) no member works more than N slots in a row
#
#   gawk -v max_consecutive=3 -f scripts/check_assignment.awk \
#     config/2026/slots.csv data/processed/2026.tsv out/assignment.csv

function bad(msg) { print FILENAME ":" FNR ": " msg > "/dev/stderr"; errors++ }

FILENAME == ARGV[1] {                    # slots.csv: position of each slot within its date
  if (FNR > 1) { split($0, a, ","); pos[a[1], a[2]] = ++npos[a[1]] }
  next
}
FILENAME == ARGV[2] {                    # processed data (TSV)
  FS = "\t"; $0 = $0
  if (FNR == 1) { for (i = 6; i <= NF; i++) date[i] = $i }
  else for (i = 6; i <= NF; i++) { n = split($i, v, " "); for (j = 1; j <= n; j++) ok[$1, date[i], v[j]] }
  next
}
FNR > 1 {                                # assignment (CSV): member_id,name,date,slot,role
  FS = ","; $0 = $0
  if (!(($1, $3, $4) in ok)) bad("not available: " $1 " " $3 " " $4)
  if (++seen[$1, $3, $4] > 1) bad("assigned twice: " $1 " " $3 " " $4)
  works[$1, $3, pos[$3, $4]]; member[$1]; day[$3]
  total++
}
END {
  longest = 0
  for (m in member) for (d in day) {
    run = 0
    for (p = 1; p <= npos[d]; p++) {
      run = ((m, d, p) in works) ? run + 1 : 0
      if (run > longest) longest = run
      if (max_consecutive && run == max_consecutive + 1) { print "more than " max_consecutive " slots in a row: " m " " d > "/dev/stderr"; errors++ }
    }
  }
  if (errors) { print errors " problem(s)" > "/dev/stderr"; exit 1 }
  print "OK (" total + 0 " assignments, longest run " longest " slots)"
}
