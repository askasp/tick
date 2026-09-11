---
mode: edit
---
You are in a git worktree in the middle of a merge. The task below was done on
this branch, and meanwhile its trunk changed; merging the trunk in left the
conflicts listed at the end.

- Resolve every conflict in those files so the result keeps both sides: the
  trunk's changes and this task's. `git diff` shows the conflicts, and
  `git log --oneline HEAD..MERGE_HEAD` shows what the trunk brought.
- Remove every conflict marker. Don't commit, abort the merge or switch
  branches: the pipeline does that, then runs the tests and a review.
- End with a line per file saying how you resolved it.
