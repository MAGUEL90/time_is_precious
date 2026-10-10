# City Hub layout polish — 2026-10-11

Branch: feature/time-world/city-progression. Baseline: 5282518; starting tree clean.
Scope: requested UI cleanup only, no progression/raid balance changes.

- Removed the lootable-item count and watchtower status sentence from Management. The detected-raid Inspect action and its watchtower permission checks remain.
- City Hub uses one 300x196 logical size in Management, Supply and last-raid view. Removed tab/phase-specific resizing.
- Supply textures are native 16x16 pixel assets; render centered without scaling inside their 24x24 layout cells, with nearest filtering. The previous aspect-fit stretching to 24 pixels produced uneven pixel sizes.

Verification:
- CityProgressionHubTest PASS in native Godot 4.5.2 GL Compatibility (400x225 logical, 1200x675 window). Both tab frames have exactly matching size and position; dense attack/construction content remains inside the frame. Level-up/reload/actual breach checks also passed.
- RaidUITest PASS, including Inspect gating, intelligence clearing and report navigation. Assertions referring to removed status strings now check the retained inspection state directly.
- Reviewed captures of Management, Supply and active-attack layouts; git diff --check PASS.
- Existing virtual-display unsupported V-Sync warning only. No settings, assets, dependencies or gameplay rules changed.

Status: PASSED — NEEDS HUMAN REVIEW.
Suggested next feature: session save/load for city level/progress, storage, wall projects and raid schedules, before longer balance playtests. Not implemented in this UI task.
