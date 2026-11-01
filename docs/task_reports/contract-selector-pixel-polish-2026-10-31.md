# Contract selector pixel polish — 2026-10-31

Baseline: `5fd84a5a9153a3fedfc38489a8aa525d0ba9c8d4` on `fix/ui/fire-worker-feedback-20261031`.

The three visible 3D, 6D, and 9D renewal buttons use the existing 34 × 34 brown panel style. Their selected checklist is the existing 16 × 16 texture rendered at its native size with nearest filtering, with a fixed marker slot in each button. The Contract panel minimum is 118 × 102 logical pixels so the larger controls fit immediately on opening. Duration, price, renewal behavior, and the existing fixed-width day range are unchanged.

In the Job Board's Choose Contract panel, the quote summary is lowered by two logical pixels. The existing error-feedback label is also lowered by two pixels solely to keep it separated from the quote; action buttons, messages, and payment behavior remain unchanged.

The original reference images were inspected by the parent reviewer. This executor could not materialize them: two supported preparation attempts returned signed transfers without a workspace path, and the transfer host was outside the enforced network allowlist. No restricted download was attempted. Existing game assets and before/after local renders were inspected here; no screenshots are included in the commit.

## Verification

All tests used Godot 4.5.1 and isolated profiles. Rendered tests used a 400 × 225 logical viewport and a 1200 × 675 window.

- **PASS:** Rendered `test_scene_worker_renew_currency.tscn`. It checks native-size and nearest-filtered markers, compares every opaque source pixel against the rendered 3D/6D/9D checklist within one color step, verifies button/label separation, fixed geometry, keyboard and mouse selection, panel fit on opening and at the viewport edge, close/reopen without charge, and the existing renewal/date cases.
- **PASS:** Rendered `test_scene_content_prepaid_ui.tscn`. It checks the summary's new gap below the duration buttons, separation from the error and action controls, error readability, unchanged focus, selection, totals, and payment behavior.
- **PASS:** `test_scene_worker_control.tscn` headless, including the existing Fire confirmation flow.
- **PASS:** The two rendered UI tests also passed on the unmodified baseline. `git diff --check` passed after the changes.

During development, an initial test had a Vector2/Vector2i comparison parse error, and a first-frame fit assertion found the initial panel minimum two pixels too short. Both were corrected and the final tests passed. Linux software rendering reported that changing V-Sync mode is unsupported. Windows, Android, and a full human playthrough were not tested.
