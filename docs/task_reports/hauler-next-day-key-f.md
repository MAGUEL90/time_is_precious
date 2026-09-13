# Hauler next-day shortcut: F

Date: 2026-09-13
Branch: feature/process-workshop/clay-worksites
Baseline: 0f971ab330b83e2c8502ef943ddd04e94019565a
Starting state: existing dirty feature worktree, including the edited untracked fixture and reports.
Risk: LEVEL 1 — isolated debug shortcut.
Status: PASSED — NEEDS HUMAN REVIEW

The Director requested F in place of PgDn. Change only the delivery fixture key handler, on-screen hint and its existing shortcut regression expectations; update current manual instructions and mark the older report's shortcut as superseded. No project input settings, save schema, production scenes or gameplay rules change.

Acceptance: F advances to tomorrow 06:45; old shortcuts do not; paused/held-key guards remain. Run the existing HaulerDeliverySetupTest, verify project launch and inspect the incremental diff. Keep all human edits intact.

Work split: Astra Medium implements and verifies. Luna XHigh is not delegated.

Verification: HaulerDeliverySetupTest passed, including F → tomorrow 06:45, no repeated/paused advance and no advance from PgDn/F8. Main headless launch exited 0. The existing certificate-store and ObjectDB / 15-resource shutdown diagnostics remain; no new blocking errors appeared. The F hint and current manual instructions were read back. Incremental script diff and whitespace checks passed. No new test suite, scene layout changes, commit, push or merge. Pre-edit script copy: `%TEMP%/tip-next-day-key-f-20260913-120847`.

Changed files: `test_scene_hauler_delivery_setup.gd`; this report; manual instructions in `worker-worksite-save-mvp.md`, `hauler-destination-daily-target.md`, `hauler-cart-palette-and-progress-font.md`; superseded-shortcut note in `hauler-commute-without-cart-and-pagedown.md`.
