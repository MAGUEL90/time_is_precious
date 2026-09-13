# Worker Hub Tools layout and cart poses

Date: 2026-09-12
Scope: worksite test fixture, Worker Control UI, and shared worker animation support.

## Approved presentation

- Tools uses a four-column scrollable worker-card grid, with a separate exclamation control for Details.
- The right-hand heading uses the selected worker's name. Tool names appear in the equipment picker; no new tool-effect values are invented.
- Primary presents the cart, Secondary presents the current optional tool. The two Accessories slots are placeholders.
- One physical tool unit occupies each implemented slot. Units cannot be shared. Existing busy and mandatory-cart assignment locks remain in effect.
- Worker data provides the visual profile for the preview. Synthetic workers use the existing default profile.
- Cart artwork in the UI is a placeholder. Imported character poses are separate from a world cart sprite.

## Data adapter

`clay_worker_management.gd` supplies `tool_id`, `slot` and `can_unequip` for each tool unit, and a `visual_profile` dictionary for each worker. Slot mapping is provisional for the two current tool types: cart to Primary, other existing tools to Secondary. Accessories do not allocate equipment yet.

## Cart animation

- Moving Haulers use `push_cart`, waiting Haulers use `idle_cart`. The supplied right-facing frames are mirrored for left movement.
- Push body/head/hand sheets contain four 32 x 32 frames; idle body/head contain two frames. Idle does not show the push-only hand layer.
- Light is the only supplied skin tone. Other tones keep their normal walk/idle animations. Missing cart-specific clothes, hair and accessories are hidden rather than mixed with incompatible poses.
- The Hauler demo's two synthetic citizens now have explicit light profiles for visual testing; global/default citizen profiles remain unchanged.
- Missing artwork: a separate world cart sprite, matching cart clothing/hair/accessory layers, and other skin tones. The UI temporarily uses the existing grain-sack icon labelled Cart.

## Editable scenes

- `scenes/test_scenes/ui_sandbox/worker_control/worker_control.tscn`: Tools grid area, name heading, slot arrangement, preview anchor and equipment picker.
- `scenes/test_scenes/ui_sandbox/worker_control/worker_tool_card.tscn`: reusable portrait card and exclamation button.
- `scenes/worker_visual/base_worker_visual.tscn`: cart SpriteFrames and animation playback exports.

Cards use 28 x 28 cells, four columns; character preview uses integer 3x scale. Slot picker replaces the right-side preview while open, with Back/Escape returning to it. Details from a card returns to Tools. No tooltip is added.

## Verification

- WorkerControlTest PASS: portrait selection, exclamation Details/Back, four-column grid, real Equip/Unequip actions, exclusive slot ownership, busy locks, Fire and camera-only Go to.
- WorkerCartAnimationTest PASS: supplied frame counts, both directions, fallback and clearing mirrored state on normal animation.
- WorkerWorkAnimationTest PASS: existing work/tired playback regression.
- ClayWorksiteHaulerTest PASS: actual travelling actor uses push_cart; delivery conservation, return on rejected delivery, removal and shift-end behavior retained.
- ClayWorksiteDailyTest PASS. Main headless launch exited 0. Git diff whitespace check passed.
- Rendered Tools, Hauler equipment, picker, cart pose sheet and world Hauler cycle inspected.
- Existing certificate-store and shutdown ObjectDB/resource warnings remain. No new blocking runtime errors remain.

Manual check: F6 on `test_scene_clay_worksite_hauler.tscn`, K then Tools. Select a worker card; use its exclamation for Details; open Primary/Secondary to manage tools. F7 advances 30 minutes to inspect the Hauler cycle. `test_scene_worker_cart_animation.tscn` provides a separate four-pose visual check.

Work split: Astra Medium handled data adapters, fixture profiles, regression updates, final layout corrections and rendered verification. Luna XHigh implemented the initial Tools UI/reusable card and shared cart animation integration with targeted tests.

## Follow-up visual fixes

- Portrait cards now display the original 11 x 15 image without fractional resizing. The exclamation uses its native 4 x 11 texture through TextureButton.
- Empty slots use `plus_icon_3.png`.
- Shared worker idle playback is 0.333333 FPS, one third of its previous speed. Walk/work speeds are unchanged.
- Equipped cart previews now request idle_cart. Equipped Haulers also keep cart poses during ordinary idle/walk travel and roaming.
- Added `scenes/worker_visual/cart_placeholder.gd`, a temporary pixel-aligned wooden cart drawing attached to push_cart/idle_cart actions, mirrored with facing. It remains visible even when an unavailable skin-tone pose falls back to walk/idle. Final cart art is still replaceable.
- Verified WorkerControlTest, WorkerCartAnimationTest and ClayWorksiteHaulerTest all pass; inspected UI preview and actual hauling render; main launch exits 0 and whitespace check passes. Existing certificate and resource shutdown warnings remain.
- This follow-up was implemented and verified by Astra Medium without subagent delegation.

## Corrected preview scope and supplied cart art

- Restored shared/world idle to 1 FPS. Only the Worker Hub Tools preview divides its instance idle speed by three before playback.
- Removed the automatically introduced hair/clothing from synthetic demo profiles and unlinked preview defaults. Existing explicitly configured citizen/player profiles are preserved.
- Disabled Button icon expansion, so `plus_icon_3` renders at its native 16 x 16 canvas rather than shrinking to available text space.
- Replaced and removed the procedural cart placeholder with `worker_cart.tscn`, using the user-provided `tools/push_cart/push_cart.png` and `tools/idle_cart/idle_cart.png`: four and two 32 x 32 frames respectively. The cart is aligned to the character sheet origin, mirrored consistently, and restarted with body clips on action/direction changes.
- `worker_cart_icon.tres` crops the actual cart artwork for the equipment slot; the previous sack placeholder is no longer used there.
- WorkerControlTest, WorkerCartAnimationTest and ClayWorksiteHaulerTest pass; cart/body synchronization and world-vs-preview idle scope are checked. Main launch exits 0. Tools and world renders inspected; existing certificate/resource shutdown warnings remain.
