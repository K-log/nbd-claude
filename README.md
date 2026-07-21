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

- **`orchestrate`** (inherits your session model) — the task orchestrator.
  Gathers requirements,
  optionally fetches ticket/PR context, researches dependencies, analyzes
  codebase patterns, produces a milestone-based implementation plan, then
  executes each milestone through a build → regression-check → fix → commit
  loop, with the adversarial `review-code` pass deferred to a single
  end-of-task review.
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
| `analysis`          | inherit| Analyzes existing codebase structure and conventions         |
| `parallelize-task`  | haiku  | Restructures a milestone's steps into independent step-groups|
| `build`             | inherit| Implements a specific, already-planned unit of work          |
| `review-code`       | inherit| Adversarial code review via the `hostile-review` skill       |
| `check-regressions` | inherit| Runs tests (when opted in) and static regression analysis    |

**No subagent ever runs on a model more expensive than the one you pick for
the session** with `/model` — that's the design invariant. It falls out of
two rules: the three high-volume read-only workers (`fetch-details`,
`research`, `parallelize-task`) are pinned to **Haiku**, the cheapest tier,
so they're always at or below your session model *and* keep their discount
whenever you're on something pricier; everything else — `orchestrate`,
`analysis`, `build`, `review-code`, `check-regressions` — is set to
**`inherit`**, so it runs on exactly the session model, never above it.

The upshot is a single dial: run the session on **Haiku** and the whole
pipeline is Haiku; on **Sonnet** for balanced cost/quality; on **Opus** for
a hard task and the driver, analysis, build, and final review all follow —
no plugin edit, and never a surprise upcharge past your choice.

`orchestrate` also reports a **delegation ledger** — every subagent it
spawned, the model each ran on, the call count, and the purpose — in its
plan file and final summary, so the fan-out (and where the tokens went) is
legible without leaving the session. Cross-check it against `/usage`, which
attributes recent quota draw to each subagent, skill, plugin, and MCP
server (press `w` for the 7-day view).

To keep usage steady rather than spiky, `orchestrate` parallelizes only
genuinely independent work and **caps concurrency at 4 subagents at a
time**, queuing the rest; the `hostile-review` skill applies the same
batch-of-4 cap to its per-finding verification subagents. The adversarial
`review-code` pass runs **once over the full task diff at the end** instead
of on every milestone — the per-milestone loop keeps the cheaper
`check-regressions` static/regression check to catch breakage early.

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
