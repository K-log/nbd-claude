# CLAUDE.md

Guidance for AI assistants working **on** this repository. This repo is a
Claude Code **plugin** — its "source" is Markdown + JSON that configures
other Claude sessions, not application code. There is no build step, no test
runner, and no runtime dependency to install.

## What this repo is

`orchestrate-suite` — a Claude Code plugin distributed through a
single-plugin marketplace (`nbd-claude`). It ships:

- a single long-running **`orchestrate`** task-orchestrator agent that
  drives a ticket/bug/feature from plan to committed code entirely by
  itself — research, analysis, implementation, review, and regression
  checks all inline, with no worker subagents and no fan-out,
- a **`hostile-review`** adversarial code-review skill,
- a **`senior-developer-mode`** output style,
- a **`approve-plan-writes`** PreToolUse hook.

The user-facing explanation of behavior lives in `README.md`; keep it as the
authoritative narrative and update it whenever behavior changes.

## Design invariant: one long-running agent, not a fan-out

The load-bearing design choice is that `orchestrate` is a **single agent
that does all the work itself** and runs as long as the task takes. It
must not spawn worker subagents, parallelize across spawns, or otherwise
fan work out — that is precisely the token-churn the redesign removed. When
editing:

- `orchestrate` has **no `Agent` tool** and grants no nested `Agent(...)`
  scope. Do not add one. If a change seems to want delegation, it belongs
  inline in the agent instead.
- Milestones run **sequentially**, one at a time. Do not reintroduce a
  concurrency cap, a delegation ledger, or a `## Delegations` plan-file
  section — those concepts are gone by design.
- The whole task runs on the **session model** (`orchestrate` is
  `model: inherit`); there are no cheaper pinned workers to balance against
  anymore. Keep it `inherit`.

## Layout

```
.claude-plugin/
  plugin.json          # plugin manifest (name, version, author, keywords)
  marketplace.json     # marketplace manifest listing this one plugin
agents/
  orchestrate.md       # the single long-running orchestrator (only agent)
skills/
  hostile-review/SKILL.md
hooks/
  hooks.json           # registers the PreToolUse matcher
  approve-plan-writes.sh
output-styles/
  senior-developer-mode.md
README.md  LICENSE
```

There is no `src/`, no package manager, no CI. Every file is either a
manifest, an agent/skill/style definition, or a hook script.

## Agent file conventions

`agents/orchestrate.md` is YAML frontmatter followed by the agent's system
prompt:

- `name` — must equal the filename stem (`orchestrate`).
- `description` — block scalar (`>-`), third person, states when to use the
  agent. It carries the "single long-running agent, no subagents" framing
  and the "no `AskUserQuestion`" note; keep those accurate if behavior
  changes.
- `tools` — an allowlist giving the agent everything it needs to do the
  work itself: `Read, Write, Edit, Grep, Glob, Bash, WebSearch, WebFetch`
  plus the `TaskCreate/TaskGet/TaskList/TaskUpdate` progress mirror. It
  deliberately has **no `Agent` tool**.
- `skills: hostile-review` — the agent uses the skill for its final review.
- `model: inherit` — always. See the design invariant above.
- `color: purple`.

## The orchestrate agent (the core artifact)

`agents/orchestrate.md` is the largest and most important file. Its design
contracts, any of which is easy to break with a careless edit:

- **Does everything itself in one session** — no worker subagents. See the
  design invariant above; this is the whole point of the plugin.
- **No `AskUserQuestion` tool** — the orchestrator cannot ask
  interactively (Claude Code strips that tool from Agent-tool subagents,
  and the `## Decision needed` block works regardless of how it's invoked).
  It stops with a `## Decision needed` (or `## Decision needed
  (multi-select)`) block. Do not add interactive-question logic.
- **Phases 0–6** are a fixed pipeline: checkpoint selection → requirements
  → research → analysis → plan synthesis → milestone execution → final
  review. Preserve phase numbering and the per-phase structure.
- **Plan file** lives at `docs/plans/<slug>.md` and is the orchestrator's
  only durable state across stop/resume. The template section headings in
  the agent body are a contract with the resume logic — don't rename them.
- The adversarial `hostile-review` pass runs **once** over the full task
  diff in Phase 6, not per milestone.

## Hook

`hooks/hooks.json` registers a single `PreToolUse` matcher on `Write|Edit`
that runs `approve-plan-writes.sh`. The script **only ever auto-approves**
writes to `docs/plans/*.md`; on any error (no `jq`, unparseable payload) it
`exit 0`s and defers to the normal permission prompt — it can remove a
prompt, never block a write. Preserve that fail-open property. The script
uses `set -euo pipefail`; reference the plugin root via
`${CLAUDE_PLUGIN_ROOT}` as `hooks.json` does.

## Editing / validation workflow

There is no compiler or test suite. To validate changes:

```
claude plugin validate .        # validates plugin.json + marketplace.json
```

Load the plugin from a local checkout to try it end to end:

```
claude --plugin-dir .
```

Bump `version` in `.claude-plugin/plugin.json` (semver) when plugin behavior
changes. The `description` strings in `plugin.json` and `marketplace.json`
are kept identical — update both together.

## Conventions

- **Prose style:** files are hard-wrapped near ~76 columns. Match it when
  editing so diffs stay clean.
- **No emojis** anywhere — this is a rule the `senior-developer-mode` style
  itself enforces, and the repo follows it.
- **Keep README, the agent description, and this file consistent.** The
  single-long-running-agent framing is stated in multiple places by design;
  a change to one requires updating the others.

## Git workflow

- Commit messages follow plain, descriptive summaries (see `git log`); no
  `feat:`/`fix:` conventional-commit prefixes are used. PRs reference an
  issue number in the subject where relevant (e.g. `(#3)`).
- Do not create a pull request unless explicitly asked.
