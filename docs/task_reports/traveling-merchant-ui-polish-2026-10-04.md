# Traveling merchant UI polish — 2026-10-04

Branch: `feature/economy/traveling-merchant-mvp`.
Baseline: `903d5b16f2abef670675e1374c6122ae89fe04cb`.
Starting working tree: clean. Risk: LEVEL 1 — presentation-only update.

## User-requested scope

- Preserve native item pixels rather than scaling 16x16 textures to 11x11 or 18x18.
- Remove B/S price abbreviations and the Trader Qty heading from the catalog.
- Use the existing small Shekel icon for monetary displays.
- Reuse the existing close-icon component with normal/hover/pressed states.
- Use the established selection-frame asset to identify selected/hovered items.
- Align panel margins, rows, detail fields and actions on the logical pixel grid.

The merchant ledger, schedule, stock, prices, inventory API and world integration
are outside this revision. No new assets, dependencies or project settings are needed.
Implementation is scoped to the merchant UI script and scene; this report records
review and validation separately from the original MVP checkpoint.

## Validation

Status: PASSED — NEEDS HUMAN REVIEW.

- Godot 4.5.2, GL Compatibility, Xorg/Mesa llvmpipe; 1200x675 window and the
  unchanged 400x225 logical viewport.
- Existing `TravelingMerchantAccessTest`: PASS after final layout changes. It
  exercises BUY/SELL controls, opening/closing, live balances, scene reload,
  selection stability, departing merchant, input guards and long balance bounds.
- Inspected BUY, SELL/sold-out and long-balance screenshots. The final 376x209
  window has an integer-centered origin and 16px outer content margins. Columns
  use 192px + 8px gap + 144px; 20px catalog rows fit all six current offers.
- Item textures render at native 16x16, coins at 8x8, with nearest filtering.
  The close control instances the shared 8x8 TextureButton with its existing
  normal/hover/pressed textures. The selection frame reuses the workshop atlas.
- The first launch caught a partially written script during editing; a subsequent
  launch encountered the old test process's occupied MCP port. After that process
  exited, the completed script/scene passed. Final run has no script or resource
  errors; the known virtual-driver V-Sync warning remains.
- `git diff --check` passes. Only the two merchant UI files and this report change.

Backend economy and balance remain as previously tested in the MVP report. This
revision does not claim new Android, hardware or long-session validation.

## Follow-up: project quantity panel and hover-only rows

The Game Director subsequently requested removing the selector frame and using
mouse hover only. Catalog buttons now use the shared HudShortcutButton hover and
pressed styles with an empty idle background and no persistent selection frame.
The active item remains available in the detail panel. Like existing work-order
cards, row keyboard focus is disabled so clicking does not leave a focus outline.

The quantity LineEdit now reuses the project's textured HudShortcutButton panel
for normal/read-only states and removes the engine's default white focus outline.
The existing quantity editing and SpinBox behavior are preserved. The final
TravelingMerchantAccessTest passes graphically on Godot 4.5.2; the resulting panel
was inspected, with only the known virtual-driver V-Sync warning. No economic
logic or amounts change.
