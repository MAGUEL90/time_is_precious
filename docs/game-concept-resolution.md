# Time is Precious — Resolution and Platform Display Direction

Last updated: 2026-06-01

This document is part of the **Time is Precious** game concept documentation.
It defines the current target resolution, aspect ratio, platform display direction, and pixel-art readability rules.

## Current Decision

The current base/design resolution should remain:

```text
1280 x 720
```

Aspect ratio:

```text
16:9 landscape
```

Primary platform direction:

```text
PC first, Android landscape compatible
```

## Reasoning

Time is Precious is a 2D top-down management RPG with resource management, worker delegation, production chains, storage, city needs, and UI-heavy decision making.

A landscape layout is currently the safest direction because it gives enough horizontal space for:

- map visibility
- time/day UI
- inventory and storage UI
- resource stock display
- worker status
- process status
- job board / worker hub UI
- city condition indicators

Portrait can be considered later only if the game design changes significantly toward a simpler mobile-first layout.

## Prototype Rule

For the current prototype, do not change the base resolution away from 1280x720 unless there is a strong technical or gameplay reason.

The current goal is to stabilize the playable core loop first:

```text
Gather resource
↓
Store resource
↓
Process resource
↓
Produce output
↓
Use output for progression
```

Resolution should support this loop, not distract from it.

## Scaling Direction

Recommended Godot display direction:

```text
Base viewport: 1280x720
Aspect ratio: 16:9 landscape
Stretch direction: support wider screens without cropping important gameplay/UI
```

For wider PC or mobile screens, extra side space is acceptable if the layout remains readable and does not crop important UI.

Avoid:

- cropping core UI
- forcing portrait layout
- making pixel assets too small to read
- redesigning the whole UI before the core loop is stable

## Pixel Art Readability Rule

The project still prioritizes small efficient pixel art, especially 16x16 where possible.

Readability should be handled through:

- camera zoom
- tile size consistency
- UI scale
- icon size
- clean silhouettes

Do not solve readability by making every asset larger too early.

Recommended working direction:

```text
Tile/resource scale: small and efficient
Character asset direction: 16x16 or close to it when readable
UI icons: can use 32x32 when needed
Camera zoom: adjusted for comfort
```

## Mobile Direction

Mobile support should be treated as:

```text
Android landscape compatible
```

Not:

```text
Android portrait-first
```

Reason:
A management RPG needs space for map, systems, and UI. Portrait would likely create pressure to simplify or redesign the game around vertical mobile behavior.

## Current Design Lock

Until the core loop becomes stable, the working resolution decision is:

```text
Resolution: 1280x720
Aspect ratio: 16:9
Orientation: Landscape
Platform target: PC first, Android landscape compatible
```

Future changes must explain:

1. Why 1280x720 is no longer enough.
2. What gameplay problem the new resolution solves.
3. How UI readability improves.
4. How pixel art readability is preserved.
5. Whether PC and Android can still share the same core layout.
