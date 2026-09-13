# Unused assets older than one month

Audit date: 2026-09-07. Cutoff: before 2026-08-07 00:00 Asia/Jakarta.
Scope: current files under `assets/`, including PNG, GIF and TTF; generated import sidecars
are checked for UIDs, not counted as separate assets. There are no current JPG/JPEG files.
Addon assets are outside this game-asset cleanup scope.

Both filesystem modification time and latest Git change must precede the cutoff. Scanned
project source, resources, scenes (including test scenes), and documents by path, filename,
and import UID. Inspected dynamic resource loaders; their referenced resources were included.
Git internals, `.godot` cache and an asset's own import metadata are not evidence of usage.

## Complete current candidate list

| Path | Last modified (Jakarta) | Latest Git change (Jakarta) | Size |
| --- | --- | --- | --- |
| `assets/characters/gabbi/gabbi_hair/gabbi_hair_walk.png` | 2026-07-29 05:46 | 2026-07-29 05:32 | 624 bytes |
| `assets/temporer/game/tile_sets/Bitmask references gif.gif` | 2025-11-19 06:33 | 2025-11-14 07:30 | 353,038 bytes |

No project references were found for these two files. Gabbi's visual currently references
`gabbi_hair_idle.png`; the walk PNG's own import UID is not used elsewhere. The GIF is a
bitmask reference image, not a runtime texture found in the scanned resources.

The initial audit produced a review list. In the follow-up, the Game Director explicitly
authorized deletion. Both listed assets and the PNG's `.png.import` sidecar were removed
after rechecking references. The GIF had no import sidecar. Byte-verified recovery copies
are in `C:/Users/Hendro/AppData/Local/Temp/tip-clay-prep-20260907/removed-assets-one-month/`.
The counts below describe the pre-deletion audit, not the remaining filesystem.

## Retained / previously removed

Of 190 current assets, 183 have references and seven have none. Only the two above pass the
one-month age rule. These five unreferenced PNGs are newer and remain outside that rule:

- `assets/ui/ui_icon/left_arrow_icon.png`
- `assets/ui/ui_icon/minus_icon.png`
- `assets/ui/ui_icon/separator_icon.png`
- `assets/ui/ui_icon/worker_icon_active.png`
- `assets/ui/ui_icon/worker_icon_inactive.png`

Their filesystem modification dates are 2026-08-19 or 2026-08-21; their latest Git change is
2026-09-06. The project's TTF font has live theme/UI references and must be retained.

The 21 old PNGs removed in the previous task are already absent and are not current deletion
candidates. Their exact names remain in `clay-prep-removed-assets.json`.

## Next clay checkpoint

Use the Game Director's current naming: `test_scene_clay_worksite.tscn` / `.gd`.
The renamed fixture passes the two-marker, movement and inventory pause/resume checks.

The next checkpoint is to agree on the worksite contract before adding stock/work mechanics:

| Decision | Proposed direction; not approved tuning |
| --- | --- |
| Primary input | Quantity, with duration calculated and previewed |
| Site stock | Independent fractional stock per site; capacity range, starting stock and recovery days TBD |
| Cycle reset | Fixed capacity/rate during refill; settle full-then-depleted behavior and repeated partial harvesting |
| Work duration | Base game minutes per clay TBD; settle rounding before equipment bonuses |
| Equipment | Choose item/slot/bonus; sample at start; no durability system in this task |
| Needs | Existing clock drain exactly once; extra work fatigue TBD |
| EXP | Personal EXP for completed, received output; amount TBD; preserve current cap |
| Interruption | Settle partial output, cancellation, full inventory and collapse/scene-change behavior |

Per the start brief, gameplay balancing requires explicit agreement. The existing fixture
still has no stock, work reward, EXP payout, or invented numerical defaults.
