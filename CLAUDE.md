# Working on tick

tick moves AI coding tasks through pipelines of shell scripts. A task is a
directory, a pipeline is a directory of numbered scripts, and cron's tick moves
tasks from one script to the next. README.md says how it works; this file says
how to change it.

## Principles

1. **Linux-inspired.** Files are the state, directories are the config, exit
   codes are the protocol, cron is the scheduler, `flock` is the mutex, `mv` is
   the atomic write. If a standard tool already does something, use that tool.

2. **Keep it simple.** bash, coreutils, git, jq, flock. No daemon, no database,
   no config language. Every script fits on a screen, and its first comment
   lines say what it does.

3. **Occam's razor.** Of two designs that work, pick the one with fewer parts.
   Don't add a file, flag, setting or state until something actually needs it.
   Removing things counts as progress.

4. **Predictable shell scripts drive AI, not the other way around.** Scripts do
   everything that can be predicted, and the AI gets only the part that needs
   judgment, as a pipe. An email summary cron job looks like this:

       fetch-mail | only-what-i-want | agent summarize > digest.md

   First a script fetches the emails. Then another one filters out what we
   don't want to see. Only then does the AI read the rest and summarize it.
   The AI never gets our scripts as tools, and it never decides what runs next.

5. **Prefer bash and pipes over AI, because they are easier to test.** You can
   run a script by hand on a fixture and assert on the result. You can't do
   that with an agent. If a step can be a script, it is a script: committing,
   pushing, running tests and polling CI are all scripts.

6. **Agents are filters.** `agent NAME` reads a prompt on stdin and writes the
   answer on stdout. Give an agent tools only when it has to decide what to
   look at next, which means coding inside a worktree.

7. **Agents remember nothing; the task directory does.** Steps talk to each
   other through files (`feedback.md`, `review.md`, `goto`), never through an
   agent's conversation.

## Adding things

| to add | do this | touch the runner? |
| --- | --- | --- |
| a pipeline | `mkdir pipelines/NAME`, then `ln -s ../../steps/X NN-X` for each step | no |
| a pipeline for one repo | `pipelines/NAME/env` with `REPO=` and settings like `TEST_CMD=` (sourced before each step); `REPO=none` needs no repo | no |
| a step | an executable in `steps/` that follows the contract below | no |
| an agent | `agents/NAME.md`: frontmatter (`cli`, `mode`: read, web or edit, `model`) and a prompt | no |
| a kind of question | an agent, plus a pipeline whose one step is `steps/answer` and whose env says `ANSWERER=NAME` | no |
| an AI CLI | `drivers/NAME`, same contract as `drivers/claude` | no |
| a command | `bin/t-NAME`. Line 2 is its help line (`# t NAME ARGS — what`) | no |
| a setting | `etc/tick.conf`, as `: "${NAME:=default}"` | no |
| a cron job that isn't a task | a pipe script in `jobs/`, plus a crontab line | no |

`bin/t-run` is the runner, and it should almost never change. If a feature
seems to need a change there, look for a file convention first. `goto`,
`hold` and `after` all started out that way.

## The step contract

A step runs with the task directory as its cwd.

- `exit 0`: finished. The task moves to the next step, or to the step named in `./goto`.
- `exit 75` (EX_TEMPFAIL): not yet. The step runs again next tick, and the run doesn't count.
- any other exit: failed. The step runs again next tick. After `MAX_RUNS` runs of the same step, the task holds.

Before exiting, a step may write:

- `goto`: the name of the step to go to next. The number is optional, so `implement` works.
- `feedback.md`: what the implementer must fix. The implement step reads it and archives it.
- `hold`: a reason for pausing. The tick skips the task until `t resume`.

## Rules that aren't negotiable

- **An editing agent needs a permission mode, or it edits nothing.** `claude -p`
  without one describes the change, writes nothing, and exits 0. That is why
  `implement` fails when HEAD didn't move.
- **A step that did nothing must fail, not pass quietly.** Silence isn't success.
- **Write state with `> f.tmp && mv f.tmp f`** so that a reader never sees half
  a file.
- **Never run agent output.** Parse it with `grep` for one fixed line (`VERDICT:
  approve`) and treat everything else as text.
- **Worktrees live under `~/.tick`, never inside this repo.** An agent reads
  every CLAUDE.md above its cwd, and this one would confuse it.
- **CLI flags live only in `drivers/`.** Steps and agents say `mode: edit`, and
  the driver turns that into `--permission-mode` or `--agent plan`.

## Testing

`test/run` runs every test, and `test/run stack` runs only the tests whose
names match. Fake `claude`, `opencode` and `gh` in `test/fake/` go first on
PATH. They follow the real protocols (`test/fixtures/` holds recorded real
output), so tests never call a model. Each test gets its own `T_VAR` and a toy
repo with a bare `origin`.

Assert the rule, not the implementation. Name tests after the behavior, for
example `test_a_stacked_task_waits_then_builds_on_its_parent`.

## Style

- Commit subjects are imperative and say what changed for the reader.
- As few comments as possible. A script's header says what it does. Beyond
  that, comment only a failure the code can't make obvious by itself. A
  clearer name or a test beats a comment.
- Errors name the fix: `task 42 is running; watch it with: t log 42 -f`.
