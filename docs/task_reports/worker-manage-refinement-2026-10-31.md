# Worker Manage and Contract refinement — 2026-10-31

Baseline: `cfdf34ecaa6383e16cd48eaaed04c90dae9dd2aa`, branch `fix/ui/fire-worker-feedback-20261031`; working tree was clean. No PR or merge is included.

The four Manage actions retain equal sizes. The reason Fire is unavailable appears centered below the compact panel on hover and the panel reserves space at viewport edges. The narrower duration selector uses the existing rotated arrow and offers only 3/6/9 days. Its list uses the same cream panel asset as Contract, dark pixel text, a subtle highlight and the existing selection check. Price and the shekel icon are vertically aligned; the Contract frame is narrower. Contract rules, prices, expiry, and save data were not changed.

## Images

- [Manage](evidence/worker-manage-refinement-2026-10-31/manage.png) and [Fire hover](evidence/worker-manage-refinement-2026-10-31/fire-hover.png).
- [Contract from an earned journey checkpoint](evidence/worker-manage-refinement-2026-10-31/contract.png) and [dropdown](evidence/worker-manage-refinement-2026-10-31/dropdown.png).
- Previous baseline images: [Manage](evidence/worker-manage-contract-2026-10-31/manage.png), [Fire hover](evidence/worker-manage-contract-2026-10-31/fire-hover.png), [Contract](evidence/worker-manage-contract-2026-10-31/contract.png), and [dropdown](evidence/worker-manage-contract-2026-10-31/dropdown.png).

Images are logical 400×225 screenshots from Godot 4.5.1 in a 1200×675 window. The owner reference images were inspected by the parent session; Library offered only a restricted download host in this executor, so those files were not accessed directly here.

## Verification

- **PASS:** `test_scene_worker_renew_currency.tscn`, rendered and headless. Checks include dropdown dimensions and theme, popup bounds at the viewport edge, mouse and keyboard selection, focus, price/icon alignment, Close and duration changes without payment, one renewal payment, insufficient funds, and active/expired/legacy/long expiry display.
- **PASS:** rendered `test_scene_worker_fire_hover.tscn`; working, travelling, hauling, reserved and workshop-assigned reasons appear below Manage on hover, hide on exit/close/state refresh, stay within viewport edges, and avoid visible buttons. `test_scene_worker_control.tscn` passed headless after correcting an initial duplicate-variable parse error in its new assertions.
- **PASS:** rendered `test_scene_contract_ui_review.tscn` `capture` using a copy of an earlier earned checkpoint with player needs active; renewal and cancellation retained their existing wallet behavior.
- **PASS:** rendered `test_scene_expired_notice_regression.tscn` multi-worker [write](evidence/worker-manage-refinement-2026-10-31/notice-write.log), [renew](evidence/worker-manage-refinement-2026-10-31/notice-renew.log), [partial-read](evidence/worker-manage-refinement-2026-10-31/notice-partial-read.log), and [read](evidence/worker-manage-refinement-2026-10-31/notice-read.log) with an isolated profile; headless `test_scene_prepaid_contracts.tscn` also passed.
- **NOT RUN:** Windows and Android. The Linux software renderer reported that V-Sync could not be changed.
