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
t new                                        # in the repo you're in: type the title, see the task it makes
t                                            # the live board: tab shows a task's log, enter what to do
t show discount                              # one task: where it is, and what you can do next
t log discount -f                            # watch it work
t say discount "also validate it"            # send it back to the implementer
t diff discount                              # read the change
t peek discount steps                        # how each step went, and which file each setting comes from
t name discount "Discount field"             # what the board calls it
```

Wherever a command takes a TASK, you can give its number (`3`), a word from
its title (`discount`), or nothing, and then you pick from a list. If fzf is
installed, the list is fuzzy-searchable.

### The board

```
$ t ls
  1  shop    Add a discount code field       3/4    3m  review  read cart.js
  3  shop    └ Show the discount in the ca…  0/4        after 1
  2  shop    Rename cart to basket everywh…  1/3    2h  held  implement ran 3 times without getting past it
```

Each row is a task's id, repo, title, step, age and status. The step is the
one it is on out of its pipeline's steps: 3/4 is at the third of four, 0/4
hasn't begun the first, and a done task has them all. The age is how long it
has been on that step, so a stuck task stands out. Where there is nothing to
say, a column is blank. A task stacked on another sits under it (└) until that
one is done. A narrow terminal drops the repo first, then the status, then the
age, never the step. The status says what the task is doing:

- `review  read cart.js`: running, and this is the latest line its step printed
- `next tick`: the next tick starts it; after a run that failed or has to
  wait, followed by that run's last line (`next tick  ci: build pending`)
- `after N`: stacked on task N, and waiting for it
- `held  why`: it needs you
- `done`, or `answered` for a question

A title longer than 40 characters doesn't fit, so `t new` has an agent
(`agents/namer.md`) name the task in a few words, and the board shows that
name instead. `t name 3 "…"` changes it, and `t show` still prints the whole
title.

In a terminal, plain `t` shows this board live, in fzf: in greys, with red
only for a held task, the one thing on it that needs you. Rows move as tasks
run, the cursor starts on the newest running one, and the pane beside it shows
the task you're on: its live log while it runs, else its details (`t peek`).
`tab` switches the pane between details, steps, log and diff (its top line
lists them, the one you're on bright), and `^d`/`^u` scroll it half a page
(PgDn/PgUp a page, Shift-↓/↑ a line). The line at the bottom holds only the
keys worth pressing now (`t keys`), and Enter does the first of them: the log
of a running task, say for a held one, the diff of a done one: the files it
changed, with the diff of each beside them, and Enter again for all of one. The
diff tab lists the files too, and names what tooling wrote (`GENERATED=`)
without its diff.

The keys are all ctrl-, so typing still searches, and they reach the board
over ssh from any terminal. `^l` turns the pane to the log (again: the raw
log), `^r` holds the task (the prompt asks why) or resumes it, `^t` stacks a
task on it, `^n` starts a new one, and `^x` deletes one. `^o` attaches to its
agent, the one key that leaves the board, for the agent's own screen. Everything
else is a word away: `?` lists every action in the pane, with the agent's
session id, and you type the one you want, or its first letters, and press
Enter. `cancel` stops a running agent now and holds the task, `run` runs it
in the background with the pane following it, and `rm` deletes it once the
pane has said what that removes and you press Enter again. `^x` on a running
task stops its agent first. `^w` widens the pane. Without fzf, `t`
prints `t ls`.

`t log` tells a task's story in one text column, with the time in the gutter:
each run opens with a banner saying which step it came from and its number
(`test → review  …  run 1`), the agent's markdown is rendered rather than
printed, and long lines fold on words. Three or more calls of one tool in a
row fold into one line (`read   ×8  src/lib/health-*, src/app.ts`); while the
task runs, its last three calls stay lines of their own. `--raw` is the file
itself, every byte, and the session line `t attach` resumes. `-f` follows it
into the steps still to come. The drivers log paths relative to where the agent works,
so the log says `src/app.ts`. The board's status column keeps a column's worth
of that line: a path by its basename (`notify.ts`), and so a command by its
verb and the file it names, never the shell around it — `bash cd "$(git
rev-parse --show-toplevel)" && ./ci.sh 2>&1` is `bash ci.sh`.

### Starting a task

On the board, `^n` (or Enter on an empty board) starts one without leaving
it: the prompt becomes `new>` and takes the title, and the pane shows the task
that is about to exist (`t new --dry`): its repo and where that came from,
branch, base, who solves it, when it starts, and the command to type next
time. `^p` turns the list into the pipelines, the repo's default first and
under the cursor: search and scroll it as the tasks, and enter on one picks
it. Enter creates it and puts the cursor on it, `^o` opens `$EDITOR` for
details with the title already on line 1, `^r` picks another repo, `^s`
another agent for every step (like `--cli`; the keys at the bottom say
which), and esc goes back. `^a`, `^e` and `^u` edit the line as in a shell.
With cron installed the task starts at once; without it, `? run` on its row
runs it. Flags typed with the title work too: `Add proration -r amino`.

`^t` stacks a task on the one you're on the same way (`stack on 7>`), and
`? say` says something to it (`say to 7>`, and Enter on a held task): what you
type goes to `feedback.md`, `tab` picks the step it restarts at, `^s` who
solves it from then on, and the pane shows what will happen and its latest log.
`^s` on a task's row does that without saying anything (`t agent`): claude,
opencode, then its pipeline's agents again, from its next run on.

Outside the board, `t new` without a title opens the same form as a screen of
its own (`t compose`).

### One task

```
$ t show 2
Rename cart to basket everywhere

state     held  implement ran 3 times without getting past it
pipeline  shop · opencode
          1 implement  2 test  3 review
repo      ~/git/shop
branch    t/0002-rename-cart-to-basket-everywhere
worktree  ~/.tick/tasks/0002/work
feedback  **cart.js:12** — the old name is still exported …

history
  14:02  implement  →  test
  14:03  test       →  implement   looped back
  14:20  held       implement ran 3 times

next
  t log 2            see why
  t say 2 "..."      tell it what to do; it starts over from its first step
  t attach 2         take over the agent yourself, then: t resume 2
```

### A normal coding task, start to finish

1. `t new -r amino "…"` from anywhere, or `t new "…"` inside the repo.
2. The tick runs **implement** (the agent edits, and the script commits),
   then **test** (your test command), then **review** (a second agent reads
   the diff).
3. Failing tests and review changes go back to implement on their own, and a
   step gets 3 runs.
4. It ends `done`, or `held` when it needs you. `t show` tells you what to
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
| `edit` | read, edit files, run commands | implementer, merger |

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
| `feature` | +plan (claude) → implement (opencode) → test → review (opencode) → sync → pr → +ci |
| `main` | local's steps, then merge (opencode): tick only, from any directory; lands on its `main` |
| `ask` | answer (opencode): reads the repo you're in and changes nothing |
| `research` | answer (claude): searches the web; needs no repo |

You pick one per task with `t new -p feature "…"`, and a repo can name its own
default (see Repos).

A step written `+plan` is optional: the pipeline lists it in `OPTIONAL=` in its
`env` and leaves it out unless the task asks for it with `t feature +plan "…"`
(the same `+plan` works on the board, typed after the title, and `+plan +ci`
asks for both). The task keeps what it asked for in its `opt` file, and every
screen counts only its own steps, so a plain feature is 0/5 and one with both
is 0/7.

`feature` has two: **plan** and **ci**. With **plan**, `agents/planner.md` reads
the task and the repo and decides how many pull requests it needs. One is the
default, and the answer nearly always. Only a change too big to review well, with seams that let
each part merge on its own, becomes a stack of up to four: the task becomes
part 1, and each later part is a task stacked on the one before it (`t new
--on`), so its PR's base is the branch below. The parts run one after another,
each once the one below is done, and none of them is planned again.
`plan.md` keeps what the planner said.

**sync**, before `pr`, merges what the branch started from back into it: for a
stacked task that is the task below, which keeps working after its child
branched off, and otherwise the trunk. The merger agent resolves conflicts, and
anything that came in sends the task back to test, so what the PR holds is what
was tested and reviewed. Nothing new in the base and the step says so and moves
on.

With **ci**, the task doesn't end at the open pull request: it waits for the
PR's checks (`exit 75` while they are pending), and a failing one becomes
`feedback.md` and sends the task back to implement, which pushes again. Without
it the pull request is yours to watch.

### Mindsets: reviewing once per thing

A mindset is a file in `mindsets/` — eight to fifteen lines saying what one
review pass looks for, what it leaves to another pass, and what counts as
evidence. It is not an agent: `agents/reviewer.md` stays the reviewer and keeps
the one `VERDICT: approve | changes` contract. Same reviewer, different mindset.

`MINDSETS=` in a pipeline's `env` names them, and the review step reads the same
diff once per name. The task moves on only when every pass approves; the passes
that ask for changes are what `feedback.md` holds, so the implementer is not
handed four approvals to read. Unset, the step reads once, for everything.

A reviewer remembers nothing, so each round it would read the whole diff afresh
and find something new. `passes/` keeps each pass's last answer until the task
moves past review instead: a pass that approved doesn't read again, and one that
asked for changes reads its own answer back, and may ask again only for what is
still not done or for a bug the fix added. From the third round on, only
`LATE_MINDSETS=` (`feature`: intent and defects) may still send the task back.
A round that sends the task back is not a failed run: the task holds only once
review has sent it back `MAX_ROUNDS` times (5), with the last feedback waiting
for implement when you `t resume` it.
While it reads, the board says which pass it is on and of how many
(`review  tests 2/3  Read client.ts`).

| mindset | what it asks |
| --- | --- |
| `intent` | does this do what the task asked, all of it, and only it? |
| `defects` | what input breaks the new code? |
| `blast-radius` | what outside this diff does it break? |
| `tests` | would the test fail if the code were wrong? |
| `craft` | is it the simplest thing that works, and does it look like this repo? |
| `data` | what happens at a thousand times the data? |
| `trust` | who could see or do what they shouldn't? |

`feature` names the first five. A small local model answers five narrow
questions better than one wide one, and a stacked pull request gets no review
from GitHub's bot at all, so this is the only review it will get. `data` and
`trust` are left to `jobs/idle-review`, which has all the time in the world.

`main` works in a worktree of its own, like `local`, but branches from tick's
local `main` (`TRUNK=main` in its env) and ends with `merge`. That step merges
`main` into the task's branch, and the merger agent resolves any conflicts. If
`main` had moved, the task goes through test and review again. Then `main`
fast-forwards to the branch, and your checkout with it. git won't overwrite
your uncommitted work, so while it's in the way, the step waits.

### Who solves each step

Each agent step's solver is set in its pipeline's `env`, by the step's name:

```sh
# pipelines/feature/env
CLI_plan=claude
MODEL_plan=opus                          # the latest Opus: planning is worth it
EFFORT_plan=max                          # and let it think as hard as it can
CLI_implement=opencode
CLI_review=opencode
# MODEL_implement=vllm/qwen3-coder-next  # optional: pin a model for that step
```

Without `MODEL_<step>`, the CLI's own default model runs: for opencode that's
`vllm/laguna-s-2.1` from `~/.config/opencode/opencode.jsonc`, and for claude
whatever `claude` defaults to.

Two things keep a big change inside a local model's context. A repo's
`GENERATED=` globs — openapi specs, `.gen.ts` clients, drizzle's `meta/` — never
reach an agent at all: they leave the review's diff, and every prompt says which
files those are and that nobody edits them by hand (drizzle's `*.sql` migrations
are the schema change itself, so they stay in). What is left goes whole file by
whole file, smallest first, until `DIFF_MAX` bytes (200 kB in `etc/tick.conf`)
are spent; the files that don't fit are named, and the reviewer reads those in
the worktree itself.

`EFFORT_<step>` is how hard claude thinks (`low`, `medium`, `high`, `xhigh`,
`max`); a step that names none gets `T_EFFORT` from `etc/tick.conf`, which is
`high`. opencode has no such dial and ignores it.

The first one set wins:

1. `t new --cli claude "…"`, or later `t agent 7 claude`: every step of that one task.
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
GENERATED="*openapi*.json *.gen.ts …"      # what tooling writes: no agent reads or reviews it
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
`ln -s ../../steps/lint pipelines/shop/25-lint`. Add `OPTIONAL=lint` to
`pipelines/shop/env` and it runs only for a task started with `+lint`.

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

## Slack: the board on your phone

Two more jobs put the board in a Slack channel and let you answer it from
there. They are the only part of tick that talks to anything outside your
machine, and nothing else in tick reads a line they write: `rm jobs/slack*`,
drop the crontab line, and tick is exactly as it was.

A channel is bound to a repo — and a task you start in a channel stays in it
whether or not it has one, so a question (`research …`, which sets `REPO=none`)
is answered where you asked it. Write `~/.config/slack/env` (`chmod 600` it):

```sh
SLACK_TOKEN=xoxb-…               # chat:write, reactions:write, and channels:history
                                 # — groups:history for a private channel
SLACK_CHANNELS="C0AMINO=amino"   # CHANNEL=repo, one pair per repo you want on Slack
SLACK_ME=U0AKSEL                 # who a held task mentions
```

```sh
(crontab -l; echo '* * * * * $HOME/git/tick/jobs/slack-loop >> $HOME/.tick/slack.log 2>&1') | crontab -
```

`slack-loop` runs `slack-in` and `slack-out` every 10 seconds, so a message is
answered in about that. It locks itself, and what fails lands in `~/.tick/slack.log`.

From then on the channel holds one short line per task, posted once and edited
in place — an edit is silent, so four agents work without touching your phone:

```
10  Backend: Health Connect source + ingest  ·  4/6 held
```

It says where the task stands, not what its agent is doing this second: a
pushed message is read minutes later, and that line is stale by then.

The details go into one reply under it, edited the same way: how long it has
been at it, why it is held, and what it did, so the whole run is where you look
instead of a reply per tick. Steps that follow
each other join up (`implement → test → review`), and a loop it went round more
than once says so (`↺ ×3`) — churn is the thing you want to see, and a line
each hides it. Only a hold or an answer mentions you, because an edit is silent
and a mention is not, and both are tick waiting on you. A question's answer
lands in that thread as itself, not as the news that there is one. `t rm` takes
the message with the task, so the channel holds what the board holds.

Say `status` and every open task's line is posted again at the bottom, where
you are already looking, with its details under it; the old line goes. A reply
under a line goes to that task.

| you do | it runs |
| --- | --- |
| type in the channel | `t new -r REPO` there, first line the title and the rest details |
| open with a pipeline's name | that pipeline (`ask where is the total rounded?`), and `+plan` after it |
| say `status` | posts each open task's line again at the bottom of the channel |
| say `help` | what you can type in the channel and in a thread, with examples |
| start with `t ` | that one command on the task it names (`t show 9`, `t rm 12`) |
| reply in a task's thread | `t say` to that task |
| reply starting with `t ` | the same command, on the task you are under (`t log`, `t stack …`) |

Your own message wears the answer: **👀** means tick has it, **✅** means the
task it started is done. No 👀 yet means the task was busy — `t say` waits for
a step to end, so it lands on a later tick, and the missing reaction says so
without a word. 👀 is also the only thing the job remembers, so nothing it has
already taken can run twice.

## Mail: an inbox on the board, and replies you sign

Front comes into tick the way everything else does, as tasks and files. Mail
arriving is not work: a thousand conversations cost the board one row, and only
you add more. With `~/.config/front/env` written (the digest's), start the watch
once:

```sh
t new -p front "front inbox"
```

It is a task that never ends. Its one step, `watch`, asks Front what changed
every `POLL` seconds (300), keeps each conversation in `~/.tick/mail/front/`,
has an agent write it a one-line gist, and puts how many had something today on
its row. Between polls it exits 75, so a tick costs nothing, and a poll that
fails holds it in red like any other step.

Enter on its row is `t inbox`: the conversations, newest first, with the thread
beside the one you are on.

| key | does |
| --- | --- |
| enter | an agent drafts a reply: a task on pipeline `reply`, with `+draft` |
| ^o | a reply you write: the thread is read, and `$EDITOR` opens on it |
| ^x | archives the conversation in Front |

A reply is `thread → +draft → sign → send`, and nothing leaves until you sign
it. The task holds at `sign`, in red (`draft ready`, or `write your reply`), and
Enter on it, or `t sign N`, opens the reply in `$EDITOR` with the thread under
it. What you save is what leaves. `t say N "shorter" draft` has the agent write
it again. `DELIVER=` in `pipelines/reply/env` says what leaving is:

- `draft`, the default: a private draft on the conversation in Front, to read
  once more and send from there. Signing again edits the same draft.
- `send`: sent as you, and only while the thread is the one you read. If
  someone wrote since, the reply holds again, with the thread as it is now.

A draft writes the way you do because of `jobs/mail-corpus`, which keeps the
mail you sent as files in `~/.tick/corpus/` (its first run goes back
`CORPUS_SINCE`, 2 years). A draft gets what you wrote to the same person first,
then to anyone at their domain, then your newest, up to `CORPUS_MAX` bytes:

```sh
(crontab -l; echo '0 3 * * * $HOME/git/tick/jobs/mail-corpus >> $HOME/.tick/corpus.log 2>&1') | crontab -
```

`sources/front` is the only file that knows Front's API. Another source, Gmail
or Slack's DMs, is a file beside it with the same verbs (`poll`, `thread`,
`draft`, `send`, `archive`, `sent`), a pipeline like `front` with its own
`SOURCE=`, and a word in `CORPUS_SOURCES`.

## Google: mail and calendars, one account or many

A Google account is a name, and what it has is a link under that name:
`sources/NAME → gmail` for its mail, `calendars/NAME → gcal` for its calendar,
or both. Each account keeps its login in `~/.config/google/NAME/`, so a second
Workspace is a second name, and it shares nothing with the first, or with Front.

1. In the account's Google Cloud console, turn on the Gmail and Calendar APIs
   and make an OAuth client of type *Desktop app*. In a Workspace, make the
   consent screen *Internal*: an *External* app still in testing loses its
   login every 7 days.
2. Write the client's id and secret, and link what the account has:

   ```sh
   mkdir -p ~/.config/google/work
   printf 'GOOGLE_CLIENT_ID=…\nGOOGLE_CLIENT_SECRET=…\n' > ~/.config/google/work/env
   chmod 600 ~/.config/google/work/env
   ln -s gmail ~/git/tick/sources/work
   ln -s gcal ~/git/tick/calendars/work
   ```

3. `t google login work` opens Google's consent page and keeps the refresh
   token. It asks only for what the links need: `gmail.modify` for mail,
   `calendar.events` for a calendar.
4. Put it on the board, a pipeline for each:

   ```sh
   cd ~/git/tick/pipelines
   mkdir work-mail work-cal
   ln -s ../../steps/watch work-mail/10-watch && printf 'REPO=none\nSOURCE=work\n' > work-mail/env
   ln -s ../../steps/agenda work-cal/10-agenda && printf 'REPO=none\nCALENDAR=work\n' > work-cal/env
   t new -p work-mail "work inbox"
   t new -p work-cal "work calendar"
   ```

The mail is a source like Front: its inbox, the replies you sign, `DELIVER=`,
and the corpus (`CORPUS_SOURCES="front work"`) all work the same way.

The calendar's row says the day (`2 left today · next 13:00 Standup · 1 to
answer`), and Enter on it is `t cal`: the next 7 days (`DAYS=`), with the event
you are on beside them. enter opens it in the browser; ^y accepts, ^t says
maybe, ^x declines. An answer is the one thing there another person sees, so
the key is the signature, and the organizer is told at once.

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
  names from it; `work` links to it), and those run in parallel. `t new --on 7 "…"`
  branches from task 7's branch into a worktree of its own and waits until 7 is
  done; the two never share a lock, so you can still say to 7 while its child runs.
- **Agents.** `agents/*.md` are prompts with a `mode` (read, web or edit).
  Which CLI and model solve a step is the pipeline's choice (`CLI_<step>=`). `drivers/claude` and `drivers/opencode` are the only files that
  know CLI flags. `SLOTS_claude` and `SLOTS_opencode` in `etc/tick.conf` cap
  how many agents run at once. When a CLI fails — a local model out of
  context, a server that went away — the same prompt goes to claude once, so
  a task never stops on one model's bad day.

A task directory holds `task.md`, `name`, `pipeline`, `step`, `opt`, `repo`, `base`,
`branch`, `env`, `work/`, `plan.md`, `feedback.md`, `review.md`, `passes/`, `hold`, `after`,
`runs/`, `history` and `log/`. `grep . ~/.tick/tasks/0007/*` shows all of it.

## Commands

```
t                          the live board in a terminal (fzf), else t ls
t ui [TASK [ACTION]]       with a TASK, the menu of what to do with it; with an ACTION, that at once
t peek [TASK] [show|steps|log|raw|diff]   what the board's pane shows for it
t keys [TASK]              the keys the board's bottom line offers for it
t new ["what to do" [-]] [-p PIPELINE] [--on TASK] [--cli claude|opencode] [--test CMD] [-r REPO] [--now] [--edit] [--dry]
t compose [t new's flags]  the screen plain t new opens: title, pipeline, and the task it will make
t PIPELINE ...             t new ... -p PIPELINE:  t ask --now "How do the tests run?"
t ls [-a]                  the board as text; -a adds done tasks
t show [TASK]              where it is, and what you can do next
t log [TASK] [-f] [--raw]  every run in order, rendered in one column; -f follows it, --raw is the file itself
t diff [TASK]              the files it changed, with the diff of each beside them
t say [TASK] "notes"       back to implement, with your notes
t sign [TASK]              read a reply in $EDITOR and sign it: then it leaves
t inbox [TASK]             the mail a watch keeps: enter drafts a reply, ^o you write one, ^x archives
t cal [TASK]               the week a calendar watch keeps: ^y accepts an invite, ^t maybe, ^x declines
t google login NAME        log a Google account in, for its linked mail and calendar
t attach [TASK]            resume the agent's conversation yourself
t run [TASK]               run it now, in this terminal
t hold [-f] [TASK] [why]   pause it after the running step; -f cancels that step now, agent and all
t resume [TASK] [STEP]     unpause it, optionally at another step
t name [TASK] ["name"]     what the board calls it; left out, an agent picks a short one
t agent [TASK] [CLI]       who solves every step from its next run; left out, the next one
t path [TASK]              its worktree:  cd "$(t path discount)"
t rm [-f] [TASK]           delete the task and its worktree (the branch stays); -f stops its run first
t doctor                   what's missing, and the pipelines
t tick                     what cron runs
```

## Idle time: reading finished work again

The models that review a task are local and free, and the GPU is idle most of
the day. `jobs/idle-review` spends that: while nothing else is running, it reads
one finished task's diff once more, with a mindset that task's pipeline never
runs — `data` and `trust`, before anything is read twice.

```sh
(crontab -l; echo '*/10 * * * * $HOME/git/tick/jobs/idle-review >> $HOME/.tick/idle.log 2>&1') | crontab -
```

It also stays away while the GPU is yours: `GPU_BUSY` in `etc/tick.conf` is a
command, and while it succeeds the job reads nothing. It defaults to `pgrep -x
reaper`, the process Steam launches every game through — a process name, not a
pattern, because `pgrep -f` would match the shell doing the asking. Anything
that exits 0 works: add `|| pgrep -x wineserver`, or ask `nvidia-smi` how busy
the card is.

One pass per run, so the interval is the whole budget. A pass that says
`VERDICT: changes` is said to the task (`t say`, restarting at implement) with a
`## idle review: <mindset>` header, and the ordinary pipeline fixes it, tests
it, reviews it with the standing five and pushes to the pull request. A task is
asked for at most `IDLE_FIXES` findings, ever.

A mindset reads one commit `IDLE_PASSES` times, and a fix moves the commit,
which opens every mindset again — so the loop goes quiet exactly when every
mindset has approved the code as it stands. It leaves alone anything it cannot
help: work that already landed, a task another is stacked on, a held task, a
question with no worktree, and a pull request that is closed.

While a pass is running, the task's row on the board says so — `idle review
data` where it would say `done` — because the job writes what it is doing into
the task's `note` and removes it when it is finished. Any job can do that; the
board shows a `note` while it is there.

Its whole memory is `idle/<mindset>` in each task directory, holding the commit
it read and how often. `rm ~/.tick/tasks/*/idle/craft` makes every task get
another reading from that mindset — which is what to do after editing one. Drop
the crontab line and `rm -r ~/.tick/tasks/*/idle`, and tick is exactly as it was.

## Not covered yet

- The `pr` and `ci` steps are tested only against a fake `gh`.
- `jobs/front-digest` and `sources/front` are tested only against a fake
  `curl`, whose answers follow Front's API docs rather than recorded
  responses: drafting, sending and archiving have not met the real Front yet.
- So are `sources/gmail`, `calendars/gcal` and `t google login`, against a
  fake `curl` and `nc` shaped by Google's API docs.
- A stack merges, and doesn't rebase: the `sync` step brings the task below
  into the branch as a merge commit, so a stacked PR shows that merge.
