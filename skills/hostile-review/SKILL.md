---
name: hostile-review
description: >-
  Adversarial code review that hunts for real, verifiable bugs, then
  independently re-verifies each finding before reporting. Use when asked to
  review a diff, PR, file, directory, or git ref for concrete defects rather
  than style opinions. Triggers on "hostile review", "adversarial review",
  "hunt for bugs", or when the `orchestrate` agent needs its two-pass review
  methodology.
---

Arguments (`args`, if provided): optional file(s), directory, glob, or diff
ref to scope the review.

This is a read-only review. Do not edit, fix, or modify any files — only
report findings. Pass 1 is a single-agent hostile hunt; Pass 2 dispatches a
fresh neutral subagent per finding for independent verification. This
per-finding fan-out is deliberate — a reviewer with no memory of the
hostile framing is the strongest check against false positives — and it is
meant to run once over the full scope, not repeatedly.

**Resolve scope:**

1. If arguments are given, split them on whitespace into one or more tokens.
   - If every token resolves to an existing file, directory, or glob match on
     disk, treat them together as the literal scope — this disk-existence
     check takes priority over the ref rules below so relative paths like
     `../shared/utils.ts` are never misread as a git ref, and space-separated
     multi-file input (e.g. `src/a.ts src/b.ts`) resolves correctly instead
     of being treated as one invalid token.
   - Otherwise, if there is exactly one token and it contains `..` (e.g.
     `main..feature`), treat it as a git ref range and run
     `git diff <ref-range> --stat` to resolve the file list.
   - Otherwise, if there is exactly one token, treat it as a single git ref
     (e.g. `main`, `HEAD~3`, a commit SHA) and run `git diff <ref> --stat` to
     resolve the file list.
2. If no arguments are given: run `git diff HEAD --stat`. If that errors
   (e.g. no commits yet), fall back to `git diff --stat` instead.
3. If scope is still empty or ambiguous after the above (including
   multi-token arguments where not every token resolved as a path), and an
   `AskUserQuestion` tool is available, ask which files/directory/ref to
   review before continuing. If invoked from a context with no
   `AskUserQuestion` tool (e.g. delegated to as a subagent), report the
   ambiguity as an unresolved question instead of guessing.

**Pass 1 — Hostile review:**

Treat this code as some of the worst you've seen. Assume it is broken and do
not extend good faith. You are hunting concrete bugs, not style opinions.

1. Read every target file in full. Do not skim.
2. Hunt for concrete defects: logic errors, off-by-one errors, null/undefined
   handling, race conditions, resource/memory leaks, broken error handling,
   security holes, unhandled edge cases, type mismatches, dead/unreachable
   code, and contract mismatches between caller and callee.
3. Verify before listing anything:
   - Trace the exact code path that triggers each suspected issue.
   - Prove it where you can: run the project's linter/type-checker/tests
     (e.g. `tsc`, `eslint`, `pytest`, `cargo check`) or construct the
     specific input/state that breaks it.
   - Drop anything you cannot trace to a concrete trigger. No "this might be
     an issue" — either it reproduces from reading the code, or it does not
     go on the list.
4. Write a concise findings list: one entry per issue with `file:line`, a
   one-sentence description of the concrete failure mode, and the evidence
   that proves it.

**Pass 2 — Neutral verification (subagents):**

For each Pass 1 finding, dispatch a fresh, independent subagent (Agent tool,
subagent type `Explore`). It is read-only by design — Write/Edit are denied
at the tool level, so the "no edits" constraint is structural here, not just
an instruction. It must have no memory of the "worst code" framing above.
Give it only:

- The file(s) and line range in question.
- The claimed defect, phrased as a neutral hypothesis to check: "Determine
  whether X actually occurs at file:line. Do not assume it is real — verify
  by re-reading the referenced code and tracing the exact logic path."
- Instructions to return: confirmed / partially confirmed / disputed, its
  supporting evidence (the traced code path, not just an opinion), and —
  only if confirmed or partially confirmed — a severity: `critical` (crash,
  data loss, security), `high` (wrong behavior on a common path), `medium`
  (wrong behavior on an edge case), `low` (real but cosmetic/maintainability
  only).

This subagent type has no command-execution access, so it cannot re-run a
linter/type-checker/test that Pass 1 used as evidence. It verifies by code
inspection only — if Pass 1's evidence was a command run, the neutral agent
re-derives the same conclusion by reading the code path that command would
exercise, and states plainly that it verified by inspection rather than
execution.

Findings are independent, so verify them in parallel — but cap the fan-out
at 4 verification subagents at a time. More than 4 findings → dispatch the
first 4 in one message, wait for them, then the next batch. This is the only
fan-out in the workflow and it runs once, so the batch cap keeps even a
finding-heavy review from spiking usage in a burst.

If invoked from a context with no `Agent` tool (so `Explore` subagents
can't be dispatched), fall back to verifying each finding yourself: drop the
hostile framing, re-read each referenced code path cold as a neutral
reviewer trying to disprove the finding, and record the same
confirmed/partially confirmed/disputed verdict, severity, and evidence.

**Output:**

Present every Pass 1 finding in one markdown table, including ones the
neutral pass disputed:

| Severity | File:Line | Issue | Evidence | Neutral Verdict |
| -------- | --------- | ----- | -------- | --------------- |

- `Neutral Verdict` always states the verdict word (`Confirmed`, `Partially
  confirmed`, or `Disputed`) followed by the verifier's reasoning.
- Confirmed and partially confirmed findings sort together, ordered by
  severity (critical → high → medium → low); disputed findings sort last.
- For disputed findings, set `Severity` to `Disputed`.
- If Pass 1 found nothing, say so plainly and stop — do not invent findings
  to fill the table.
