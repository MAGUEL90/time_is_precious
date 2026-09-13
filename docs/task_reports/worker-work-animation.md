# Worker work animations

2026-09-09. Authorized asset/animation integration. Existing local changes preserved.

- Added native editable SpriteFrames animations in base_worker_visual.tscn: 8 body and 16 head clips, each looping through 8 frames of 32x32. First atlas row is right, second left.
- Naming follows existing convention: `light_work_right`, `base_light_work_right`, `tired_light_work_right`, with all four tones and both directions.
- Sources are the user-provided work PNGs. Body tan intentionally references the existing `tan/warm.png`; no asset renamed or edited.
- BaseWorkerVisual accepts work as default_action or via play_visual, using its existing animation speed. Head falls back to base for actions without the requested expression.
- Hand is hidden for work. Clothes/hair/accessories show only when matching work clips exist, preventing unrelated walk frames from overlaying the work motion. The provided asset set does not include these work layers yet.
- F6 preview: scenes/test_scenes/test_scene_worker_work_animation.tscn. Shows all 16 tone/expression/direction combinations.
- Automated preview test covers frame counts, atlas bounds, playback progression, body/head synchronization and returning to idle/walk with clothing/hair restored. PASSED graphically at 1200x675. Screenshot visually inspected. Main project smoke exit 0; diff check clean. Existing certificate store and exit resource warnings remain.
- This prepares reusable visual animations; automatic worksite actor spawning, commuting and linking actor animation to Daily activity are not implemented here.

Changed: scenes/worker_visual/base_worker_visual.gd and .tscn. Added preview .gd/.tscn and this report.
