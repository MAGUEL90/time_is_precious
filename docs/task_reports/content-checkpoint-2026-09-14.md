# Content checkpoint before City Storage supply

Date: 2026-09-14
Content branch: `codex/content-worksites`
Baseline: `1a2e41ab6707e5816cf8472d4e39d194c596678d`
Next branch: `feature/workers/city-storage-supply`, based on this content checkpoint.
Status: PASSED — NEEDS HUMAN REVIEW (automated checks below; no merge approval).

## Purpose and scope

Preserve the Game Director's completed content-authoring session before starting City Storage
tool supply. This is a local Git checkpoint, not merge approval or a completed daily-loop claim.
The checkpoint includes existing scene-local integration (Level 2 scope), authored map/assets,
and previously uncommitted project notes and cleanup. The branch transition itself is Level 1.

- Authored content layout and tileset, Player spawn, worksite placement, stockpile house sprites,
  labels, and the existing Work Progress UI adjustment.
- Reusable worksite content adapter and storage backend, shared Player/InventoryUI bindings,
  world-coordinate output placement, and direct-component preview routing.
- Temporary `debug_disable_fatigue` support, enabled on the content Player; hunger/focus remain active.
- Existing deletion of 23 unused asset files and 22 import sidecars. A live-source audit found
  no references to the deleted assets in 350 script/scene/resource/project files.
- Existing `docs/game-concept.md`, `docs/CONTENT_LOG.md`, tileset guide, and preparation reports,
  preserved as part of the working-tree checkpoint. No new design or governance changes.
- Integration-test fixtures decoupled from fixed map coordinates and removed demonstration
  pickup/workshop instances, while retaining output-position and interaction-priority coverage.

## Validation

Godot 4.5.1 headless checks passed:

- Main-scene launch and direct `content_worksites.tscn` preview launch, 90 frames each.
- `ContentWorksitesIntegrationTest`: translated output positions, shared UI/input guards,
  cart requirement, daily targets and accepted delivery quantities, XP, Worker Progress, and Go To.
- `HaulerDeliverySetupTest` with `TIP_TEST_HAULER_TARGET=1` (automated mode; no save-slot access).
- `ConditionHUDRegressionTest`.
- Live asset-reference audit and `git diff --check`.

The first content integration run exposed obsolete layout/demo-node assumptions. The test now
uses translated authored nodes and its own pickup/workshop instances; the production map was
not changed by that repair. Root reviewed the actual test diff and verified the passing run.
An initial Hauler fixture launch omitted its automated-mode flag; its save read was blocked and
the existing save was preserved. The definitive automated run bypassed persistence and passed.
Evidence directory: `C:/Users/Hendro/AppData/Local/Temp/tip-content-checkpoint-20260914-055421/`.

## Review boundaries

- Main-scene art and interactive traversal were not visually re-reviewed during this checkpoint;
  the user supplied the completed content layout. Automated launch checks do not replace that review.
- Content Worksites still use playtest tool/Hauler seeding and scene-local state. City Storage
  deposits and worksite state retention across scene changes remain subsequent tasks.
- Fatigue stays temporarily disabled in this authored content scene until the Director re-enables it.
- Inherited `docs/CONTENT_LOG.md` labels for AI NPC integration and the complete save system
  disagree with their accompanying implementation descriptions. They are preserved here and need
  reconciliation during PR review; this checkpoint does not certify either system as complete.
- The earlier integration report describes its original map snapshot. This checkpoint includes
  later human layout changes and removal of demonstration pickups, workshop, and citizen instances.
- Known environment diagnostics: certificate-store read error and ObjectDB/resource warnings at
  shutdown. They remain visible in the logs.

The content branch requires a PR before entering `main`; the Game Director retains merge authority.
The next branch starts from this checkpoint so the authored map is available during City Storage work.
