# Food and a full Belly — 1 November 2026

Branch `feature/gameplay/character-needs-20261101`; starting commit
`bb432810346cc663341a857f3374d242b27200a2`; starting working tree clean.

The Game Director approved preventing the player from eating when Belly is
full, even if Energy is low. The existing inventory food action is disabled
at the player's minimum Hunger, and an execution-time guard prevents an item
or Energy gain if the condition has changed. Multi-item consumption stops as
soon as Belly reaches that minimum. The exact internal minimum is used rather
than a rounded HUD percentage, so a slightly hungry player may still eat.

Food effects, condition rates, sleeping, collapse, city food storage and daily
rations are unchanged. No new feedback text was added.

Godot 4.5.1/Linux headless checks passed for all eight current foods at full
Belly, repeated attempts, the disabled inventory action, both meters full,
near-full and batch consumption, the existing date and drumstick effects,
full Energy, a configured Hunger minimum, and sleep. Date pickup, city food
stock and daily rations, inventory modal/feedback, status Tab, player Energy,
and city sleep/save tests also passed. The sleep/save fixture deliberately
emits a warning while checking preservation of an invalid checkpoint.

`CityFoodUITest` failed while opening the physical storage interaction; the
same failure was reproduced on the clean starting commit under the same
Godot version. Human gameplay and other platforms have not been tested.
