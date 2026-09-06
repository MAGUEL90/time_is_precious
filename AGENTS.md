# TIME IS PRECIOUS — AGENT CONTROL ENTRYPOINT

Status: ACTIVE

The agent-control pack under `docs/agent-control/` is active for coding-agent governance.

All agents must begin with:

`docs/agent-control/00 - AGENT - READ ME FIRST.md`

and follow the mandatory reading order defined there before implementation work.

Activation baseline:
- Human-tested commit: `fcb5dc24a74c3b5b2c23af9ad10676752e7532a1`
- Permanent checkpoint tag: `agent-baseline-2026-09-05`

Active rules:
- Default permission is `LEVEL 1 — ISOLATED / LOW-RISK` unless the Game Director authorizes a higher level.
- Do not infer permissions beyond the assigned task and control pack.
- Do not work directly on `main` or merge agent-authored work into `main`.
- Human Game Director retains final merge authority.
- Do not modify this control pack unless the Game Director explicitly requests a control-pack change.
