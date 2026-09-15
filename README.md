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
one is done. A watch that never ends (an inbox, a calendar, a roadmap) stands
at the top, above the work. A narrow terminal drops the repo first, then the status, then the
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
task on it, `^n` starts a new one, and `^x` deletes one at once, worktree
and all (the branch stays). `^g` deletes every
task done, answered or held for 12 hours, once the pane has listed them and you
press Enter. `^o` attaches to its
agent, the one key that leaves the board, for the agent's own screen. Everything
else is a word away: `?` lists every action in the pane, with the agent's
session id, and you type the one you want, or its first letters, and press
Enter. `cancel` stops a running agent now and holds the task, `run` runs it
in the background with the pane following it, and `rm` deletes it like `^x`.
`^x` on a running task stops its agent first. In a prompt that takes words,
esc clears what you typed, and esc again goes back. `^w` widens the pane. Without fzf, `t`
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
it. The list turns into the pipelines, the repo's default first and under the
cursor: search and scroll it as the tasks, and enter on one picks it. Then the
prompt becomes `new>` and takes the title, and the pane shows the task
that is about to exist (`t new --dry`): its repo and where that came from,
branch, base, who solves it, when it starts, and the command to type next
time. `^p` brings the pipelines back, the title waiting for you. Enter creates it and puts the cursor on it, `^o` opens `$EDITOR` for
details with the title already on line 1, `^r` picks another repo, `^s`
another agent for every step (like `--cli`; the keys at the bottom say
which), and esc goes back. `^a`, `^e` and `^u` edit the line as in a shell.
With cron installed the task starts at once; without it, `? run` on its row
runs it. Flags typed with the title work too: `Add proration -r amino`.
`^v` pastes the image on the clipboard, a screenshot say, as `--image FILE`:
it goes into the task's `images/`, and `task.md` lists its path, which claude
and opencode read to see it. Outside the board: `t new --image "$(t paste)" "..."`.

`^t` stacks a task on the one you're on the same way (`stack on 7>`; on an
answered question, `task from 7>` makes a task of it), and
`^y` says something to it (`say to 7>`, and Enter on a held task): what you
type goes to `feedback.md` (a running task is stopped first), `tab` picks the step it restarts at, `^s` who
solves it from then on, and the pane shows what will happen and its latest log.
`^s` on a task's row does that without saying anything (`t agent`): claude,
opencode, then its pipeline's agents again, from its next run on. A step stuck on
opencode moves to claude now with `t agent -f 7 claude`.

Outside the board, `t new` without a title opens the same form as a screen of
its own (`t compose`).

### One task

```
$ t show 2
Rename cart to basket everywhere

state     held  implement ran 3 times without getting past it
pipeline  shop · claude
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
   do either way, and ends with the implementer's summary of what it changed.
5. When it's done, read it with `t diff`. Then take it with `git merge`, or
   with `-p amino-feature`, review the PR it opened.
6. Clean up with `t rm`. The branch stays.

### Questions instead of code

```sh
t ask --now -r amino "How does checkout compute tax?"          # reads amino, changes nothing
t research --now "What changed in Postgres 18 upgrades?"       # searches the web, from anywhere
t say 7 "and where is that tested?"                            # a follow-up
t show 7                                                       # the question, the answer, the history
t new --from 7 "Test the tax rounding"                         # make it a task (t stack 7, ^t on the board)
```

A task made from a question works in its repo, with its repo's pipeline, and
its details are the question, the follow-ups and the answer.

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
| `amino-feature` (the default) | +plan (claude) → implement (claude) → test → review (claude) → sync (claude) → pr → +preview → +ci |
| `mono-feature` | +plan (claude) → implement (claude) → test → review (claude) → sync (claude) → pr → +ci: mono only, from any directory |
| `tick-feature` | implement (claude) → test → review (claude) → merge (claude): tick only, from any directory; lands on its `main` |
| `ask` | answer (claude): reads the repo you're in and changes nothing |
| `research` | answer (claude): searches the web; needs no repo |

You pick one per task with `t new -p amino-feature "…"`, and a repo can name its own
default (see Repos).

A step written `+plan` is optional: the pipeline lists it in `OPTIONAL=` in its
`env` and leaves it out unless the task asks for it with `t amino-feature +plan "…"`
(the same `+plan` works on the board, typed after the title, and `+plan +ci`
asks for both). The task keeps what it asked for in its `opt` file, and every
screen counts only its own steps, so a plain amino-feature task is 0/5 and one with both
is 0/7. A task can take one on later, done or not: `t resume 7 preview` adds
it to `opt` and restarts there, and so does the say form on the board (`^y`),
where `tab` offers the left-out steps as `+preview` and Enter with nothing
typed restarts at the step you picked.

`amino-feature` has three: **plan**, **preview** and **ci**. With **plan**, `agents/planner.md` reads
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

With **preview**, the pushed branch goes online for people to click through.
The step runs the repo's `PREVIEW=` in the worktree, which starts the app and
prints one `NAME URL` line per surface; the links go to the task's `preview`
file and, whenever they change, into a comment on the PR. `t show` and the board's pane
list them under the PR's link, and `t copy` (`alt-c` on the board) puts them all on the
clipboard. The task finishes
with the preview still up, and the repo's `TEARDOWN` takes it down when `t rm`
or `t clean` deletes the task. amino's (`repos/amino/preview`) runs `./dev.sh up`
behind three Cloudflare quick tunnels (app, backoffice, API), builds both
frontends against the API's link, and prints the links only once each answers
through its tunnel and both bundles name that API. Quick tunnels need no
Cloudflare account; the random `trycloudflare.com` links are the only lock, and
they change when a test run's teardown closes the tunnels.

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
`LATE_MINDSETS=` (`amino-feature`: intent and defects) may still send the task back.
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
| `house-rules` | does it keep the rules the repo's CLAUDE.md files and skills wrote down? |
| `data` | what happens at a thousand times the data? |
| `trust` | who could see or do what they shouldn't? |

`amino-feature` names the first five, and `mono-feature` adds `house-rules`. A small local model answers five narrow
questions better than one wide one, and a stacked pull request gets no review
from GitHub's bot at all, so this is the only review it will get. `data` and
`trust` are left to `jobs/idle-review`, which has all the time in the world.

`tick-feature` works in a worktree of its own, like `amino-feature`, but branches from tick's
local `main` (`TRUNK=main` in its env) and ends with `merge`. That step merges
`main` into the task's branch, and the merger agent resolves any conflicts. If
`main` had moved, the task goes through test and review again. Then `main`
fast-forwards to the branch, and your checkout with it. git won't overwrite
your uncommitted work, so while it's in the way, the step waits.

### Who solves each step

Every agent step runs the default CLI; a pipeline's `env` names one for a step
when it should be another:

```sh
# pipelines/amino-feature/env
CLI_plan=claude
MODEL_plan=opus                          # the latest Opus: planning is worth it
EFFORT_plan=max                          # and let it think as hard as it can
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
3. `T_CLI` in `etc/tick.conf` (claude): any step the pipeline doesn't name.

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
PIPELINE=amino-feature                     # its default pipeline
TEST_CMD="$T_ROOT/repos/amino/run-tests"   # what test steps run; without it, `make test` or nothing
GENERATED="*openapi*.json *.gen.ts …"      # what tooling writes: no agent reads or reviews it
GENERATE="$T_ROOT/repos/amino/generate"    # writes it: implement runs this after the agent, before it commits
TEARDOWN="$T_ROOT/repos/amino/teardown"    # after every test run, and before `t rm` deletes the worktree
PREVIEW="$T_ROOT/repos/amino/preview"      # +preview: start the app, print "NAME URL" lines
```

`repos/amino/` also holds the four scripts it names. A repo's settings apply
under every pipeline you run on it, so `t new -r mono -p amino-feature "…"` runs
mono's tests too.

Which repo and which pipeline a task gets (the first one given wins):

| | repo | pipeline |
| --- | --- | --- |
| 1 | `-r NAME`: a name in `repos/`, a directory in `~/git` (`T_REPOS`), or a path | `-p NAME` |
| 2 | the repo you're standing in | the repo's `PIPELINE=` |
| 3 | `T_REPO` in `etc/tick.conf`, for when you're in no repo | `T_PIPELINE` in `etc/tick.conf` (amino-feature) |

To add one, with a pipeline of its own to change its review in:

```sh
mkdir ~/git/tick/repos/rigg && cp -a ~/git/tick/pipelines/amino-feature ~/git/tick/pipelines/rigg
printf 'REPO=~/git/rigg\nPIPELINE=rigg\nTEST_CMD="cargo test"\n' > ~/git/tick/repos/rigg/env
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
reads `FRONT_TOKEN=` and `FRONT_EMAIL=` from `~/.config/front/env`, which `t
front login` writes, and the `summarizer` agent writes the digest. To get one
every morning:

```sh
(crontab -l; echo '0 7 * * * $HOME/git/tick/jobs/front-digest > $HOME/digest.tmp 2> $HOME/digest.log && mv $HOME/digest.tmp $HOME/digest.md') | crontab -
```

## Mail: an inbox on the board, and replies you sign

Front comes into tick the way everything else does, as tasks and files. Mail
arriving is not work: a thousand conversations cost the board one row, and only
you add more. After `t front login` (it says which permissions the token needs,
checks it, and keeps it), start the watch once:

```sh
t new -p front-inbox "front inbox"
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
| enter | `t thread`: the conversation the width of the screen, and you write under it |
| ^x | archives the conversation in Front |
| ^d ^u | scroll the thread half a page, as on the board |
| ? | every key, in the pane; again, the thread |

`t thread` is one screen for reading, writing and signing, and it opens where
the thread ends, with the prompt under the last message. There is no editor: a
line is what you type at the prompt, enter starts the next, and backspace on an
empty one takes the line above back. A paste keeps its lines.

| key | does |
| --- | --- |
| ^y | sends it: it leaves now, the same key that sends on every screen |
| ^t | a comment for your teammates instead (pipeline `comment`), or a reply again; your text comes along |
| ^s | an agent writes it into the prompt, from what you wrote so far (`+draft`) |
| ^e ^x | once held: write on at its end, or delete it |
| ^d ^u | scroll the thread half a page, as on the board |
| esc | back to the inbox; what you wrote holds on the board (a task on pipeline `reply`), and nothing leaves |

A reply is `thread → +draft → sign → send`, and nothing leaves until you sign
it. The task holds at `sign`, in red (`draft ready`, or `write your reply`), and
Enter on it opens it in `t thread` again, where it was. Without fzf, `t sign N`
opens it in `$EDITOR` with the thread under it. `DELIVER=` in
`pipelines/reply/env` says what leaving is:

- `draft`, the default: a private draft on the conversation in Front, to read
  once more and send from there. Signing again edits the same draft.
- `send`: sent as you, and only while the thread is the one you read. If
  someone wrote since, the reply holds again, with the thread as it is now.

Comments are Front's, and stay there: tick never keeps one of its own. In a
thread they hang under the message they follow, indented and dimmer (`└ Ida K`),
and the thread ends by saying who can't see them (`2 comments: only your
teammates see them, not Anna Ø.`), so what a colleague said never reads like
something the customer was told. A draft reads them, does what they say, and
never quotes them. A conversation that is there because a comment mentions
you says `mention` in red, so typing `mention` in `t inbox` lists every one.
Front's search can't find mentions, so tick learns of one from Front's email
about it ("Mentioned by Ida K"): the email is no row, the conversation it links
to is. Keep those emails on in Front's notification settings.
The watch's first poll reads back a day (`SINCE=` in the pipeline's env), and
each later one what changed since: a comment that mentions you tomorrow, on a
thread from last year, brings that whole thread. A
comment is a task of its own (`thread → +draft → sign → post`): it holds as
`comment ready`, naming who won't see it, and is posted only once you sign it.

A draft writes the way you do because of `jobs/mail-corpus`, which keeps the
mail you sent as files in `~/.tick/corpus/` (its first run goes back
`CORPUS_SINCE`, 2 years). A draft gets what you wrote to the same person first,
then to anyone at their domain, then your newest, up to `CORPUS_MAX` bytes:

```sh
(crontab -l; echo '0 3 * * * $HOME/git/tick/jobs/mail-corpus >> $HOME/.tick/corpus.log 2>&1') | crontab -
```

`sources/front` is the only file that knows Front's API. Another source is a
file beside it with the same verbs (`poll`, `thread`, `draft`, `send`,
`archive`, `sent`), a pipeline like `front-inbox` with its own `SOURCE=`, and a
word in `CORPUS_SOURCES`. `can VERB` says which of them it has, and the screens
offer only those keys.

## Slack: the same inbox, and the same thread

Slack comes in the way Front does, through your own user token, so no bot
joins a channel and what you sign is posted as you. Each workspace has a name
of your own, and as many as you like stand side by side. `t slack login NAME`
says which scopes to give the token, checks it and keeps it in
`~/.config/slack/NAME/env`; for a new name it also links `sources/NAME` to
`slack` and makes the pipeline `pipelines/NAME` that watches it. Then start the
watch once:

```sh
t slack login slack-amino
t new -p slack-amino "slack amino"
```

Its row counts what involves you (`5 today · 1 mention`), never the unread.
Enter opens `t inbox` as for mail, in two bands: above a rule, direct messages,
mentions and threads you are in, each with the last thing said; under it,
channels that don't involve you, as a count (`#random  41 unread`). `^x` marks
one read.

Enter on a conversation is `t thread`, with the same keys as mail and three of
Slack's own. The prompt starts under the message that brought you there, as a
reply in its thread; the signature line says who will read it.

| key | does |
| --- | --- |
| ^k ^j | walk the messages: the prompt moves with you, into that message's thread |
| ^g | let go of the message: a message to the whole channel, in red |
| ^r | your one reaction (`SLACK_REACTION=`, `+1`), or off it again; it goes at once, and needs no signature |

There is no comment (`^t`), because Slack has no strand only your team sees.
Slack keeps no draft a token can write, so `pipelines/slack-reply` has
`DELIVER=send`: `^y` posts it. What was said since you wrote it shows above it
behind a red rule, and a reply sent over new messages holds again instead of
going, for you to read them first; `^y` again sends it.

## Google: mail and calendars, one account or many

A Google account is a name, and what it has is a link under that name:
`sources/NAME → gmail` for its mail, `calendars/NAME → gcal` for its calendar,
or both. Each account keeps its login in `~/.config/google/NAME/`, so a second
Workspace is a second name, and it shares nothing with the first, or with Front.

1. `t google login work` (or `t google login work mail calendar` for both).
   The first time, it lists the four pages in Google Cloud where the account
   gets an OAuth client of its own (a *Desktop app*, with the consent screen
   *Internal*, since an *External* app still in testing logs out every 7 days),
   and asks for the client's id and secret.
2. It prints the login link and opens it. Pick the account and allow it. With
   the browser on another machine, the page it lands on won't load: paste its
   address into the terminal instead. It asks only for what you log in for:
   `gmail.modify` for mail, `calendar.events` for a calendar.
3. Once logged in, the account gets its links (`sources/work → gmail`,
   `calendars/work → gcal`) and a pipeline for each (`work-mail`, `work-cal`),
   and it says what to start:

   ```sh
   t new -p work-mail "work mail"
   t new -p work-cal "work cal"
   ```

The mail is a source like Front: its inbox, the replies you sign, `DELIVER=`,
and the corpus (`CORPUS_SOURCES="front work"`) all work the same way.

An inbox full of mail that isn't yours (everything to a shared address) can
be narrowed where Gmail keeps it: `SEARCH=` in its pipeline's env is added to
the search the watch makes, in Gmail's own words, so what doesn't match never
comes onto the list.

```sh
SEARCH='("native app" OR aksel)'
```

The calendar's row says the day (`2 left today · next 13:00 Standup · 1 to
answer`), and Enter on it is `t cal`: the next 7 days (`DAYS=`), with the event
you are on beside them. enter opens it in the browser; ^y accepts, ^t says
maybe, ^x declines. An answer is the one thing there another person sees, so
the key is the signature, and the organizer is told at once.

## GitHub: a roadmap on the board

A GitHub project is a queue: its issues are the work, in the order your team
put them. It comes onto the board as one row, like an inbox, but a roadmap
mostly sits still, so its row doesn't count what is there. It says only what
needs you, and nothing on a quiet day. gh needs the project scope once
(`gh auth refresh -s project`), then:

```sh
t new -p amino-roadmap "roadmap"      # PROJECT=AminoNordics/1 in pipelines/amino-roadmap/env
```

Every `POLL` seconds (900) `steps/roadmap` reads the project into
`~/.tick/roadmap/`, and its log says what moved since the last poll (`#613
Up-next → QA`, `#840 arrived from carl428`). The row says `1 stalled · 1
unplanned`:

- **unplanned**: an open issue with no status, or one in the project's repos
  that isn't on the project at all.
- **stalled**: In progress, and nothing touched it for `STALL` days (3): not
  on GitHub, and not a commit in a task made from it.

Enter on the row is `t roadmap`: the open issues in the project's order, with
what needs you lifted above a line, and the issue you are on beside them. A
parent shows its sub-issues as a fraction (`4/6`), and enter lists them.

| key | does |
| --- | --- |
| enter | its sub-issues, as a list of their own; esc goes back |
| ^t | asks for your note, then opens `t compose` with the issue's title typed, where you pick the pipeline, the agent (^s) and the repo (^r), and ^o shows the details: the issue, its comments and your note. Enter makes the task, and GitHub hears in the background that the issue is In progress, assigned to you; if it can't be told, the roadmap's row says so |
| ^n | asks for a title, and enter puts a new issue on the list at once as `#…`, with no status, in the repo of the issue you are on; in a list of sub-issues, a sub-issue of their parent. GitHub makes it in the background, and the list reloads with its number; if GitHub can't, it leaves the list, and the footer and the roadmap's row say why |
| ^s | the list turns into the project's statuses (the issue's own says `now`), and enter moves it there at once; one off the project is put on it. GitHub hears in the background, and if it can't, the issue moves back |
| ^x | not mine: off the list, and nothing changes on GitHub |
| ? | every key in the pane, and what the red words mean; again: the issue |

The task's details are the issue, its comments and your note, and its first
line (`issue: AminoNordics/amino-monorepo#553`) ties it to the issue: the pull
request says `Closes` it, and the roadmap counts the task's commits as the
issue moving. The repo is the one in `repos/` whose git remote is on GitHub.
Tick sets the status and nothing else, and without a signature, because a
status describes work already done; priority and effort stay the team's.

## Later: your own list

What you have written down and are not doing now goes on a list only you
write. Nothing polls it, so it isn't a watch: it is one row under the tasks,
with no id, that never sorts above them (`later  23 · 4 this week · 2
rotting`; empty, `nothing yet`).

```sh
t later "Bytte regnskapsfører"       # on the list, from anywhere
t later                              # the list; Enter on its row on the board opens it too
```

Each thing is a file in `~/.tick/later/`: its first line says what it is, and
the lines under it are notes and subtasks (`- [ ] teste restore`). There is no
priority and no status, only how long since you touched it. A thing untouched
for `LATER_ROT` days (42) rots, and rotting lifts it above a line, red, since
that is the one thing the list can tell you that you don't already know. A
note `due 30 Sep` counts toward `this week`, and does nothing else.

The query is the add box: type the thing, and if it is there you found it; if
nothing matches, Enter adds it.

| key | does |
| --- | --- |
| enter | its subtasks, where typing adds one the same way, and Enter on a subtask ticks it off (again: on) |
| ^t | a task of it in `t compose`, its title typed and its notes as details; the thing leaves the list. With nothing matching, a task of what you typed |
| ^d | did it: off the list, into `done/` |
| ^x | not doing it: off the list, into `dropped/` |
| ^e | its file in `$EDITOR` |

Half of such a list is nothing tick can do. The pipeline `me` is for that: one
step, `do`, that runs nothing and holds (`needs your hands`) until you resume
it, which is saying you did it: Enter on its row, `^r`, or `t resume`.

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
`branch`, `env`, `work/`, `plan.md`, `summary.md`, `feedback.md`, `review.md`, `passes/`, `hold`, `after`,
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
t sign [TASK]              read a reply in $EDITOR, or type it under the thread, and sign it: then it leaves
t inbox [TASK]             the mail a watch keeps: enter opens the thread to write under it, ? every key
t thread CONV|TASK         a conversation the width of the screen: type a reply or comment under it, ^y sends it
t cal [TASK]               the week a calendar watch keeps: ^y accepts an invite, ^t maybe, ^x declines
t roadmap [TASK]           the project a roadmap watch keeps: enter lists sub-issues, ^t makes a task with your note, ^n an issue
t later ["something"]      your own list: put a line on it, or open it; typing finds, enter adds what isn't there
t google login NAME        log a Google account in, for its linked mail and calendar
t front login              the Front API token: what to choose when you make it, then it is checked and kept
t slack login NAME         a Slack workspace under a name of your own: its token, checked and kept, and its inbox pipeline
t attach [TASK]            resume the agent's conversation yourself
t run [TASK]               run it now, in this terminal
t hold [-f] [TASK] [why]   pause it after the running step; -f cancels that step now, agent and all
t resume [TASK] [STEP]     unpause it, optionally at another step, or at an optional one it left out
t name [TASK] ["name"]     what the board calls it; left out, an agent picks a short one
t agent [-f] [TASK] [CLI]  who solves every step from its next run; left out, the next one; -f switches the running step too
t copy [TASK]              its links on the clipboard: the pull request, and the preview's
t path [TASK]              its worktree:  cd "$(t path discount)"
t rm [-f] [TASK]           delete the task and its worktree (the branch stays); -f stops its run first
t clean [-n] [HOURS]       delete every task done, answered or held for 12 hours (or HOURS); -n lists them
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
