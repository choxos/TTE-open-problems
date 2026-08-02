#!/usr/bin/env python3
"""Find comparisons against a possibly-missing variable that are read as numbers.

SEQ-01 completed twelve scenarios, wrote 510,000 rows and reported four
conclusions while having estimated nothing, because its outcome column was

    Y = as.integer(hist$event_time[ids[keep]] == t + 1L)

and `event_time` is NA for everyone who never fails. `NA == t + 1L` is NA rather
than FALSE, so the outcome was missing on most person-periods and every model
downstream received nothing. Nothing in R complains: `as.integer` of NA is NA,
`sum` of NA is NA, and a logical subscript containing NA silently returns NA
rows rather than dropping them.

The line reads exactly like the correct one, which is why review does not catch
it. What makes it a defect rather than a style question is the destination: a
comparison used inside `if` fails loudly, and a comparison used inside
`as.integer` or `sum` becomes a silent missing number. This reports only the
second kind, against variables the study itself initializes to NA.

Being narrow is the point. An earlier version flagged every line mentioning a
name that had ever been assigned NA and produced 233 hits across 18 studies,
which is the same as producing none.

What it does not see, so a clean run is not a proof: missingness that arrives
rather than being declared. It recognizes a variable as possibly-missing only
where the study writes `rep(NA, ...)`, an NA-filled matrix or vector, or
`$col <- NA`. NA introduced by a merge that does not match, by a subscript out
of range, or by arithmetic that overflows is invisible to it, and so is any
comparison whose result is consumed more than one expression away from where it
is written.

  python3 build/studies/scan_na_comparisons.py
  python3 build/studies/scan_na_comparisons.py --study studies/SEQ-01-...
"""

import argparse
import glob
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

# A variable is "possibly missing" only when the study creates a whole vector of
# NA and fills it in. A scalar `x <- NA_real_` sentinel inside a guard clause is
# not this defect and was the main source of noise.
NA_ASSIGN = [
    re.compile(r"(?:^|[\s(,])([A-Za-z_.][A-Za-z0-9_.]*)\s*(?:<-|=)\s*rep\(\s*NA"),
    re.compile(r"(?:^|[\s(,])([A-Za-z_.][A-Za-z0-9_.]*)\s*(?:<-|=)\s*"
               r"(?:matrix|array|numeric|integer|logical|vector)\(\s*NA"),
    re.compile(r"\$([A-Za-z_.][A-Za-z0-9_.]*)\s*(?:<-|:=)\s*NA(?:_[a-z]+_)?\s*(?:$|[,)#])"),
]

# The comparison has to end up somewhere that turns NA into a silent number.
NUMERIC_SINK = re.compile(
    r"\b(?:as\.integer|as\.numeric|as\.double|sum|mean|cumsum|prod|tabulate|"
    r"weighted_tabulate|rowsum|table|xtabs)\s*\("
)

COMPARISON = re.compile(r"==|!=|>=|<=|(?<![<>=!-])>(?!=)|(?<![<>=!-])<(?![-=])")
GUARDED = re.compile(r"is\.na|isTRUE|isFALSE|%in%|ifelse\(|na\.rm\s*=\s*TRUE|coalesce")


def na_variables(text):
    found = set()
    for pat in NA_ASSIGN:
        for m in pat.finditer(text):
            found.add(m.group(1))
    return {v for v in found if len(v) > 1}


def logical_lines(path):
    """Join continuation lines so a guard on the previous line still counts."""
    raw = open(path, encoding="utf8", errors="ignore").read().splitlines()
    out, buf, start, depth = [], "", 1, 0
    for i, line in enumerate(raw, 1):
        code = re.sub(r"#.*$", "", line)
        if not buf:
            start = i
        buf = (buf + " " + code.strip()).strip()
        depth += code.count("(") + code.count("[") - code.count(")") - code.count("]")
        trailing = re.search(r"(?:[+\-*/&|,]|<-|%in%|==|>=|<=)\s*$", code.strip())
        if depth <= 0 and not trailing:
            if buf:
                out.append((start, buf))
            buf, depth = "", 0
    if buf:
        out.append((start, buf))
    return out


def scan_file(path, extra_vars):
    text = open(path, encoding="utf8", errors="ignore").read()
    vars_here = na_variables(text) | extra_vars
    if not vars_here:
        return []
    alt = "|".join(re.escape(v) for v in sorted(vars_here, key=len, reverse=True))
    # The NA variable must be an operand of the comparison, not merely present.
    # Subscripts nest: the defect this exists to catch is written
    # `hist$event_time[ids[keep]] == t + 1L`, and a `\[[^\]]*\]` subscript
    # pattern cannot match `[ids[keep]]`, so the first version of this scanner
    # reported the known defect as clean. Allow any run of subscript characters.
    # `<-` is an assignment, not a comparison, so a subscript run must not be
    # allowed to slide into one: `truncation[t + 1L] <- mean(...)` is the
    # assignment target and reported as a comparison against `truncation`.
    cmp_op = r"(?:==|!=|>=|<=|(?<![<>=!-])>(?![-=])|(?<![<>=!-])<(?![-=]))"
    operand = re.compile(
        r"(?:\$|\b)(" + alt + r")\b[\w\[\]$.,+*/\s-]{0,60}?" + cmp_op
        + r"|" + cmp_op + r"\s*(?:\w+\$)?(" + alt + r")\b"
    )
    hits = []
    for ln, expr in logical_lines(path):
        if not (COMPARISON.search(expr) and NUMERIC_SINK.search(expr)):
            continue
        m = operand.search(expr)
        if not m or GUARDED.search(expr):
            continue
        hits.append((ln, m.group(1) or m.group(2), expr))
    return hits


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--study", help="one study directory; default is all of them")
    a = ap.parse_args()

    studies = ([a.study.rstrip("/")] if a.study
               else sorted(d for d in glob.glob(os.path.join(ROOT, "studies", "*"))
                           if os.path.isdir(os.path.join(d, "R"))))
    total = 0
    for study in studies:
        files = sorted(glob.glob(os.path.join(study, "R", "*.R")))
        # A variable created as NA in the mechanism is still NA in the estimators.
        shared = set()
        for f in files:
            shared |= na_variables(open(f, encoding="utf8", errors="ignore").read())
        rows = []
        for f in files:
            for ln, var, expr in scan_file(f, shared):
                rows.append((os.path.relpath(f, ROOT), ln, var, expr))
        if rows:
            print(f"\n=== {os.path.basename(study)} ===")
            for rel, ln, var, expr in rows:
                print(f"  {rel}:{ln}  [{var}]")
                print(f"      {expr[:180]}")
            total += len(rows)
    print(f"\n{total} unguarded numeric-sink comparison(s) across {len(studies)} studies")
    return 1 if total else 0


if __name__ == "__main__":
    sys.exit(main())
