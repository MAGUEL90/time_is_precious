# TIME IS PRECIOUS — GIT & CHANGE CONTROL

Status: TEMPLATE — NOT ACTIVE

Purpose: make every AI change reviewable and reversible.

## Protected main rule
Assume `main` is protected unless repository configuration says otherwise.
The agent must not develop directly on `main`, merge into `main`, force-push, rewrite published history, or remove known-good tags/checkpoints.

## Known-good baseline
Before the first implementation run, verify the game launches in a known-good state, commit intended human changes, and create a permanent checkpoint/tag.
Suggested initial tag: `v0.1-before-agent-work`
Actual approved tag: `TBD`

## One task = one branch
Suggested patterns:
- `agent/ui/<task-name>`
- `agent/bugfix/<task-name>`
- `agent/tooling/<task-name>`
- `agent/test/<task-name>`
- `agent/system/<task-name>`

Do not mix unrelated tasks in one branch.

## Dirty working tree guard
Before editing, inspect repository status. Never overwrite, discard, reset, or clean unrelated uncommitted human work. If safe isolation is impossible, mark implementation blocked.

## Baseline record
Every run log entry records branch, baseline commit hash, starting repository status and risk level.

## Commit rules
Agent commits, when authorized, must stay on the feature branch, remain small/coherent, describe actual changes, exclude unrelated formatting/noise, and never claim tests passed when they were not run.

## Mandatory diff review
Before completion, inspect `git diff`, list created/modified/deleted/renamed files, confirm no protected/unrelated files changed unexpectedly, and explain any scope deviation.

## Merge authority
Agent status may be:
- `FAILED`
- `PARTIAL`
- `PASSED — NEEDS HUMAN REVIEW`

Only the human may set:
- `APPROVED — MERGE`
- `REJECTED`
- `ROLL BACK`

## Recovery preference
Prefer auditable recovery through revert or rejection of an unmerged branch. Avoid destructive history rewriting.

## Scope expansion
If a task unexpectedly reaches major systems, do not silently expand it. Record the dependency and leave high-risk integration unimplemented until authorized.
