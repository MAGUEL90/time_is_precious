# Worker Manage and Contract review — 2026-10-31

Based on `f4d17769f4593a7d3936ca4f18b0f2c9d7e1c1eb` on `fix/ui/fire-worker-feedback-20261031`. No PR or merge is included in this work.

Manage has four equally sized compact actions. The Fire-disabled reason appears on hover in the existing warning color, using the existing UI font at size 6 without the previously added outline. Contract uses an existing right-arrow asset rotated down for a 3/6/9-day dropdown, a top-right Close action, and the actual expiry below Renew. No prices, transaction rules, save schema, or expiry rules were changed. New contracts use the existing 07:00 expiry on the day after `payroll_paid_until_day`; legacy paid records use 08:00. An unpaid or unavailable expiry displays `-`.

## Review images

- [Manage](evidence/worker-manage-contract-2026-10-31/manage.png) and [Fire hover](evidence/worker-manage-contract-2026-10-31/fire-hover.png): controlled UI fixtures with names from the game's citizen pool.
- [Contract from an earned journey checkpoint](evidence/worker-manage-contract-2026-10-31/contract.png), [dropdown open](evidence/worker-manage-contract-2026-10-31/dropdown.png), and [insufficient funds](evidence/worker-manage-contract-2026-10-31/insufficient-funds.png).
- Earlier baseline images: [Manage](evidence/worker-hub-contract-review-2026-10-31/manage-actions.png) and [Contract](evidence/worker-hub-contract-review-2026-10-31/contract-panel.png).

Screenshots are logical 400×225 captures from Godot 4.5.1 running a 1200×675 window. The original owner reference images were inspected by the parent session; their Library downloads were not available in this executor.

## Validation

- **PASS:** `test_scene_worker_renew_currency.tscn`, both rendered and headless, using isolated saves. Rendered checks cover mouse and keyboard selection, focus cycling and disabled Renew, Close and dropdown cancellation without payment, 3/6/9 quotes, changed-price review, one payment on Renew, insufficient funds, actual and legacy expiry, long expiry text, and layout bounds. Arrow pixels are compared in the rendered run; mouse selection is only exercised in that run.
- **PASS:** rendered `test_scene_worker_fire_hover.tscn`: hover-only reasons, existing warning color, no added outline, and edge bounds. `test_scene_worker_control.tscn` and `test_scene_prepaid_contracts.tscn` also passed.
- **PASS:** rendered `test_scene_expired_notice_regression.tscn` multi-worker `write`, `renew`, `partial-read`, and `read` phases, using a fresh isolated profile.
- **PASS:** `test_scene_contract_ui_review.tscn` `prepare`, rendered `capture`, and separate headless `write` and `read` processes, using a copy of an earlier earned journey checkpoint with player needs active. After the focus adjustment, `capture` was run again and passed. The uninstrumented headless [write](evidence/worker-manage-contract-2026-10-31/normal-write.log) and [read](evidence/worker-manage-contract-2026-10-31/normal-read.log) used normal in-game clock speed, physical travel, real sleep/save and Continue.
- **PASS:** `test_scene_worker_proceeds_journey.tscn` `read` using a copy of a previously earned and bed-saved worker-proceeds checkpoint. This checks its Continue phase; its full write journey was not rerun for this UI change.
- **TIMEOUT / DIAGNOSIS:** an earlier rendered normal-journey UI `write` process reached its 150-second limit and produced no intermediate progress log; that particular run did not finish. The saved checkpoint starts on Day 6 at 08:52 with `last_sleep_day` already 6, so the normal scenario must wait until the next day before it can sleep again. A separate copy with trace-only test instrumentation [showed](evidence/worker-manage-contract-2026-10-31/normal-timeout-diagnostic.log) the clock advancing from Day 6 08:55 to Day 7 00:11, with needs active and the game unpaused, before real sleep and save completed; its write and read both passed. The subsequent uninstrumented headless write/read also passed as noted above. The original silent timeout alone cannot prove its precise runtime state. Windows was not tested. The Linux software renderer reported a V-Sync warning.

A separate exploratory `--check-only --script` invocation failed to resolve project autoloads because it did not start the project scenes. The corresponding scripts were loaded through the passing project-scene runs above.
