# orchestrate-suite

A Claude Code plugin providing a single long-running task-orchestrator
agent that plans, researches, implements, reviews, and commits a ticket,
bug, or feature end to end in one continuous session, plus a hostile-review
skill and a senior-developer-mode output style.

## Design: one long-running agent, not a fan-out

`orchestrate` does the whole job itself — research, codebase analysis,
implementation, in-process review, regression checks, and commits — in a
single agent that runs as long as the task needs. It deliberately does
**not** spin up worker subagents or parallelize work across many
short-lived spawns.

The reason is cost and predictability. A hundred short subagents, each
re-reading the same files and re-deriving the same context from a cold
start, burn tokens on churn. One agent that keeps its context and works
straight through spends its tokens on the task. Running for an hour — or
three — is fine; the plan file is its durable memory, so it doesn't
re-research what it already knows across a stop and resume.

There is one deliberate exception. The **final adversarial review** runs
`hostile-review`'s two-pass methodology once over the whole task diff at
the very end: the agent hunts for bugs itself, then fans out a fresh,
independent verification subagent per finding (capped at four at a time) to
re-check each one cold. A reviewer with no memory of writing the code is
the strongest guard against both false positives and self-marking, so that
one pass is worth the spawns. Every other review — the per-milestone
self-review and regression check during the build loop — stays
single-agent.

Apart from that final verification, there is no concurrency to manage, no
fan-out cap to reason about, and no delegation ledger to reconcile.
Milestones run in order, one at a time.

## Components

### Agent

- **`orchestrate`** (inherits your session model) — the task orchestrator.
  Gathers requirements, optionally fetches ticket/PR context, researches
  dependencies, analyzes codebase patterns, produces a milestone-based
  implementation plan, then executes each milestone through a build →
  regression-check → fix → commit loop, with the adversarial
  `hostile-review` pass deferred to a single end-of-task review —
  everything in one agent except that final review's per-finding
  verification, which fans out fresh subagents once at the end.

  Has no `AskUserQuestion` tool, so it never asks interactively; instead it
  stops with a `## Decision needed` block whenever a human decision is
  required, which works however it's invoked. Fully autonomous by default:
  it opens every run with a multi-select `## Decision needed` asking which
  of three checkpoints (plan approval, test opt-in, per-milestone commit
  confirmation) should pause for input — leave all unselected and it runs
  start to finish without stopping, except for hard blocks (ambiguous
  requirements, exhausted retries, confirmed Critical Issues/regressions,
  failed required checks) that always pause regardless. Communicates
  tersely by design — plain words, `file:line` facts over prose, no
  filler.

Because the main agent runs the whole pipeline, **the task runs on the
session model** you pick with `/model` — never above it, never a surprise
upcharge. Run the session on **Haiku** for a cheap pass, **Sonnet** for
balanced cost/quality, or **Opus** for a hard task; the driver, the
building, and the final review's bug-hunt all follow that one dial with no
plugin edit. The only work outside it is the short-lived `Explore`
verification subagents in the final review, which run read-only and once.
Cross-check spend with `/usage` (press `w` for the 7-day view), which
attributes recent quota draw to each session, skill, plugin, and MCP
server.

### Skills

- **`hostile-review`** — adversarial two-pass code review: a hostile Pass 1
  hunts for concrete, evidence-backed defects, then a fresh neutral
  subagent independently verifies each finding in Pass 2 (batched four at a
  time) before anything is reported. Used by the `orchestrate` agent for
  its final review, and available standalone for reviewing a diff, PR,
  file, directory, or git
  ref.

### Output styles

- **`senior-developer-mode`** — autonomous execution with a minimal-change
  philosophy: concise, no-emoji communication; asks only when blocked by
  something destructive, irreversible, or genuinely ambiguous; verifies with
  the project's formatter/linter/type-checker/tests before reporting done.

### Hooks

- **`approve-plan-writes`** (`PreToolUse`) — auto-approves `Write`/`Edit`
  calls that target the orchestrator's own plan file (`docs/plans/*.md`)
  so its per-phase bookkeeping never prompts for permission. The plan file
  is a durable record the `orchestrate` agent overwrites on every phase;
  approving those writes removes the one prompt the plugin generates on
  itself without touching how any application file is handled — every other
  `Write`/`Edit` still goes through the normal permission flow. The hook
  degrades to the normal prompt if `jq` is unavailable or the payload can't
  be parsed, so it can only ever remove a prompt, never block a write.

## Installation

### From the marketplace

Add this repository as a plugin marketplace, then install the plugin:

```
/plugin marketplace add k-log/nbd-claude
/plugin install orchestrate-suite@nbd-claude
```

### Local development

Alternatively, load the plugin directly from a local checkout:

```
claude --plugin-dir .
```

Validate the manifests at any time with:

```
claude plugin validate .
```

## License

MIT — see [LICENSE](LICENSE).
