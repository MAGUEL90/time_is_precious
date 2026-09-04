# TIME IS PRECIOUS — TECHNICAL RULES

Status: TEMPLATE — NOT ACTIVE

Purpose: keep AI-written Godot changes understandable, local, reversible and consistent.

## Existing architecture first

Inspect the project before adding managers, event buses, base classes, autoloads, folder conventions or patterns. Reuse established architecture when suitable. Do not rebuild working systems for style preference.

Authoritative architecture reference: `ARCHITECTURE.md`.
Technical domain / branch reference: `docs/root-branch-map.md`.

## Locality

Prefer the smallest correct change. Do not refactor unrelated files, rename unrelated nodes, reformat large untouched sections, clean the repository as a side effect, or convert architecture during a feature task.

## Preserve public behavior

Preserve existing signals, public methods, resource schemas, relied-upon node paths, save fields, input actions and scene contracts unless explicitly authorized.

## Godot / GDScript baseline

- Engine family: Godot `4.5.x`.
- Current project feature level: `4.5`.
- Current renderer: GL Compatibility.
- Follow surrounding GDScript style unless a dedicated coding-standard document is introduced later.
- Use tabs where surrounding project code uses tabs.
- Prefer typed variables, typed parameters and typed return values when practical and consistent with nearby code.
- Use descriptive names and focused functions.
- Avoid unexplained magic values; gameplay/balance values must come from approved design or existing authoritative data.
- Avoid unnecessary `_process()` / per-frame work.
- Connect/disconnect signals safely and avoid duplicate connections on repeated UI open/close cycles.
- Parser errors, invalid resources, broken node paths and missing required autoloads are blocking defects.
- Do not suppress warnings or remove checks merely to make output appear clean.

## Scene safety

Preserve unrelated scene nodes/properties. Avoid broad node-path changes. Verify dependent scripts after node renames. Prefer targeted edits over replacing manually-authored scenes wholesale. Experimental UI remains in the approved sandbox until integration is authorized.

Approved first pilot sandbox after activation:

`res://scenes/test_scenes/ui_sandbox/`

Production UI remains under established `res://scenes/ui/` conventions.

## Display / pixel-art safety

Current repository settings use:
- logical viewport `400 x 225`
- development window override `1200 x 675`
- viewport stretch
- expand aspect
- integer scale mode
- 2D transform pixel snapping

Do not change logical viewport, stretch, rendering method, pixel snapping, orientation direction or platform display settings unless the task explicitly authorizes a project-setting change.

The `1280 x 720` value in presentation documentation is a PC/reference output target, not the current logical rendering viewport.

## Project/global settings require explicit authorization

- `project.godot`
- Autoloads
- Input Map
- Rendering/physics/display/stretch settings
- Export presets
- Plugins/addons
- Engine-version migration

## Dependencies

Do not add third-party addons, libraries, binaries, generated tools or external dependencies without approval.

## Save/persistence

Persistence changes are high-risk. Identify schema and compatibility impact first, preserve existing save data unless migration is planned, never silently rename saved keys, and document migration requirements.

Real save/load is currently not a completed production system, so an agent must not assume a stable save schema exists.

## UI autonomy rule

AI may be highly autonomous on UI implementation only after the human defines what information is shown, what player actions exist, which actions require confirmation, and what state changes are gameplay-significant.

UI autonomy does not authorize changes to underlying economy, worker rules, production rules, condition drain, progression, or other gameplay logic.

## Documentation

Document non-obvious ownership, state transitions, compatibility constraints and intentional workarounds. Avoid noisy comments that merely restate code.

When a task changes project state:
- update `DEVLOG.md` for merged implementation history.
- update `ROADMAP.md` only when progress/priority/gates change.
- update `ARCHITECTURE.md` only when responsibilities or boundaries change.
- update `docs/game-concept.md` only with explicit design approval.
- update `docs/root-branch-map.md` only when technical domains/conventions change.