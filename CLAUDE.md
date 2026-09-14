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
| a repo | `repos/NAME/env`: `REPO=` where it is, `PIPELINE=` its default pipeline, and settings its steps read (`TEST_CMD=`, `TEARDOWN=`, `GENERATED=`, `GENERATE=`, `PREVIEW=`) | no |
| a pipeline's settings | `pipelines/NAME/env`; a step sees the pipeline's env, then its repo's, then its task's own. `REPO=none` for a pipeline that needs no repo | no |
| a step | an executable in `steps/` that follows the contract below | no |
| a step you don't always want | `OPTIONAL=plan` in the pipeline's env: it is left out unless `t new` asks for it with `+plan`, which the task keeps in its `opt` file | no |
| an agent | `agents/NAME.md`: a prompt, with `mode: read`, `web` or `edit` in its frontmatter | no |
| a review mindset | `mindsets/NAME.md`: what one review pass looks for. Name it in a pipeline's `MINDSETS=` | no |
| who solves a step | `CLI_<step>=claude` or `opencode`, and optionally `MODEL_<step>=` and `EFFORT_<step>=` (claude's thinking; `T_EFFORT` elsewhere), in the pipeline's env; `t new --cli` overrides it for one task | no |
| a kind of question | a pipeline whose one step is `steps/answer`; its env sets `MODE_answer=` (read or web), `CLI_answer=`, and `ANSWERER=NAME` only for a prompt of its own | no |
| an AI CLI | `drivers/NAME`, same contract as `drivers/claude` | no |
| a mail source | `sources/NAME`, with the verbs of `sources/front`: `poll`, `thread`, `draft`, `send`, `archive`, `sent`, and `can VERB`, which `t inbox` and `t thread` ask before they offer a key (`comment`, `react`, `threads`). A source that can't draft gets `pipelines/SCRIPT-reply` with `DELIVER=send`, as `sources/slack` does | no |
| a Slack workspace | `t slack login NAME`: its token in `~/.config/slack/NAME/env`, the link `sources/NAME` → `slack`, and the pipeline `pipelines/NAME` that watches it | no |
| a Google account | `~/.config/google/NAME/env` (its OAuth client), then `ln -s gmail sources/NAME` for its mail and `ln -s gcal calendars/NAME` for its calendar, and `t google login NAME`. The script knows its account by the name it runs as | no |
| an inbox on the board | a pipeline whose one step is `steps/watch`, with `SOURCE=` and `POLL=` in its env; start it once with `t new -p NAME` | no |
| a calendar on the board | a pipeline whose one step is `steps/agenda`, with `CALENDAR=` in its env | no |
| a roadmap on the board | a pipeline whose one step is `steps/roadmap`, with `ROADMAP=` (a file in `roadmaps/`, with the verbs of `roadmaps/github`: `items`, `start`), `PROJECT=` and `POLL=` in its env | no |
| a command | `bin/t-NAME`. Line 2 is its help line (`# t NAME ARGS — what`) | no |
| a key on the board | a line in `lib/board.sh`: `ACTIONS` for what it does to a task, else `BOARD_KEYS`, `FORM_KEYS`, or a screen's own (`INBOX_KEYS`, `THREAD_KEYS`, `CAL_KEYS`, `ROADMAP_KEYS`, `LATER_KEYS`). `t ui` binds it from there, and screens name it with `key NAME` | no |
| the board's look | `lib/board.sh`: the `C_` greys and red, `T_FZF_COLORS`, and `BOARD_FZF`, which every fzf screen and `t doctor` use | no |
| a setting | `etc/tick.conf`, as `: "${NAME:=default}"` | no |
| a cron job that isn't a task | a pipe script in `jobs/`, plus a crontab line | no |
| a line on the board from a job | write it to `note` in the task directory, and remove it when you're done | no |

`bin/t-run` is the runner, and it should almost never change. If a feature
seems to need a change there, look for a file convention first. `goto`,
`hold` and `after` all started out that way.

## The step contract

A step runs with the task directory as its cwd.

- `exit 0`: finished. The task moves to the next step, or to the step named in `./goto`.
- `exit 75` (EX_TEMPFAIL): not yet. The step runs again next tick, and the run doesn't count.
- any other exit: failed. The step runs again next tick.

A step that runs `MAX_RUNS` times without finishing holds the task. A step that sends the
task back with `goto` `MAX_ROUNDS` times holds it too, and moving on to a later step starts
that count over.

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
- **Steps enter the worktree with `cd -P work`.** `work` links to `<repo>-<id>`,
  and repos derive ports and container names from `basename $PWD`. Through the
  link, every task would be called `work` and share them.
- **CLI flags live only in `drivers/`.** Steps and agents say `mode: edit`, and
  the driver turns that into `--permission-mode` or `--agent plan`.

## Testing

`test/run` runs every test, and `test/run stack` runs only the tests whose
names match. Fake `claude`, `opencode` and `gh` in `test/fake/` go first on
PATH. They follow the real protocols (`test/fixtures/` holds recorded real
output), so tests never call a model. Each test gets its own `T_VAR` and a toy
repo with a bare `origin`.

Assert the rule, not the implementation. Name tests after the behavior, for
example `test_a_stacked_task_waits_then_builds_on_its_parent`. Say keys by name
(`keyfor hold`) and rows by rule (`'^ +1 .* 0/3 +next tick$'`), so a restyle
breaks no test that isn't about the style.

fzf is tested too: one test draws the live board in tmux and reads the screen
back, and `t doctor`, which a test runs, fails on a flag or color fzf doesn't
know.

## Style

- Commit subjects are imperative and say what changed for the reader.
- As few comments as possible. A script's header says what it does. Beyond
  that, comment only a failure the code can't make obvious by itself. A
  clearer name or a test beats a comment.
- Write bash a person can read top to bottom without comments. Names carry
  the meaning: a variable says what it holds (`task`, not `t`; `$C_DIM`, not
  `$d`), and a small function says what a pipeline does (`task_num`,
  `last_words`, `next_choice`).
  - `if cond; then act; fi`, not `[ ! cond ] || act`. Keep `||` for "or
    else stop": `a || die "..."`, `[ -f x ] || continue`.
  - A bash loop over a one-line awk program. awk picks columns
    (`awk '$1 == a { print $2 }'`) or runs a program laid out over lines.
  - Code lives in scripts, not in strings: fzf calls a mode of the script
    (`t-ui --rows`), and what only one command needs moves to `lib/`
    (`lib/new.sh` for `t new`), so each script stays about a screen long.
- Errors name the fix: `task 42 is running; watch it with: t log 42 -f`.
