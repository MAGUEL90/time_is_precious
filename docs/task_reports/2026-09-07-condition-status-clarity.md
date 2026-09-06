# Condition status clarity

## Approved collapse rule adjustment

The Game Director subsequently requested that hunger no longer directly cause fainting, while preserving low-Satiety Focus drain. Removed only the hunger predicate from Player.has_critical_condition; Energy and Focus remain direct triggers. Existing hunger-pressure Focus drain and post-Nightmare hunger consequences are unchanged. This is an explicitly approved protected-mechanic change in scenes/player/player.gd; earlier statements below about no collapse-rule changes describe the prior scope. Added regression checks for zero-Satiety minute advancement without collapse, unchanged hunger Focus penalty, and retained Energy/Focus triggers. Unrelated human edits in scenes/content_scene/content_scene.tscn are preserved.

## Latest user revision

The Game Director requested removal of all HUD notes as visual noise. Removed ConditionHelp, text alerts, and their timer/transition tracking. Retained Energy/Focus/Satiety/EXP labels, bars, and severity-driven colors. Updated regression coverage to assert that neither help notes nor text alerts are created; headless test PASS and diff check clean. Earlier help/alert implementation and render evidence below describe the superseded version, not the final UI.

- Branch: `fix/gameplay-hud/condition-status-clarity`
- Baseline: `c7cb1774abc256542694472bee815b3cde22fdb9`
- Risk: LEVEL 4 for the subsequent explicitly approved collapse-rule adjustment; original HUD work was LEVEL 2.
- Starting tree: local changes in `docs/CONTENT_LOG.md` and the player scene's enabled debug-needs override.
- Status: PASSED — NEEDS HUMAN REVIEW for tested HUD behavior; full sleep/collapse playtest remains unverified.

## Scope and acceptance

Show Energy, Focus, Satiety, and EXP using the existing pixel font. Keep all condition bars full when healthy. Bind warning colors to Player severity methods, keep HUD free of explanatory notes and text notifications, preserve EXP and Nightmare visibility, and disable the local needs-testing override. Hunger must affect collapse only indirectly through the unchanged Focus drain.

No changes to condition drain, thresholds, Focus formula, economy, save data, autoloads, project settings, or game design documents. No worksite implementation. The protected agent-control pack was read but not modified; this report records the run outside it.

## Changes

- Modified `scenes/ui/bottom_hud/bottom_hud.gd`: positive-facing names, severity-based colors, bottom-relative drawer positioning and hiding. No help notes or text alerts remain.
- Modified `scenes/player/player.gd`: remove hunger as a direct collapse trigger, as explicitly requested.
- Removed the local `debug_disable_player_needs = true` override from `scenes/player/player.tscn`, returning this file to the committed baseline (default false).
- Added `scenes/test_scenes/condition_hud_regression_test.gd` and its scene.
- Added this report. No files deleted or renamed.
- Preserved unrelated `docs/CONTENT_LOG.md` edits without staging them.

## Validation

- Headless ConditionHUDRegressionTest: PASS. Covers healthy bar mapping, configurable severity, warning/critical colors and recovery, absence of HUD notes/alerts, active minute-based needs, eating not refilling Focus, drawer positioning/open/close/reopen, EXP binding, Nightmare visibility callbacks, zero Satiety without direct collapse, retained Energy/Focus triggers, and unchanged hunger Focus penalty.
- Graphical test run at 1200x675: exit 0; viewport screenshot inspected for status labels/help/alert layout. Corrected initial helper-label width after font layout.
- Main scene startup, headless, 120 frames: exit 0; no new blocking script errors observed.
- Git diff whitespace check: PASS.
- Existing shutdown warnings persist: 15 Dialogue Manager script resources retained.

## Limitations

The Game Director reported normal use working safely before requesting the hunger-trigger change. No complete manual Nightmare escape/return test was observed; visibility callbacks and collapse predicates are tested, not the entire gameplay sequence. No Android validation. Commit and push authorized by the Game Director; merge remains human-only.
