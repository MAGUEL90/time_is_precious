# TIME IS PRECIOUS — GIT & CHANGE CONTROL

Status: TEMPLATE — NOT ACTIVE

Purpose: make every AI change reviewable and reversible.

## Protected main rule

`main` is a protected release branch in this repository.

Repository rules currently require pull-request based changes and protect against deletion/non-fast-forward history changes. The control pack is stricter than the repository ruleset: an agent must not develop directly on `main`, merge its own work into `main`, force-push, rewrite published history, or remove known-good tags/checkpoints.

GitHub configuration is not a substitute for this human-approval rule.

## Known-good baseline

Human-validated candidate baseline:

`fcb5dc24a74c3b5b2c23af9ad10676752e7532a1`

This is the merge commit for PR #95 and was reported by the Game Director as working correctly in Godot after local runtime validation on 2026-09-05.

Human smoke-test status: `PASSED`

Suggested permanent checkpoint tag:

`agent-baseline-2026-09-05`

Actual approved tag: `PENDING TAG CREATION`

Important: the control pack must remain `TEMPLATE — NOT ACTIVE` until the permanent tag exists and the Game Director explicitly approves activation.

## One task = one branch

Use the repository's existing branch taxonomy from `docs/root-branch-map.md`:

`<type>/<root>/<child-work>`

Allowed task types include:
- `feature`
- `fix`
- `refactor`
- `chore`
- `test`

Examples:
- `feature/process-workshop/ui-status-panel`
- `fix/inventory/slot-quantity-preview`
- `test/gameplay-hud/ui-sandbox-smoke`
- `chore/agent-control/activation-prep`

Do not create a second competing `agent/...` taxonomy just to identify AI-authored work. Agent identity belongs in the Agent Run Log and PR description.

Do not mix unrelated tasks in one branch.

## Dirty working tree guard

Before editing, inspect repository status. Never overwrite, discard, reset, or clean unrelated uncommitted human work. If safe isolation is impossible, mark implementation blocked.

## Baseline record

Every run log entry records branch, baseline commit hash, starting repository status and risk level.

## Commit rules

Agent commits, when authorized, must stay on the feature branch, remain small/coherent, describe actual changes, exclude unrelated formatting/noise, and never claim tests passed when they were not run.

## Mandatory diff review

Before completion, inspect the branch diff against its baseline, list created/modified/deleted/renamed files, confirm no protected/unrelated files changed unexpectedly, and explain any scope deviation.

## Pull request rule

Implementation intended for `main` must go through a PR.

The PR must include:
- objective
- risk level
- baseline commit
- changed-file summary
- tests performed
- untested areas
- known risks
- any protected-area authorization

## Merge authority

Agent status may be:
- `FAILED`
- `PARTIAL`
- `PASSED — NEEDS HUMAN REVIEW`

Only the human Game Director may set:
- `APPROVED — MERGE`
- `REJECTED`
- `ROLL BACK`

Even if GitHub technically permits a merge without an approving-review count, the agent must not interpret that as merge authority.

## Recovery preference

Prefer auditable recovery through rejection of an unmerged branch or a normal revert. Avoid destructive history rewriting.

## Scope expansion

If a task unexpectedly reaches major systems, do not silently expand it. Record the dependency and leave high-risk integration unimplemented until authorized.
