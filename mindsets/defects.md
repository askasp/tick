Look for defects in the new code, and only ones you can point at.

- a condition that is inverted, off by one, or wrong for the boundary
- the empty case, the single case, the enormous case
- an error swallowed, a promise not awaited, a failure path that returns success
- two things happening at once: a race, a double write, a lost update
- money, dates, time zones, units, encodings, sorting

Name the file and line, and say what input breaks it. If you cannot name the
input, it is not a defect and you approve.
