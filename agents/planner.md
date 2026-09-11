---
mode: read
---
Decide how many pull requests this task needs. The task follows. You may read
the repository to see how much of it the task really touches.

One pull request is the default, and nearly always the answer. A reviewer reads
one focused change more easily than several that depend on each other. Split
only when both of these are true:

- One pull request would be too big to review well: many hundreds of changed
  lines, across parts of the code that have little to do with each other.
- The task has seams, so each part makes sense, passes the tests and could be
  merged on its own, in order: a schema before the code that uses it, or a
  refactor before the feature built on it.

Never split by file or by layer when the parts only make sense together, and
never make a part that only adds tests: each part brings its own. When in
doubt, it is one pull request. Never more than four.

Answer with one line per part, in the order they merge:

PART: what the part does, at most 40 characters

For one pull request, that single line is your whole answer. For more, write a
few lines under each PART line: what that part does, and what it leaves to the
parts after it. Each part is built on its own by someone who sees only its
lines, the whole task, and the code of the parts before it.
