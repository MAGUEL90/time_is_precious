# Overflow manual test preparation

2026-09-07 — fixture-only setup requested by the user.

Replaced the previous Fatigue 0.88 collapse-test setting with 0.5.
The root's Prepare Overflow Test option is enabled. When launched directly with F6,
it sets Fatigue 0.5, Hunger 0, Focus 1 and fills available capacity with clay, leaving
room for two clay. It does not clear pre-existing items or change inventory capacity.
Fresh launch: 48 clay, weight 96/100.

Manual test: F6, approach a site, E, 1h, Start Work.
Expected: six clay earned; two enter inventory (50 clay, 100/100), four fall to ground.
Repeat one hour with the full bag: all six new clay fall to ground.
Trying to collect while full leaves the stack intact. Free enough space for the whole
stack, then E collects it once. Disable Prepare Overflow Test for normal fixture starts.

Preparation is skipped for nested regression fixtures. Gathering regression includes
the preset's quantity/condition assertions and existing full/partial overflow checks.
An initial harness attempt assigned a nested fixture as current_scene; Godot rejected it.
The harness now mounts that fixture under the SceneTree root before testing F6 preparation.
No production settings, gameplay balance, old local work, commits or merges changed.
