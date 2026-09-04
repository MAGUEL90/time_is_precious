# TIME IS PRECIOUS — TECHNICAL RULES

Status: TEMPLATE — NOT ACTIVE

Purpose: keep AI-written Godot changes understandable, local, reversible and consistent.

## Existing architecture first
Inspect the project before adding managers, event buses, base classes, autoloads, folder conventions or patterns. Reuse established architecture when suitable. Do not rebuild working systems for style preference.

## Locality
Prefer the smallest correct change. Do not refactor unrelated files, rename unrelated nodes, reformat large untouched sections, clean the repository as a side effect, or convert architecture during a feature task.

## Preserve public behavior
Preserve existing signals, public methods, resource schemas, relied-upon node paths, save fields, input actions and scene contracts unless explicitly authorized.

## Godot/GDScript
Exact coding standard: `TBD`
Until verified, match surrounding code style, use descriptive names, keep functions focused, avoid unexplained magic values, avoid unnecessary per-frame work, manage signals safely, treat parser errors/invalid references as blocking, and do not suppress warnings simply for a clean console.

## Scene safety
Preserve unrelated scene nodes/properties. Avoid broad node-path changes. Verify dependent scripts after node renames. Prefer targeted edits over replacing manually-authored scenes wholesale. Experimental UI remains in the approved sandbox until integration is authorized.

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

## UI autonomy rule
AI may be highly autonomous on UI implementation only after the human defines what information is shown, what player actions exist, which actions require confirmation, and what state changes are gameplay-significant.

## Documentation
Document non-obvious ownership, state transitions, compatibility constraints and intentional workarounds. Avoid noisy comments that merely restate code.
