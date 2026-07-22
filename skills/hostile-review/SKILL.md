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
report findings. This runs entirely in one agent: you hunt, then you turn
the hostile framing off and re-verify your own findings. No subagents.

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

**Pass 2 — Neutral re-verification:**

Now drop the "worst code you've seen" framing entirely. For each Pass 1
finding, re-approach it cold, as a neutral reviewer with no stake in whether
the bug is real. Phrase each as a hypothesis to check — "Determine whether X
actually occurs at file:line" — and re-read the referenced code from
scratch, tracing the exact logic path, rather than trusting your Pass 1
conclusion. Deliberately try to disprove each finding; a bug you can't
re-confirm on a fresh reading is a false positive, not a bug.

For each finding, settle on: confirmed / partially confirmed / disputed, the
supporting evidence (the traced code path, not an opinion), and — only if
confirmed or partially confirmed — a severity: `critical` (crash, data loss,
security), `high` (wrong behavior on a common path), `medium` (wrong
behavior on an edge case), `low` (real but cosmetic/maintainability only).

**Output:**

Present every Pass 1 finding in one markdown table, including ones Pass 2
disputed:

| Severity | File:Line | Issue | Evidence | Verdict |
| -------- | --------- | ----- | -------- | ------- |

- `Verdict` always states the word (`Confirmed`, `Partially confirmed`, or
  `Disputed`) followed by the Pass 2 reasoning.
- Confirmed and partially confirmed findings sort together, ordered by
  severity (critical → high → medium → low); disputed findings sort last.
- For disputed findings, set `Severity` to `Disputed`.
- If Pass 1 found nothing, say so plainly and stop — do not invent findings
  to fill the table.
