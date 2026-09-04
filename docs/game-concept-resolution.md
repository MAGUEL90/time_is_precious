# Time is Precious — Resolution and Platform Display Direction

Last updated: 2026-09-05

This document defines the current display, pixel-art readability, and platform presentation direction for **Time is Precious**.

## Important terminology

The project uses two different resolution concepts and they must not be confused:

1. **Logical rendering viewport** — the internal pixel-art coordinate space used by Godot.
2. **Presentation/output size** — the window or device resolution the player sees.

Changing one does not automatically mean the other should change.

## Current implementation baseline

Current `project.godot` settings use:

```text
Logical viewport: 400 x 225
Development window override: 1200 x 675
Stretch mode: viewport
Stretch aspect: expand
Scale mode: integer
Renderer: GL Compatibility
2D transform pixel snapping: enabled
```

The logical viewport is intentionally small for pixel-art readability and integer scaling. It is a protected project-wide setting and must not be changed casually.

## Presentation direction

Current presentation direction remains:

```text
Aspect ratio: 16:9 landscape
Primary platform: PC first
Secondary target: Android landscape compatible
Reference PC presentation: 1280 x 720 class or higher 16:9 output
```

`1280 x 720` is a presentation/reference target, not the current logical Godot viewport.

This distinction resolves the older ambiguity where 1280x720 was described as if it were the internal base viewport.

## Why the logical viewport is smaller

Time is Precious uses small pixel art and UI-heavy management screens. A low logical viewport with integer scaling helps preserve:

- sharp pixel edges
- consistent world/UI scale
- readable silhouettes
- predictable UI spacing
- stable pixel-snapped movement and presentation

Do not increase the logical viewport merely to match a desktop window resolution.

## Prototype rule

Until the playable core loop is stable:

- Keep the current logical viewport unless a tested gameplay or presentation problem requires change.
- Do not redesign the whole UI around a new resolution without a dedicated task.
- Treat changes to stretch, scale mode, pixel snapping, renderer or viewport as project-setting changes requiring explicit approval.

## Scaling direction

The game should remain readable across common landscape outputs while preserving the logical pixel grid.

For wider PC/mobile screens:
- extra horizontal space is acceptable when layout remains readable
- core UI must not be cropped
- important controls must remain reachable
- integer scaling should be preserved where practical

Avoid:
- forcing portrait layout
- stretching pixel art non-uniformly
- changing logical viewport as a quick fix for one panel
- making every sprite larger to solve readability

## Pixel Art Readability Rule

The project continues to favor small efficient pixel art, often around 16x16 where readable.

Readability should be handled through:
- camera composition
- tile-size consistency
- UI scale and layout
- icon sizing
- clear silhouettes
- integer scaling

UI icons may be larger than world sprites when needed for clarity.

## Android direction

Android support means:

```text
Landscape-compatible gameplay and UI
```

It does not mean:

```text
Portrait-first mobile design
```

Desktop testing alone is not proof of Android readiness. Touch/input, safe-area/layout behavior, performance, and device output must be validated separately before mobile compatibility is claimed.

## Current design lock

Working display decision:

```text
Logical viewport: 400 x 225
Development window: 1200 x 675
Reference presentation direction: 16:9, 1280 x 720 class or higher
Orientation: Landscape
Platform target: PC first, Android landscape compatible
```

Future display changes must explain:
1. What concrete gameplay or presentation problem exists.
2. Why the current logical viewport/scaling cannot solve it.
3. How pixel-art readability is preserved.
4. How existing UI scenes are affected.
5. Whether PC and Android can still share the same core layout.
6. What regression tests were performed.