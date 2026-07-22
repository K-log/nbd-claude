# CLAUDE.md

Guidance for AI assistants working **on** this repository. This repo is a
Claude Code **plugin** — its "source" is Markdown + JSON that configures
other Claude sessions, not application code. There is no build step, no test
runner, and no runtime dependency to install.

## What this repo is

`orchestrate-suite` — a Claude Code plugin distributed through a
single-plugin marketplace (`nbd-claude`). It ships:

- an **`orchestrate`** task-orchestrator agent that drives a ticket/bug/
  feature from plan to committed code by delegating to seven worker
  subagents,
- a **`hostile-review`** adversarial code-review skill,
- a **`senior-developer-mode`** output style,
- a **`approve-plan-writes`** PreToolUse hook.

The user-facing explanation of behavior lives in `README.md`; keep it as the
authoritative narrative and update it whenever behavior changes.

## Layout

```
.claude-plugin/
  plugin.json          # plugin manifest (name, version, author, keywords)
  marketplace.json     # marketplace manifest listing this one plugin
agents/                # one Markdown file per subagent (frontmatter + body)
  orchestrate.md       # the orchestrator; the other 7 are its workers
  fetch-details.md  research.md  analysis.md  parallelize-task.md
  build.md  review-code.md  check-regressions.md
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

Each `agents/*.md` file is YAML frontmatter followed by the agent's system
prompt. Match the existing files exactly when adding or editing one:

- `name` — must equal the filename stem.
- `description` — block scalar (`>-`), written in third person, states when
  to use the agent and any hard warnings (see `orchestrate.md`'s
  `--agent orchestrate` warning, which is load-bearing).
- **Model policy (design invariant):** the three high-volume read-only
  workers — `fetch-details`, `research`, `parallelize-task` — are pinned to
  `model: haiku`. Everything else (`orchestrate`, `analysis`, `build`,
  `review-code`, `check-regressions`) is `model: inherit`. The rule: **no
  subagent ever runs on a model more expensive than the session model.** Do
  not change a `haiku` worker to `inherit` or introduce a costlier tier
  without preserving this invariant, and update the README's model table if
  you touch it.
- Tool grants — `orchestrate` uses an allowlist `tools:` line (including a
  scoped `Agent(research, analysis, ...)` grant naming exactly the 7
  workers); workers use `disallowedTools:` to remove capabilities. Keep the
  least-privilege pattern each worker already sets:
  - `research`, `fetch-details` deny `Write, Edit, Bash, Agent`.
  - `analysis`, `parallelize-task` deny those **plus** `WebSearch, WebFetch`.
  - `review-code` denies `Write, Edit`; `check-regressions` denies
    `Write, Edit, Agent`.
  - `build` denies only `Agent` (it needs `Bash`/`Write`/`Edit` to
    implement and commit).
- `color` — set per existing convention (cyan = read-only worker, green =
  build, red = review, yellow = regressions, purple = orchestrator).

## The orchestrate agent (the core artifact)

`agents/orchestrate.md` is the largest and most important file. Its design
contracts, any of which is easy to break with a careless edit:

- **Invoke via the Agent tool, never `claude --agent orchestrate`** — the
  latter is confirmed broken (spawns zero subagents). This warning appears
  in the agent `description`, the README, and inline; keep all three in sync.
- **No `AskUserQuestion` tool** — the orchestrator cannot ask interactively
  (Claude Code strips that tool from Agent-tool subagents). It instead stops
  with a `## Decision needed` (or `## Decision needed (multi-select)`) block.
  Do not add interactive-question logic.
- **Phases 0–6** are a fixed pipeline: checkpoint selection → requirements →
  research → analysis → plan synthesis → milestone execution → final review.
  Preserve phase numbering and the delegation-per-phase routing table.
- **Plan file** lives at `docs/plans/<slug>.md` and is the orchestrator's
  only durable state across stop/resume. The template section headings in
  the agent body are a contract with the resume logic — don't rename them.
- **Concurrency cap of 4** subagents at once, and adversarial `review-code`
  runs **once** over the full task diff in Phase 6, not per milestone.
- **Delegation ledger** (`## Delegations` table) must stay in the plan-file
  template and the Phase 6 summary.

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
- **Keep README, agent descriptions, and this file consistent.** The
  `--agent orchestrate` warning and the model-cost invariant are stated in
  multiple places by design; a change to one requires updating the others.

## Git workflow

- Commit messages follow plain, descriptive summaries (see `git log`); no
  `feat:`/`fix:` conventional-commit prefixes are used. PRs reference an
  issue number in the subject where relevant (e.g. `(#3)`).
- Do not create a pull request unless explicitly asked.
