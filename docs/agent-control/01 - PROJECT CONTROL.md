# TIME IS PRECIOUS — PROJECT CONTROL

Status: TEMPLATE — NOT ACTIVE

## Human / Agent boundary

Human Game Director owns:
- Game vision and core loop.
- Story, lore, character identity, quests and consequences.
- Economy and balancing intent.
- Time ↔ Shekel trade-offs.
- Worker/delegation design.
- Progression and win/lose conditions.
- Final UX judgment and merge approval.

Agent may implement when authorized:
- UI from an approved specification.
- Reusable UI components.
- Boilerplate and data binding.
- Debug tooling and tests.
- Documentation.
- Small bug fixes.
- Repetitive signal wiring.
- Local refactors necessary for the assigned task.

## Source-of-truth separation

Design truth: `docs/game-concept.md`.
Progress / current priority truth: `ROADMAP.md`.
Technical architecture truth: `ARCHITECTURE.md`.
Implementation history / merged snapshots: `DEVLOG.md`.
Technical domain and branch taxonomy: `docs/root-branch-map.md`.
Implementation truth: current checked-out source code and scenes.
Change history: Git commits, branches, PRs, tags and Agent Run Log.

Do not treat current buggy behavior as proof that it is intended.
If documentation and implementation disagree, do not silently pick whichever is convenient. Preserve the working build, identify the conflict, and use the authority order in `00 - AGENT - READ ME FIRST.md`.

## Engine / platform baseline

- Engine family: Godot `4.5.x`.
- Current project feature level: Godot `4.5`.
- Renderer: GL Compatibility.
- Current logical viewport: `400 x 225`.
- Current development window override: `1200 x 675`.
- Presentation direction: `16:9`, PC first, Android landscape compatible.

The logical viewport and project-wide display settings are protected. Do not change them without explicit authorization.

## Repository-specific protected paths

### HARD PROTECTED — explicit task authorization required
- `AGENTS.md`
- `docs/agent-control/**`
- `docs/game-concept.md`
- `docs/characters/**`
- `dialogue/**`
- `project.godot`
- `addons/**`

### SYSTEM PROTECTED — allowed only when the task explicitly includes the affected system and risk level is appropriate
- `scripts/autoload/**`
- `scenes/player/**`
- `scenes/content_scene/**`
- `scenes/player_home_interior/**`
- `scenes/scene_transition/**`
- `scenes/nightmare_world/**`
- `scenes/work_state_boot_strap/**`
- `resources/job_data/**`
- `resources/process_data/**`
- `resources/citizen_data/**`
- `resources/worker_data/**`

### CONTROLLED DOCUMENTATION — update only when evidence from the task requires it
- `ROADMAP.md`
- `DEVLOG.md`
- `ARCHITECTURE.md`
- `docs/root-branch-map.md`
- `docs/game-concept-resolution.md`

Protection is not a permanent ban on development. It is a requirement that the task scope, risk level and human authorization match the impact.

## Preferred first automation zone

Approved pilot sandbox path after activation:

`res://scenes/test_scenes/ui_sandbox/`

Rules:
- Experimental UI must remain isolated from production scenes.
- Sandbox work must not alter gameplay state or production autoloads.
- Reusable components move into `res://scenes/ui/` only in a separate, reviewed integration task.

Suggested components:
- TIPPanel
- TIPButton
- TIPItemSlot
- TIPProgressBar
- TIPTooltip
- TIPDialog

These names are conventions for a future pilot, not verified existing production files.

## Task scope contract

Every task must define objective, risk level, expected files, protected/out-of-scope areas, acceptance criteria and test plan.

If implementation unexpectedly requires a protected-area change, do not silently expand scope.

## Human review triggers

Mandatory when a change affects mechanics, story, economy, balance, save compatibility, autoload/global state, multiple major systems, broad public APIs, major scene/folder structure, dependencies/plugins, project/export settings, deletion/rename of existing assets, or large-scale refactors.

## No-guessing rule

Missing design values remain `TBD`. Do not invent or silently borrow values from another system.

## Activation gate

This file becomes ACTIVE only after:
1. Source-of-truth documents are synchronized with merged implementation.
2. A human runtime smoke test confirms the selected baseline is healthy.
3. A permanent known-good checkpoint/tag is created.
4. Protected paths and sandbox path are accepted.
5. The Game Director explicitly approves activation.

Until then, this remains `TEMPLATE — NOT ACTIVE`.