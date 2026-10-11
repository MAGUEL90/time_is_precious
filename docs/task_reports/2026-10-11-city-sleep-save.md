# Sleep autosave and City Hub Shelter

Branch: `feature/time-world/city-save-load`.
Baseline: `5e0daf242898055caadf0a0ffa3b5fceabf8804a` (manual city checkpoint).
Starting working tree: clean. Risk: **LEVEL 3 — SYSTEM CHANGE**, authorized by
“sebenarnya konsep save ini aku ingin terapkan saat player sedang tidur” and the
request to include Shelter in Supply. Scope is the existing city/home pair and
existing needs data. Status: **PASSED — NEEDS HUMAN REVIEW**. Human merge: pending.
Agent: Codex root integration/review, with a narrow delegated Shelter UI helper.

## Result

Successful bed sleep writes the single checkpoint after the existing time skip,
condition recovery and fade finish. The bed displays `Game saved` or `Save failed`
in the existing six-pixel font. Entering home, refused sleep and Collapse do not
save. Loading a sleep checkpoint returns the player awake at the saved home
position, with the saved clock and daily sleep latch. Manual City Hub Save/Load
remain available for playtesting; menu-level Continue is not included.

Supply now displays Shelter capacity, resident need and shortage/spare/covered
status with the existing house icon. These values come from CityStockManager and
CitizenNeedsManager. Shelter was already settled as a daily need; this task adds
its missing presentation without changing housing, satisfaction or balance.
Supply and Management retain the same 300 x 196 logical-pixel frame.

## Ownership and compatibility

CitySave remains under the existing WorkStateRuntime host. To preserve city jobs
and in-flight cargo while the player sleeps in the separate home scene, SceneDoor
hands the existing live worksite subtree to CitySave before the city is freed.
Its rendering, input and physics stop, while its existing minute-signal scheduler
continues production and hauling. Returning adopts that state into the new map
projection, then disposes of the previous projection without releasing adopted
workers. City drops and persistent plot-state references remain city-owned.
A failed scene change can restore the original worksite parent and visible layers.
No additional production simulator, autoload or project setting is introduced.

Schema version 2 adds only the fixed `city`/`home` location header. The slot path
stays `user://city_save/checkpoint_v1.json` so existing saves are found. Version-1
city checkpoints are explicitly accepted and upgraded on the next successful save.
Unknown versions and corrupt files remain protected. Save data cannot choose an
arbitrary scene/script/resource path. Home Load validates the complete document
from the city, freezes clock and raid processing before the deferred transition,
and uses the normal fade and spawn placement. It does not repeat sleep, accrue
offline production or advance another minute/hit during Load.

## Changed files

Modified:
- `scenes/sleep_spot/sleep_spot.gd`
- `scenes/components/scene_door/scene_door.gd`
- `scenes/content_scene/worksites/content_worksites.gd`
- `scenes/new_scenes/save_game/city_save_state.gd`
- `scenes/new_scenes/save_game/city_save_store.gd`
- `scenes/raid/raid_ui.gd`
- `scenes/test_scenes/test_scene_city_save.gd`
- `scenes/test_scenes/test_scene_raid_ui.gd`
- `scenes/test_scenes/test_scene_transition_timing.gd`
- `ARCHITECTURE.md` and `ROADMAP.md`

Created: `scenes/test_scenes/test_scene_city_sleep_save.gd`, its `.gd.uid` and
`.tscn`, and this report. No files deleted or renamed.

The transition fixture previously added a second NightmareWorld even though the
main map already authored one at the baseline. Player entered the first world
while the fixture waited on the inactive duplicate. The fixture now observes the
authored world; production Nightmare behavior was not changed.

## Verification

Godot 4.5.2 on Linux, GL Compatibility, 400 x 225 logical viewport and 1200 x 675
native window. Final editor import/parse exited successfully without script errors.

- Actual-bed round trip passed: a real hired worker and Hauler, outbound cargo,
  paid wall construction, city drops, seven-hour sleep, completed recovery and
  visible save feedback. During sleep construction completed, cargo delivered,
  and daily production continued. Returning retained all work state, conserved
  72 wood units and restored four dropped clay exactly once.
- Refused same-day sleep neither rewrote the file nor advanced time. Entering
  home alone did not create a checkpoint. Failed-departure rollback preserved
  jobs and cargo. The existing external/corrupt-file boundary blocked overwrite.
- Separate write/read processes passed: loading from a fresh city returned to
  the saved home, awake and movable, with every encoded owner and home position
  matching disk. Counts, IDs and RNG values are exact; float comparisons allow
  1e-10 JSON roundoff. Dedicated test slots leave the player's slot untouched.
- Main-city checkpoint regression passed, including explicit version-1 loading
  and version-2 rewrite, invalid-file preservation, active raid and loot state.
- Economy checkpoint regression passed: production orders, fees, output, hired
  citizens, equipment, site jobs, cargo and delivery remain coherent after Load.
- Raid UI and native City Hub layout checks passed: Shelter icon/text, daily and
  event results fit above the footer; both tabs retain their fixed frame, also
  during the dense construction-plus-attack state. Screenshots reviewed in empty
  and populated-city states.
- Scene transition timing and player action-lock regressions passed, including
  sleep/collapse fades and the existing authored Nightmare flow.
- Final diff reviewed. Editor-generated changes to `project.godot` and three
  Dialogue Manager SVG imports were excluded using the user's explicit cleanup
  authorization. No gameplay balance, addons or project settings changed.

Evidence: `/tmp/city-sleep-verified-*.log`,
`/tmp/city-sleep-final-city_save.log`,
`/tmp/city-sleep-final-city_sleep_save-write.log`,
`/tmp/city-sleep-final-city_sleep_save-read.log`,
`/tmp/city-sleep-final-city_progression_hub.log`,
`/tmp/city-sleep-check-1-raid_ui.log`, `/tmp/city-sleep-editor.log`.
Screenshots: `/workspace/scratch/sleep-save-home.png` and
`/workspace/scratch/city-shelter-supply.png`.

The existing godot-mcp bridge still reports the environment's localhost port 9877
listener error; native graphics reports unavailable VSync. Tests pass despite
those environment warnings. Final sleep tests have no leaked-ObjectDB warning.

## Playtest and limits

Run the main city, enter the player home and sleep at the bed with E. After waking,
look for `Game saved`. Exit home and use C > Load to restore that checkpoint;
the same works after restarting the game. Supply in City Hub now shows Shelter.

One slot is shared by sleep autosave and the retained manual Save button. Saves
from arbitrary other maps, title-menu Continue and multiple slots remain follow-up
work. Running home alone with F6 has no city runtime and does not create a city
checkpoint. Windows and Android were not executed here; Windows playtest is the
next human acceptance check. Physical power-loss durability was not fault-injected.
