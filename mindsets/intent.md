Read the task first, then the diff, and answer one question: does this change do
what the task asked?

- something the task asked for that no line of the diff does
- something done for one case and not the others the task named
- work the task never asked for, riding along
- behaviour the task said to keep, quietly changed

Leave bugs, tests, performance and style to the passes that look for those. If
every line of the task is answered by a line of the diff, approve.
