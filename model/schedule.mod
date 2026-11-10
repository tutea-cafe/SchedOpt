/* SchedOpt: shift scheduling for the school festival café (GNU MathProg)
 *
 *   glpsol -m model/schedule.mod -d out/2026.dat [-d weights.dat]
 *
 * The data file is generated from the event definition and the processed data
 * by scripts/make_dat.awk. Weights and thresholds below have defaults and can be
 * overridden by an extra data file.
 *
 * Load-in, setup and cleanup slots are worked by everyone who answered them on the
 * form, so only the service slots (café open) are optimized.
 */

/* ---------- Sets and data ---------- */

set M;                                   # members
param name{M} symbolic;
param grade{M} symbolic;

set R;                                   # roles
set RS within R;                         # roles with skill levels
param need_role{R} integer, >= 0;        # people per role in each service slot

set S dimen 2;                           # slots (date, slot)
set SV within S;                         # service slots (café open)
set SO := S diff SV;                     # load-in / setup / cleanup: everyone available works

set A dimen 3 within M cross S;          # (m, d, s): member m can work slot (d, s)

param pos{S} integer, >= 1;              # position of the slot within its date (slots.csv order)

param pref_rank{M, R} integer, >= 0, default 0;   # 1 = first preference, 0 = not preferred
param skill{M, RS} integer, >= 0, <= 3, default 0;
                                         # 0 none, 1 can assist, 2 can work alone, 3 can teach

/* ---------- Policy (defaults; override in a data file) ---------- */

param pref_score{k in 1..3} default 4 - k;        # score of the k-th preference
param lead_level integer, default 2;              # skill level that counts as "can work alone"
param lead_need{RS} integer, >= 0, default 1;     # such people per skill role in each service slot
param max_consecutive integer, >= 1, default 3;   # most slots in a row (setup / cleanup included)
param min_load integer, >= 0, default 1;          # fewest service slots per member (capped by availability)

param w_short default 1000;   # per missing person
param w_lead  default 100;    # per missing "can work alone" person
param w_pref  default 1;      # per preference score point
param w_fair  default 10;     # per service slot of the busiest member
param w_under default 50;     # per service slot a member gets below min_load

param out_csv symbolic default "out/assignment.csv";   # assignment, one line per (member, slot)

check {r in RS}: lead_need[r] <= need_role[r];

# service slots each member answered
param n_avail{m in M} := card({(m2, d, s) in A: m2 = m and (d, s) in SV});

# max_consecutive + 1 slots in a row, starting at slot (d, b), that include a service slot
set RUN{(d, b) in S} := {(d2, s) in S: d2 = d and pos[d2, s] >= pos[d, b] and pos[d2, s] <= pos[d, b] + max_consecutive};
set TOO_LONG := {(d, b) in S: card(RUN[d, b]) = max_consecutive + 1 and exists{(d2, s) in RUN[d, b]} (d2, s) in SV};

/* ---------- Variables ---------- */

var x{(m, d, s) in A, r in R: (d, s) in SV} binary;   # m works role r in service slot (d, s)

var short{(d, s) in SV, r in R} >= 0;                 # missing people per role
var short_lead{(d, s) in SV, r in RS} >= 0;           # missing "can work alone" people
var max_load >= 0;                                    # service slots of the busiest member
var under{m in M: n_avail[m] > 0} >= 0;               # service slots below min_load

/* ---------- Objective ---------- */

minimize cost:
    w_short * sum{(d, s) in SV, r in R} short[d, s, r]
  + w_lead  * sum{(d, s) in SV, r in RS} short_lead[d, s, r]
  - w_pref  * sum{(m, d, s) in A, r in R: (d, s) in SV and pref_rank[m, r] > 0}
                  pref_score[pref_rank[m, r]] * x[m, d, s, r]
  + w_fair  * max_load
  + w_under * sum{m in M: n_avail[m] > 0} under[m];

/* ---------- Constraints ---------- */

# One role at a time
s.t. one_role{(m, d, s) in A: (d, s) in SV}:
    sum{r in R} x[m, d, s, r] <= 1;

# Exactly the required number of people per role (missing people are penalized)
s.t. staff_role{(d, s) in SV, r in R}:
    sum{m in M: (m, d, s) in A} x[m, d, s, r] + short[d, s, r] = need_role[r];

# At least lead_need people who can work the role alone
s.t. lead{(d, s) in SV, r in RS}:
    sum{m in M: (m, d, s) in A and skill[m, r] >= lead_level} x[m, d, s, r]
  + short_lead[d, s, r] >= lead_need[r];

# At most max_consecutive slots in a row: in every run of max_consecutive + 1 slots, leave one free.
# Load-in / setup / cleanup slots count as worked when the member answered them.
s.t. consecutive{m in M, (d, b) in TOO_LONG: forall{(d2, s) in RUN[d, b]} (m, d2, s) in A}:
    sum{(d2, s) in RUN[d, b]} (if (d2, s) in SV then sum{r in R} x[m, d2, s, r] else 1) <= max_consecutive;

# Busiest member (service slots only)
s.t. load{m in M}:
    sum{(d, s) in SV, r in R: (m, d, s) in A} x[m, d, s, r] <= max_load;

# Everyone who answered a service slot works at least min_load of them (if they answered that many)
s.t. min_work{m in M: n_avail[m] > 0}:
    sum{(d, s) in SV, r in R: (m, d, s) in A} x[m, d, s, r] + under[m] >= min(min_load, n_avail[m]);

solve;

/* ---------- Output ---------- */

# One line per assignment; role is empty for load-in / setup / cleanup
printf "member_id,name,date,slot,role\n" > out_csv;
printf {(m, d, s) in A, r in R: (d, s) in SV and x[m, d, s, r] > 0.5}
  "%s,%s,%s,%s,%s\n", m, name[m], d, s, r >> out_csv;
printf {(m, d, s) in A: (d, s) in SO}
  "%s,%s,%s,%s,\n", m, name[m], d, s >> out_csv;

/* ---------- Report ---------- */

printf "\n== Assignment\n";
for {(d, s) in S} {
  printf "%s %-8s", d, s;
  for {{0}: (d, s) in SV} {
    for {r in R} {
      printf "  %s:", r;
      printf {m in M: (m, d, s) in A and x[m, d, s, r] > 0.5} " %s", name[m];
      printf {{0}: short[d, s, r] > 0.5} " (-%d)", short[d, s, r];
    }
  }
  for {{0}: (d, s) in SO} {
    printf " ";
    printf {m in M: (m, d, s) in A} " %s", name[m];
  }
  printf "\n";
}

printf "\n== Summary\n";
printf "missing people            : %d\n", sum{(d, s) in SV, r in R} short[d, s, r];
printf "missing can-work-alone    : %d\n", sum{(d, s) in SV, r in RS} short_lead[d, s, r];
printf "service slots of busiest  : %d\n", max_load;
printf "available but 0 service   : %d\n",
  card({m in M: n_avail[m] > 0 and sum{(d, s) in SV, r in R: (m, d, s) in A} x[m, d, s, r] < 0.5});
printf "below min_load (slots)    : %d\n", sum{m in M: n_avail[m] > 0} under[m];
printf "assigned to 1st/2nd/3rd/other preference: %d / %d / %d / %d\n",
  sum{(m, d, s) in A, r in R: (d, s) in SV and pref_rank[m, r] = 1} x[m, d, s, r],
  sum{(m, d, s) in A, r in R: (d, s) in SV and pref_rank[m, r] = 2} x[m, d, s, r],
  sum{(m, d, s) in A, r in R: (d, s) in SV and pref_rank[m, r] = 3} x[m, d, s, r],
  sum{(m, d, s) in A, r in R: (d, s) in SV and pref_rank[m, r] = 0} x[m, d, s, r];
printf "people in load-in / setup / cleanup:";
printf {(d, s) in SO} "  %s %s %d", d, s, card({m in M: (m, d, s) in A});
printf "\n";

end;
