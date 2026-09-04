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
Design truth: `TBD`
Implementation truth: current checked-out source code/scenes.
Change history: Git commits, branches, PRs, tags and Agent Run Log.

Do not treat current buggy behavior as proof that it is intended.

## Protected areas until fully mapped
- Story/dialogue/canon content.
- Quest definitions.
- Economy constants/formulas.
- Progression rules.
- Worker/delegation rules.
- Save schemas/migrations.
- Global managers/autoloads.
- Core player controller.
- Main world scenes.
- Project/export settings.
- Third-party addons.

Repository-specific protected paths: `TBD`

## Preferred first automation zone
Suggested isolated UI sandbox: `res://dev/ui_sandbox/`
Actual approved path: `TBD`

Suggested components:
- TIPPanel
- TIPButton
- TIPItemSlot
- TIPProgressBar
- TIPTooltip
- TIPDialog

These are proposed conventions, not verified existing files.

## Task scope contract
Every task must define objective, risk level, expected files, protected/out-of-scope areas, acceptance criteria and test plan.

If implementation unexpectedly requires a protected-area change, do not silently expand scope.

## Human review triggers
Mandatory when a change affects mechanics, story, economy, balance, save compatibility, autoload/global state, multiple major systems, broad public APIs, major scene/folder structure, dependencies/plugins, project/export settings, deletion/rename of existing assets, or large-scale refactors.

## No-guessing rule
Missing design values remain `TBD`. Do not invent or silently borrow values from another system.

## Activation gate
This file becomes ACTIVE only after repository-specific values are verified, a clean known-good checkpoint exists, protected paths are mapped, the sandbox path is approved, and the Game Director explicitly approves activation.
