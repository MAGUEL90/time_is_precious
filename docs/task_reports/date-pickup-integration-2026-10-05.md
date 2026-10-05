# Reusable date pickups — 2026-10-05

Status: PARTIAL — implementation and behavioral checks pass; shutdown warning and Godot 4.5.x/manual validation remain.

Branch: `feature/item/food-mvp`. Baseline: `54317e3db15ba41e28b7b05e3b7235c7ac5b5877`. Starting tree clean. Risk: LEVEL 2, limited integration explicitly requested by the Game Director.

Reuse the existing pickup scene for the three authored date sprites. Add an optional `world_texture` on PickUpItem; absent overrides retain the item icon. Bind each authored pickup to `date_cluster`, keeping its root position and the existing default quantity of one. Inventory/popup icons and consumption data remain unchanged. Standard pickup icon offset and idle animation apply.

Scope: pickup_item.gd, content_scene.tscn, focused regression fixture and this report. No new production pickup scene, settings, autoload, addon, balance, tree, terrain or unrelated layout changes. Editor-generated addon import changes were discarded. No control-pack changes.

Validation on available Godot 4.6.3:
- Editor import and project startup smoke: completed without script errors.
- DatePickupTest: PASS. Loads actual ContentScene, verifies all three reusable instances, separate world/inventory textures, full-inventory rejection, player interact dispatcher, repeated-call protection, three-item collection, delayed removal, legacy apple texture fallback, and existing date consumption (one removed, hunger reduced by 0.04).
- git diff --check: passed. Implementation diff reviewed against the user baseline.
- Test shutdown emits an ObjectDB leak warning. Verbose diagnostics identify GDScriptFunctionState (`play_pickup`) and SceneTreeTimer. Waiting before teardown did not eliminate it; source remains unresolved. Startup smoke does not emit this warning.

Untested: Godot 4.5.x, graphical/manual playtest, Windows and Android. No claim of full QA completion.

This integration uses authored pickups only. They reappear on scene reload under the existing scene lifecycle. Automatic spawning, timed respawn and collected-state persistence are not implemented; rates and persistence behavior still require design decisions. No merge performed.

## Follow-up: random refill

The authored-only limitation above is superseded by `date-respawn-2026-10-05.md`: pickups now use per-tree session stock and a random 1–18 game-hour refill timer.
