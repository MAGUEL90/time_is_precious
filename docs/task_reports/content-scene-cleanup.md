# ContentScene cleanup and progress handoff

Date: 2026-09-26
Branch: chore/content-scene/unused-node-cleanup
Baseline: 2a7b773cb975676298c44daab1e51d502e930f17 (main / merged City Storage PR #105)
Risk: LEVEL 2, bounded cleanup of an existing protected content scene, explicitly approved by the Game Director after audit.
Status: PASSED - NEEDS HUMAN MERGE REVIEW.

## Changes

Remove the empty ContentDirector node, inactive root Camera2D, and no-op content_scene.gd plus its UID. The Player camera remains current. No gameplay rules, authored positions, tile data, HUDs, Worksites or project settings are changed.

ROADMAP now records merged City Storage work and directs the next review to the parked mudbrick checkpoint. MCP remains separate in PR #106. The parked mudbrick worktree is preserved with all uncommitted changes; its previous tests are historical evidence, not validation against current main. Initial authored-map workshop access still needs a Game Director decision.

## Evidence

- Reference searches found no source references to ContentDirector and no remaining references to the removed script/UID.
- Live MCP probes before cleanup: root camera is_current=false, Player camera is_current=true. After cleanup Player camera remains current; root direct children decreased from 8 to 6.
- Before/after screenshots inspected at 400x225: authored composition unchanged.
- Game Director reported the playtest was okay.
- Fresh independent checkout: Godot 4.5.1 headless editor import exited 0.
- Fresh independent checkout without MCP: ContentWorksitesIntegrationTest PASSED, exit 0.
- Test covers node binding, placement, interaction/modal guards, time shortcuts, daily delivery, progress and Go To.
- Shutdown still reports ObjectDB leaks and 15 resources in use; not fixed or hidden.
- git diff --check passed. Generated changes to three Dialogue Manager .import files were inspected and restored; they are not part of this PR.

No broad unused-node audit, full-game regression or save/load compatibility is claimed. The original checkout's local cleanup was preserved while preparing this independent PR checkout. No merge performed by the agent.
