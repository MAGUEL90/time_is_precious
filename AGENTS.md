# TIME IS PRECIOUS — AGENT CONTROL ENTRYPOINT

Rules Version: `1.1`
Status: `ACTIVE`
Last Rules Update: `2026-09-10`

This file is the root entrypoint for coding-agent governance in **Time is Precious**.
Detailed rules live under `docs/agent-control/` and remain authoritative for their respective domains.

## 1. ROLE & AUTHORITY

Human Game Director:
- Owns final decisions on game vision, gameplay, architecture direction, protected changes, risk escalation and merge approval.
- May explicitly raise or narrow an agent's permitted risk level for a task.

Lead / root developer session:
- Current operating model: `Astra Medium`.
- Keep architectural reasoning, gameplay decisions, ambiguous debugging, task decomposition and final review in the root Astra session.
- The root session remains responsible for the quality and correctness of delegated work.

Implementation subagent:
- Current operating model: `Luna XHigh`.
- Use for narrow, well-specified implementation work when delegation is useful.
- A subagent is an implementation helper, not an independent game designer or architecture authority.

If an explicitly named model/configuration is unavailable, do not silently substitute it. Report the limitation to the Game Director.

## 2. REQUIRED READING & SOURCE OF TRUTH

Before implementation work, read and follow:

`docs/agent-control/00 - AGENT - READ ME FIRST.md`

Then follow the mandatory reading order defined there.

Primary project authorities include:
- Design: `docs/game-concept.md`
- Current progress / priority: `ROADMAP.md`
- Technical architecture: `ARCHITECTURE.md`
- Merged implementation history: `DEVLOG.md`
- Technical domain / branch conventions: `docs/root-branch-map.md`
- Detailed agent governance: `docs/agent-control/**`

Do not treat current buggy behavior as proof of intended design.

## 3. ACCESS & SCOPE LIMITS

- Default permission is `LEVEL 1 — ISOLATED / LOW-RISK` unless the Game Director explicitly authorizes a higher level.
- Do not infer permissions beyond the assigned task and active control pack.
- Protected paths and system-protected areas remain governed by `docs/agent-control/01 - PROJECT CONTROL.md` and related control files.
- Do not expand scope merely because a nearby improvement is convenient.
- Do not change gameplay rules, balancing, economy, story, save compatibility, project-wide conventions, autoloads, plugins/addons or project settings without the authorization required by the control pack.
- Do not modify `AGENTS.md` or `docs/agent-control/**` unless the Game Director explicitly requests a rules/control-pack change.

Delegating work does not increase permission. Every subagent inherits the same task scope, risk level, protected-path restrictions and project rules as the parent session.

## 4. DELEGATION & SUBAGENT POLICY

The root Astra session decides whether work should be delegated based on:
- clarity of the task
- risk level
- scope size
- architectural impact
- whether a useful independent implementation unit exists

Do **not** delegate every implementation automatically.

Delegate to Luna XHigh when the work is narrow, well-specified and implementation-focused, such as approved UI implementation, local wiring, targeted fixes, tests, boilerplate, data binding or another bounded task with clear expected behavior.

Before delegating, the parent must define:
- exact goal
- files in scope
- constraints
- acceptance criteria

Keep the following in the root Astra session:
- architectural reasoning and architecture decisions
- gameplay decisions or balancing decisions
- ambiguous debugging that requires broad investigation or judgment
- save-compatibility decisions
- project-wide conventions
- decisions that can materially change system behavior or long-term project structure
- final review and acceptance of delegated work

After a subagent finishes:
1. Inspect the actual changes or diff.
2. Verify the work stayed within scope and permissions.
3. Review relevant tests/results and nearby regression risk.
4. Reject, revise or accept the result based on evidence.

A subagent saying a task is complete is not sufficient evidence of completion. The root Astra session remains accountable for the final result.

Use subagents proactively when independent subtasks would materially improve speed or parallelism. Do simple tasks directly when delegation would add unnecessary overhead.

## 5. GIT & CHANGE CONTROL

- Do not work directly on `main` or another protected release branch.
- Follow the repository branch convention and one-task-per-branch rules in the active control pack.
- Do not force-push or rewrite published history.
- Do not merge agent-authored work into `main` yourself.
- Human Game Director retains final merge authority.
- Review the branch diff before presenting work for approval.

Known-good activation baseline:
- Human-tested commit: `fcb5dc24a74c3b5b2c23af9ad10676752e7532a1`
- Permanent checkpoint tag: `agent-baseline-2026-09-05`

Git history remains the normal fine-grained recovery mechanism. Permanent tags/checkpoints are reserved for important human-validated states, not every small change.

## 6. QA & FINAL REVIEW

Before presenting an implementation as complete:
- verify the requested behavior
- run applicable parse/launch/scene/test checks
- check nearby regression risk
- inspect changed files and diff
- report failed or untested areas honestly
- report remaining risks and anything requiring Game Director approval

For delegated work, final review belongs to the root Astra session, not the implementation subagent.

Only the human Game Director may give final merge approval.

## 7. VERSION NOTES

### v1.1 — 2026-09-10
- Structured the root rules into clear responsibility sections.
- Added explicit `Astra Medium` lead / `Luna XHigh` implementation-subagent policy.
- Defined delegation suitability, pre-delegation requirements and mandatory parent review.
- Clarified that subagents inherit all scope, access and risk restrictions.

### v1.0 — 2026-09-06
- Initial active agent-control governance.
- Established human merge authority, protected main, active control-pack entrypoint and known-good baseline.
