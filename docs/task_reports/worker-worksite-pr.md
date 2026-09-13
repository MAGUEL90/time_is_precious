# Worker/worksite MVP publication checkpoint

Date: 2026-09-13
Branch: feature/process-workshop/clay-worksites
Implementation checkpoint: 6adda7e5478ec66d23f716d9c50939d11f759dd5
Branch baseline: 0f971ab330b83e2c8502ef943ddd04e94019565a
Target main checked: 02a0124
Status: PASSED — NEEDS HUMAN REVIEW

## Objective and authority

The Director requested a push and PR and asked whether the game concept needs updating.
Publish the tested worker/worksite MVP and record only the worker decisions already explicitly
approved in this conversation. Documentation/publication is LEVEL 1; the feature being
published includes the previously authorized LEVEL 2 integrations and LEVEL 3 prototype save.
No additional balancing, architecture, gameplay behavior or save-format change is introduced.

## Documentation and preservation

Added dated section 9.5 in `docs/game-concept.md` for Daily assignment, common commute speed,
Laborer/Hauler cooperation, a three-item cart, one destination with an accepted-item daily
target, exclusive equipment, Worker Hub actions, contribution XP and Productive days.
Clarified that profession synergy and further tool requirements/effects remain later decisions.
These are design rules, not claims of main-map or production-save integration.

The starting working tree is dirty. Stage only the new concept edits and this report.
Earlier local concept/version drafts, CONTENT_LOG edits, the apple-pickup hunk, generic
work-progress scene tweaks, old-asset cleanup and the obsolete storage prototype remain local.
The concept's last-updated date reflects this publication; its earlier local draft version
and unrelated sections are preserved. No governance file is edited.

## Review and verification

- Refreshed GitHub refs. Main advanced only through AGENTS.md updates; read current rules v1.2.
- A temporary merge-tree check against main passed without conflicts and without changing a
  branch or working file. The main-side changes do not affect runtime code.
- The implementation is the unchanged `6adda7e` checkpoint. Its clean import, 15 checks and
  graphical commute/delivery inspection are recorded in `worker-mvp-checkpoint.md`.
- This follow-up changes documentation only. Review the selectively staged diff, whitespace
  and preservation hashes; repeating the unchanged runtime checks is unnecessary.
- Known certificate-store and exit-time ObjectDB/resource diagnostics remain documented in the
  implementation report. Android/export and full-game save integration are untested.

## Publication boundary

Push this feature branch and create one PR targeting main. Include the implementation scope,
protected-area authorization, tests and prototype limitations in its description. Read back
the remote head and PR base/head after publication. Final merge authority remains with the
human Game Director; the PR does not enable automatic merge.

Next proposed MVP: Inventory-to-City-Storage tool supplies, then main-map and production-save
integration. The current test fixture still seeds equipment supplies.

Work split: Astra Medium owns concept review, selective commit, push and PR. Luna XHigh is
not delegated because this is one bounded publication task.
