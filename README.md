# tick

A kanban board for AI coding tasks. The board is plain files, and cron moves
the tasks along. claude or opencode does the coding, and shell scripts do
everything else.

## Setup

1. `ln -s ~/git/tick/bin/t ~/.local/bin/t`
2. `(crontab -l; echo '* * * * * $HOME/git/tick/bin/t tick') | crontab -`
3. `t doctor`: checks the tools and the two lines above, and lists the pipelines.

`test/run` runs the test suite. It uses fake CLIs, so it costs no tokens.

## Daily use

```sh
cd ~/git/shop
t new "Add a discount code field"     # a task in its own worktree, off main
t new                                 # the same, but $EDITOR opens for the title and details
t                                     # the board: pick a task, then what to do with it
t show discount                       # one task: where it is, and what you can do next
t log discount -f                     # watch it work
t say discount "also validate it"     # send it back to the implementer
t diff discount                       # read the change
```

Wherever a command takes a TASK, you can give its number (`3`), a word from
its title (`discount`), or nothing, and then you pick from a list. If fzf is
installed, the list is fuzzy-searchable.

### The board

```
$ t ls
ID    PIPE     STEPS   AT            STATE     TITLE
1     shop     ✓✓▶     30-review     running   Add a discount code field to checkout
2     shop     ▶··     10-implement  HOLD      Rename cart to basket everywhere
      ↳ implement ran 3 times without getting past it   (t show 2)
3     shop     ▶··     10-implement  after 1   Show the discount on the receipt
```

In STEPS, ✓ means done, ▶ is where the task is, and · is still to come.
The STATE column shows one of:

- `ready`: the next tick starts it
- `running`
- `after N`: stacked on task N, and waiting for it
- `HOLD`: it needs you
- `done`

### One task

```
$ t show 2
2  Rename cart to basket everywhere

  shop:  ▶ implement  · test  · review
  state:     ON HOLD: implement ran 3 times without getting past it
  repo:      /home/aksel/git/shop
  branch:    t/0002-rename-cart-to-basket-everywhere  (from origin/main)
  worktree:  /home/aksel/.tick/tasks/0002/work
  feedback:  **cart.js:12** — the old name is still exported …

  next:
    t log 2            see why
    t say 2 "..."      tell the implementer what to do; it resumes
    t attach 2         take over the agent yourself, then: t resume 2
```

### A normal coding task, start to finish

1. `t new "…"` in the repo, or `t new -p shop "…"` from anywhere.
2. The tick runs **implement** (the agent edits, and the script commits),
   then **test** (your test command), then **review** (a second agent reads
   the diff).
3. Failing tests and review changes go back to implement on their own, and a
   step gets 3 runs.
4. It ends `done`, or on `HOLD` when it needs you. `t show` tells you what to
   do either way.
5. When it's done, read it with `t diff`. Then take it with `git merge`, or
   with `-p feature`, review the PR it opened.
6. Clean up with `t rm`. The branch stays.

### Questions instead of code

```sh
cd ~/git/shop
t new --now -p ask "How does checkout compute tax?"             # reads the repo, changes nothing
t new --now -p research "What changed in Postgres 18 upgrades?" # searches the web, from anywhere
t say 7 "and where is that tested?"                            # a follow-up
t show 7                                                       # the question, the answer, the history
```

These are ordinary pipelines with one step, `answer`. The step pipes the
question to `agents/answerer.md` and writes `answer.md`, which `t show`
prints. The pipeline's `env` says how: `MODE_answer=web` lets research search
the web, and `CLI_answer=` picks who answers. Leave out `--now`
and the tick answers it in the background instead.

An agent's `mode` decides what it may touch:

| mode | may | used by |
| --- | --- | --- |
| `read` | read the repo | reviewer, answerer in `ask` |
| `web` | read, search the web, fetch pages | answerer in `research` (`MODE_answer=web`) |
| `edit` | read, edit files, run commands | implementer |

A new kind of question is a new agent plus a pipeline. For example, a
security review of a repo:

```sh
printf -- '---\nmode: read\n---\nYou look for security problems in this repo…\n' > agents/auditor.md
mkdir pipelines/audit && ln -s ../../steps/answer pipelines/audit/10-answer
printf 'ANSWERER=auditor\nCLI_answer=claude\n' > pipelines/audit/env
```

## Pipelines

A pipeline is a directory of numbered links to scripts in `steps/`, like
`/etc/rc3.d`.

| pipeline | steps |
| --- | --- |
| `local` (the default) | implement (opencode) → test → review (opencode) |
| `feature` | implement (opencode) → test → review (opencode) → pr → ci |
| `ask` | answer (opencode): reads the repo you're in and changes nothing |
| `research` | answer (claude): searches the web; needs no repo |

You pick one per task with `t new -p feature "…"`.

### Who solves each step

Each agent step's solver is set in its pipeline's `env`, by the step's name:

```sh
# pipelines/feature/env
CLI_implement=opencode
CLI_review=opencode
# MODEL_implement=vllm/qwen3-coder-next  # optional: pin a model for that step
```

Without `MODEL_<step>`, the CLI's own default model runs: for opencode that's
`vllm/laguna-s-2.1` from `~/.config/opencode/opencode.jsonc`, and for claude
whatever `claude` defaults to.

The first one set wins:

1. `t new --cli claude "…"`: every step of that one task.
2. `CLI_<step>=` in the pipeline's `env`: that step, in every task.
3. `T_CLI` in `etc/tick.conf` (opencode): any step the pipeline doesn't name.

A pipeline can review twice with different solvers, because the key is the
link's name, not the script's: add `ln -s ../../steps/review 35-second-review`
and `CLI_second_review=claude`. `t show` and `t doctor` print the solver next
to each step.

### A pipeline for one repo

```
pipelines/shop/
  10-implement -> ../../steps/implement
  20-test      -> ../../steps/test
  30-review    -> ../../steps/review
  env
```

`env` is sourced before every step, and `t new` reads its `REPO`:

```sh
REPO=~/git/shop          # `t new -p shop` works from any directory
TEST_CMD="npm test"      # what the test step runs; without it, `make test` or nothing
TEARDOWN="docker compose down -v"   # after every test run, and before `t rm` deletes the worktree
CLI_implement=opencode   # who solves each agent step: claude or opencode
CLI_review=claude
```

When you stand in `~/git/shop`, a plain `t new` picks this pipeline. To make
one:

```sh
mkdir ~/git/tick/pipelines/shop && cd ~/git/tick/pipelines/shop
for s in 10-implement 20-test 30-review; do ln -s ../../steps/${s#*-} $s; done
printf 'REPO=~/git/shop\nTEST_CMD="npm test"\n' > env
t doctor                 # shows it, and warns if its test step would check nothing
```

### A new step

A step is a plain script. It runs with the task directory as its cwd, and the
worktree is `work/`.

| exit | means | what the runner does |
| --- | --- | --- |
| 0 | finished | go to the next step, or to the step it wrote into `goto` |
| 75 | not yet | run the same step next tick; this run doesn't count |
| other | failed | run it again next tick; after 3 runs, hold the task |

Two examples. The first runs a linter and sends failures back to implement;
the second waits until a person runs `touch ~/.tick/tasks/0007/approved`:

```bash
#!/usr/bin/env bash
# steps/lint — run the linter; failures go back to implement
t=$PWD
cd work || exit 1
out=$(npm run -s lint 2>&1) && exit 0
printf 'The linter fails:\n```\n%s\n```\n' "$(tail -60 <<< "$out")" > "$t/feedback.md"
echo implement > "$t/goto"
```

```bash
#!/usr/bin/env bash
# steps/approve — wait until a person runs: touch ~/.tick/tasks/ID/approved
[ -f approved ] || exit 75
```

Add a step with `chmod +x steps/lint`, then
`ln -s ../../steps/lint pipelines/shop/25-lint`.

## How it works

| idea | here | Linux equivalent |
| --- | --- | --- |
| a task is a directory of small files | `~/.tick/tasks/0007/` | `/proc/PID/` |
| a pipeline is a directory of numbered links | `pipelines/shop/20-test → ../../steps/test` | `/etc/rc3.d` |
| a step reports through its exit code | 0 next, 75 later, other = retry | `sysexits.h` |
| a lock that dies with its process | `flock` on the task's `lock` | no pid files |

- **The scheduler.** Cron runs `t tick` every minute, which starts `t run`
  for each open task. `t run` takes the task's lock and runs steps until one
  says "not yet" or fails. After a reboot, the next tick simply runs the step
  again. `t run 7` is the same thing in your terminal.
- **Feedback.** The review, the tests, CI and `t say` all write
  `feedback.md` and jump back to implement, which adds that file to the
  agent's prompt. Agents remember nothing; the task directory does.
- **Parallel tasks and stacks.** Each `t new` gets its own worktree off the
  trunk, in a directory named `<repo>-<id>` (repos derive ports and container
  names from it; `work` links to it), and those run in parallel. `t new --on 7 "…"` shares task 7's
  worktree and lock, branches from 7's branch, and waits until 7 is done.
- **Agents.** `agents/*.md` are prompts with a `mode` (read, web or edit).
  Which CLI and model solve a step is the pipeline's choice (`CLI_<step>=`). `drivers/claude` and `drivers/opencode` are the only files that
  know CLI flags. `SLOTS_claude` and `SLOTS_opencode` in `etc/tick.conf` cap
  how many agents run at once.

A task directory holds `task.md`, `pipeline`, `step`, `repo`, `base`,
`branch`, `env`, `work/`, `feedback.md`, `review.md`, `hold`, `after`,
`runs/`, `history` and `log/`. `grep . ~/.tick/tasks/0007/*` shows all of it.

## Commands

```
t                          the board (interactive in a terminal)
t new ["what to do" [-]] [-p PIPELINE] [--on TASK] [--cli claude|opencode] [--test CMD] [-r REPO] [--now]
t ls [-a]                  the board as text; -a adds done tasks
t show [TASK]              where it is, and what you can do next
t log [TASK] [-f]          history and latest output
t diff [TASK]              the change so far
t say [TASK] "notes"       back to implement, with your notes
t attach [TASK]            resume the agent's conversation yourself
t run [TASK]               run it now, in this terminal
t hold [TASK] [why]        pause it
t resume [TASK] [STEP]     unpause it, optionally at another step
t path [TASK]              its worktree:  cd "$(t path discount)"
t rm [TASK]                delete the task and its worktree (the branch stays)
t doctor                   what's missing, and the pipelines
t tick                     what cron runs
```

## Not covered yet

- The `pr` and `ci` steps are tested only against a fake `gh`.
- A stack doesn't rebase. If a parent changes after its child started,
  rebase the child yourself.
- claude's `acceptEdits` lets the implementer edit files, but not run every
  command. Set `CLAUDE_EDIT_MODE=bypassPermissions` in `etc/tick.conf` if your
  worktrees are safe to let it loose in.
