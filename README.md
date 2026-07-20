# orchestrate-suite

A Claude Code plugin providing a task-orchestrator agent that delegates
planning, research, implementation, review, and regression checks across
seven specialized worker subagents, plus a hostile-review skill and a
senior-developer-mode output style.

## Important: how to invoke `orchestrate`

**Never invoke `orchestrate` with `claude --agent orchestrate` when it's
loaded from this plugin.** That invocation path is confirmed broken by live
testing: `orchestrate` spawns zero subagents in that mode and never actually
delegates any of its phases, silently defeating the entire design.

Always delegate to it as an ordinary subagent instead, e.g. from the main
session:

```
Use the Agent tool with subagent_type: orchestrate to <task description>.
```

The likely cause is that `--agent orchestrate` runs the agent as the
top-level session agent rather than as a spawned subagent, which changes how
its `tools:` allowlist and nested `Agent(...)` grants are resolved —
`orchestrate` relies on being able to spawn its seven worker subagents via a
scoped `Agent(...)` tool grant, and that grant does not behave the same way
when it *is* the session agent. See `agents/orchestrate.md`'s own
`description` field for the full detail; it carries this warning wherever
the agent is listed or invoked from.

## Components

### Agents

- **`orchestrate`** (opus) — the task orchestrator. Gathers requirements,
  optionally fetches ticket/PR context, researches dependencies, analyzes
  codebase patterns, produces a milestone-based implementation plan, then
  executes each milestone through a build → review → fix → commit loop.
  Has no `AskUserQuestion` tool by design — see above — so it stops with a
  `## Decision needed` block whenever a human decision is required.
  Fully autonomous by default: it opens every run with a multi-select
  `## Decision needed` asking which of three checkpoints (plan approval,
  test opt-in, per-milestone commit confirmation) should pause for input —
  leave all unselected and it runs start to finish without stopping,
  except for hard blocks (ambiguous requirements, exhausted retries,
  confirmed Critical Issues/regressions, failed required checks) that
  always pause regardless. Communicates tersely by design — plain words,
  `file:line` facts over prose, no filler — to keep the whole pipeline
  fast and token-cheap across every subagent it fans out to.

Seven worker subagents, delegated to exclusively by `orchestrate` (though
each also works standalone):

| Agent               | Model  | Role                                                        |
| ------------------- | ------ | ------------------------------------------------------------ |
| `fetch-details`     | haiku  | Fetches and summarizes ticket/PR context                     |
| `research`          | haiku  | Researches external dependencies, libraries, APIs            |
| `analysis`          | sonnet | Analyzes existing codebase structure and conventions         |
| `parallelize-task`  | haiku  | Restructures a milestone's steps into independent step-groups|
| `build`             | sonnet | Implements a specific, already-planned unit of work          |
| `review-code`       | opus   | Adversarial code review via the `hostile-review` skill       |
| `check-regressions` | sonnet | Runs tests (when opted in) and static regression analysis    |

Model assignment favors the cheapest model that can do the work reliably —
haiku for high-volume, low-judgment reads; sonnet for implementation and
synthesis; opus reserved for orchestration and adversarial review, where
the cost of a missed bug or a bad plan outweighs the cost of the model.
`orchestrate` also parallelizes aggressively: independent research topics,
analysis areas, milestones, and review passes all run concurrently rather
than one at a time, by default.

### Skills

- **`hostile-review`** — adversarial two-pass code review: a hostile Pass 1
  hunts for concrete, evidence-backed defects, then a fresh neutral
  subagent independently verifies each finding in Pass 2 before anything is
  reported. Used by the `review-code` agent, and available standalone for
  reviewing a diff, PR, file, directory, or git ref.

### Output styles

- **`senior-developer-mode`** — autonomous execution with a minimal-change
  philosophy: concise, no-emoji communication; asks only when blocked by
  something destructive, irreversible, or genuinely ambiguous; verifies with
  the project's formatter/linter/type-checker/tests before reporting done.

## Installation

Add this repository as a plugin source and enable it, or load it directly
for local development:

```
claude --plugin-dir .
```

Validate the manifest at any time with:

```
claude plugin validate .
```

## License

MIT — see [LICENSE](LICENSE).
