# Player condition HUD — 1 November 2026

Branch `feature/gameplay/character-needs-20261101`; starting commit
`b8f509f4949c0b1b6d15b3cebba0cb45b6b8fdfa`; starting working tree clean.
This is a limited UI integration of the Game Director's approved presentation.

Energy and Belly use the existing condition icons and bars at the top left.
Their names appear only on the respective icon hover. EXP remains on the Tab
drawer. The existing inverse values are unchanged: a full Belly means well fed,
and full Energy means rested. The worksite preview uses the same Belly name.

The old warning was a color on a normally hidden drawer. For the visible bars,
20% or less remaining is a provisional visual warning threshold. The affected
bar slowly changes between red shades over a 2.4-second cycle, including its
empty track at zero; recovery restores the normal colors. This threshold does
not change the player's gameplay critical threshold or any condition mechanics.
Opening a paused modal clears the Tab drawer and hover labels; a Tab release
received by a dialog can close the drawer without requiring another key cycle.
Nightmare keeps the existing HUD visibility behavior.

## Verification

- Godot 4.5.1/Linux: project import and main-scene launch passed.
- `StatusTabTest`: passed on the main map and home interior, including repeated
  Tab, actual icon mouse motion, inventory interruption, dialog, and Nightmare.
- `ConditionHUDRegressionTest`: passed, including both 20% boundaries, zero,
  warning animation, recovery, eating, and sleep.
- Clay worksite inspection and Nightmare, dialogue runtime, inventory modal and
  feedback lifecycle, player energy output, and city sleep/save tests passed.
  The sleep/save test intentionally emits a warning while checking preservation
  of a corrupt checkpoint.
- `ContentWorksitesIntegrationTest` failed its daily-hauler assertions and a
  follow-on dictionary access. The same failures were reproduced on the clean
  starting commit with the same engine and isolated user-data settings.
- Godot 4.5.1 GL Compatibility rendered at the project's 400×225 viewport and
  1200×675 integer-scaled window. Normal, both hover states, and two critical
  phases were inspected. The virtual display reported unsupported V-Sync.

Human visual review and Windows/Android validation remain outstanding.
