# tick

A kanban board for AI coding tasks. The board is plain files, and cron moves
the tasks along. claude or opencode does the coding, and shell scripts do
everything else.

## Setup

1. `ln -s ~/git/tick/bin/t ~/.local/bin/t`
2. `(crontab -l; echo '* * * * * $HOME/git/tick/bin/t tick') | crontab -`
3. `echo 'source ~/git/tick/completions/t.zsh' >> ~/.zshrc` for tab completion
   (it must come after `compinit`).
4. `t doctor`: checks all of the above, and lists your repos and pipelines.

`test/run` runs the test suite. It uses fake CLIs, so it costs no tokens.

## Daily use

```sh
t new -r amino "Add a discount code field"   # in amino, from any directory (TAB completes -r)
t new                                        # in the repo you're in, writing it in $EDITOR
t                                            # the board: pick a task, then what to do with it
t show discount                              # one task: where it is, and what you can do next
t log discount -f                            # watch it work
t say discount "also validate it"            # send it back to the implementer
t diff discount                              # read the change
```

Wherever a command takes a TASK, you can give its number (`3`), a word from
its title (`discount`), or nothing, and then you pick from a list. If fzf is
installed, the list is fuzzy-searchable.

### The board

```
$ t ls
ID   STEPS  STATE      REPO     TITLE
1    ✓✓▶    running    shop     Add a discount code field to checkout
3    ▶··    after 1    shop     └ Show the discount on the receipt
2    ▶··    held       shop     Rename cart to basket everywhere
      ↳ implement ran 3 times without getting past it   (t show 2)
```

In STEPS, ✓ means done, ▶ is where the task is, and · is still to come. A task
stacked on another sits under it (└) until that one is done. The STATE column
shows one of:

- `next tick`: the next tick starts it
- `running`
- `after N`: stacked on task N, and waiting for it
- `held`: it needs you
- `done`, or `answered` for a question

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

1. `t new -r amino "…"` from anywhere, or `t new "…"` inside the repo.
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
t ask --now -r amino "How does checkout compute tax?"          # reads amino, changes nothing
t research --now "What changed in Postgres 18 upgrades?"       # searches the web, from anywhere
t say 7 "and where is that tested?"                            # a follow-up
t show 7                                                       # the question, the answer, the history
```

These are ordinary pipelines with one step, `answer`. The step pipes the
question to `agents/answerer.md` and writes `answer.md`, which `t show`
prints last. In a terminal it pages through `less`, and `glow`, if you have
it, renders the markdown (`GLAMOUR_STYLE=light` for a light terminal). The pipeline's `env` says how: `MODE_answer=web` lets research search
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
| `main` | local's steps in the repo's own checkout: commits land on its branch (tick's default) |
| `ask` | answer (opencode): reads the repo you're in and changes nothing |
| `research` | answer (claude): searches the web; needs no repo |

You pick one per task with `t new -p feature "…"`, and a repo can name its own
default (see Repos).

`main` has no worktree and no branch to merge. Its env says `IN_PLACE=yes`, so
`t new` points `work` at the repo itself, and tasks in one checkout share a lock
and run one at a time. The implementer waits while the checkout has
uncommitted changes, so a commit never takes yours along.

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

## Repos

A repo gets a short name, a default pipeline and settings of its own in
`repos/NAME/env`, so you can start work in it from any directory:

```sh
# repos/amino/env
REPO=~/git/amino-monorepo                  # where it is
PIPELINE=feature                           # its default pipeline
TEST_CMD="$T_ROOT/repos/amino/run-tests"   # what test steps run; without it, `make test` or nothing
TEARDOWN="$T_ROOT/repos/amino/teardown"    # after every test run, and before `t rm` deletes the worktree
```

`repos/amino/` also holds the two scripts it names. A repo's settings apply
under every pipeline you run on it, so `t new -r amino -p local "…"` runs
amino's tests too.

Which repo and which pipeline a task gets (the first one given wins):

| | repo | pipeline |
| --- | --- | --- |
| 1 | `-r NAME`: a name in `repos/`, a directory in `~/git` (`T_REPOS`), or a path | `-p NAME` |
| 2 | the repo you're standing in | the repo's `PIPELINE=` |
| 3 | `T_REPO` in `etc/tick.conf`, for when you're in no repo | `T_PIPELINE` in `etc/tick.conf` (local) |

To add one:

```sh
mkdir ~/git/tick/repos/rigg
printf 'REPO=~/git/rigg\nPIPELINE=local\nTEST_CMD="cargo test"\n' > ~/git/tick/repos/rigg/env
t doctor      # lists it, and warns if its test steps would check nothing
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

## Jobs: cron without a task

A job is a pipe that runs on a schedule and has no steps to move through. A
script fetches and filters the input, and an agent reads only what's left:

```sh
jobs/front-digest            # your Front conversations from the last day, summarized on stdout
jobs/front-digest "3 days"   # after a holiday
```

Conversations where a teammate @mentions you in a comment come first. The job
reads `FRONT_TOKEN=` and `FRONT_EMAIL=` from `~/.config/front/env` (`chmod
600` it), and the `summarizer` agent writes the digest. To get one every
morning:

```sh
(crontab -l; echo '0 7 * * * $HOME/git/tick/jobs/front-digest > $HOME/digest.tmp 2> $HOME/digest.log && mv $HOME/digest.tmp $HOME/digest.md') | crontab -
```

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
  again. `t run 7` is the same thing in your terminal. With cron installed,
  `t new` starts the new task's `t run` itself, so it doesn't wait a minute.
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
t PIPELINE ...             t new ... -p PIPELINE:  t ask --now "How do the tests run?"
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
t rm [-f] [TASK]           delete the task and its worktree (the branch stays); -f stops its run first
t doctor                   what's missing, and the pipelines
t tick                     what cron runs
```

## Not covered yet

- The `pr` and `ci` steps are tested only against a fake `gh`.
- `jobs/front-digest` is tested only against a fake `curl`, whose answers
  follow Front's API docs rather than recorded responses.
- A stack doesn't rebase. If a parent changes after its child started,
  rebase the child yourself.
- claude's `acceptEdits` lets the implementer edit files, but not run every
  command. Set `CLAUDE_EDIT_MODE=bypassPermissions` in `etc/tick.conf` if your
  worktrees are safe to let it loose in.
