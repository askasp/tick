# tick

A kanban board for AI coding tasks. The board is made of files, and cron moves
the tasks along it.

```sh
t new "add a billing webhook"              # a task in its own worktree, off main
t new "expose it in the API" --on 1        # stacked: same worktree, queued after task 1
t new "fix the typo in help" --cli opencode  # coded by opencode (the local model) instead of claude
t                                          # the board
t log 1 -f                                 # watch it work
t say 1 "also handle refunds"              # send it back with your notes
t attach 1                                 # take over the agent's conversation yourself
```

## Setup

1. `ln -s ~/git/tick/bin/t ~/.local/bin/t`
2. `(crontab -l; echo '* * * * * $HOME/git/tick/bin/t tick') | crontab -`
3. `test/run`: about 30 seconds, with fake CLIs, so it costs no tokens.

## How it works

Four ideas taken from Linux:

| idea | here | Linux equivalent |
| --- | --- | --- |
| a task is a directory of small files | `~/.tick/tasks/0042/` | `/proc/PID/` |
| a pipeline is a directory of numbered links | `pipelines/local/10-implement → ../../steps/implement` | `/etc/rc3.d/S20foo → ../init.d/foo` |
| a step reports through its exit code | `0` next, `75` later, other = retry | `sysexits.h` (`75` = `EX_TEMPFAIL`) |
| a lock that dies with its process | `flock` on `tasks/0042/lock` | how every daemon avoids a pid file |

### A task

```
~/.tick/tasks/0042/
  task.md       what to do (line 1 is the title)
  pipeline      local | feature | …
  step          where it is: 30-review, or done
  repo  base  branch
  work/         its git worktree (a symlink to the parent's when stacked)
  feedback.md   what the implementer must fix next
  review.md     the last review
  hold          if this exists the task is paused, and it says why
  after         if stacked: the task this one waits for
  runs/         how many times each step has run
  history       one line per move;  log/  one file per step
```

`grep . ~/.tick/tasks/0042/*` shows all of it. To move a task by hand, write
to `step`. To pause it, `touch hold`.

### A pipeline

```
pipelines/local/    10-implement  20-test  30-review
pipelines/feature/  10-implement  20-test  30-review  40-pr  50-ci
```

`ls pipelines/feature` is the pipeline. To add a step, `ln -s` it in. To
reorder, `mv`. To pick a pipeline, `t new -p feature`.

### A step

A step is a plain script in `steps/`. It runs with the task directory as its
cwd, and you can run it by hand: `cd ~/.tick/tasks/0042 && ~/git/tick/steps/review`.

| exit | means | what the runner does |
| --- | --- | --- |
| 0 | finished | go to the next step, or to the step the script wrote into `goto` |
| 75 | not yet | run the same step next tick; this run doesn't count |
| other | failed | run it again next tick; after 3 runs, put the task on hold |

### How the implementer hears from the review

Through a file. When the reviewer says `VERDICT: changes`, the review step
copies its review into `feedback.md`, writes `implement` into `goto`, and exits
0. The implement step adds `feedback.md` below the task in its prompt, and
archives it once the code changes. Failing tests (`20-test`), failing CI
(`50-ci`) and you (`t say`) all use the same file, so the implementer has only
one place to look.

The agents remember nothing between runs. What they need is in the task
directory and in the commits on the branch.

### The scheduler

`t tick` runs every minute and starts `t run ID` in the background for each
unfinished task. `t run` takes the task's lock and runs steps one after another
until one of them says "not yet" or fails. There is no daemon and no pid file.
If the machine reboots mid-step, the kernel has already dropped the lock, so
the next tick runs that step again.

`t run 42` in your terminal is the same thing in the foreground: the "one
script that goes through the whole pipeline" and the kanban are the same code.

### Parallel tasks and stacks

- A plain `t new` gets its own worktree on a new branch off the trunk
  (`origin/main` when there is one). Tasks like that run in parallel.
- `t new "…" --on 42` stacks the new task. It shares 42's worktree and lock
  (both symlinks), branches from 42's branch, and waits until 42 is `done`.
  Each task in a stack is its own branch, and with `-p feature` its own PR.

### Agents and CLIs

`agents/implementer.md` and `agents/reviewer.md` are prompts with three
settings: `cli` (claude or opencode), `mode` (edit or read) and an optional
`model`. `agent NAME` runs one as a filter:

```sh
git diff | agent reviewer
```

Only `drivers/claude` and `drivers/opencode` know CLI flags, so adding a CLI
means adding one driver. `SLOTS_claude=3` and `SLOTS_opencode=1` in
`etc/tick.conf` cap how many agents run at once. When all slots are taken,
`agent` exits 75 and the step waits for the next tick.

## Commands

```
t new "what to do" [-p PIPELINE] [--on ID] [--cli claude|opencode] [--test CMD] [-r REPO]
t ls [-a]            the board
t run ID             run it now, in this terminal
t log ID [-f]        history and latest output
t say ID "notes"     back to implement, with your notes
t attach ID          resume the agent's conversation interactively
t hold ID [why]      pause
t resume ID [STEP]   unpause, and optionally jump to another step
t path ID            its worktree:  cd "$(t path 42)"
t rm ID              delete the task and its worktree (the branch stays)
t tick               what cron runs
```

## Not covered

- The `pr` and `ci` steps are tested only against a fake `gh`.
- A stack doesn't rebase. If a parent changes after its child has started,
  rebase the child yourself.
- claude's `acceptEdits` lets the implementer edit files, but not run every
  command. Set `CLAUDE_EDIT_MODE=bypassPermissions` in `etc/tick.conf` if your
  worktrees are safe to let it loose in.
