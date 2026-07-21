#!/usr/bin/env bash
# orchestrate-suite :: PreToolUse hook
#
# Auto-approves Write/Edit calls that target the orchestrator's own plan
# file (docs/plans/*.md). That file is pure bookkeeping the `orchestrate`
# agent overwrites on every phase, so prompting for it once per phase adds
# friction without adding safety. Every other Write/Edit still goes through
# the normal permission flow untouched.
#
# Emitting no decision (a bare `exit 0`) defers to the normal flow, so any
# failure here degrades to the usual prompt rather than blocking work.
set -euo pipefail

input=$(cat)

# No jq -> can't parse the payload; fall back to the normal prompt.
command -v jq >/dev/null 2>&1 || exit 0

file_path=$(jq -r '.tool_input.file_path // empty' <<<"$input")

case "$file_path" in
  */docs/plans/*.md | docs/plans/*.md)
    jq -n '{
      hookSpecificOutput: {
        hookEventName: "PreToolUse",
        permissionDecision: "allow",
        permissionDecisionReason: "orchestrate-suite: auto-approved plan-file write (docs/plans/*.md)"
      }
    }'
    ;;
esac

exit 0
