# Worker Hub pause investigation

Date: 2026-10-03
Branch: feature/process-workshop/main-map-access
Risk: LEVEL 1, local UI visibility repair and regression coverage.
Status: confirmed Work Progress repair PASSED - NEEDS HUMAN REVIEW;
reported K-specific freeze not reproduced.

## Findings

The Game Director reported an apparent freeze after K. Current ContentScene tests using
physical K open the Worker Hub correctly and pause the world while its menu is visible.
K, Esc and the close button release that pause. Empty and two-worker rosters both render
inside the 400x225 logical viewport. No Worker Hub crash was found in the last game log.

The last game log did contain a WorkProgressUI focus warning. The authored ContentScene
sets WorkProgressUI.visible=false, while open_panel previously showed only its Root child
and paused the tree. Physical J therefore produced an invisible paused modal; K correctly
refused to open another panel over it. This case was reproduced by a failing assertion
and a runtime capture before repair. It is a confirmed defect but is not proof that the
user's K-specific report came from the same sequence. A clarification about panel visibility
was requested; no answer had arrived at this checkpoint.

The connector's runtime_input sends only logical keycode, while K is a physical-key binding.
Its initial injected K did not open the panel, so it was not used as validation evidence.
The regression injects real InputEventKey events with physical_keycode and keycode set.

## Repair

Work Progress now shows its CanvasLayer as well as Root before taking the modal pause.
Its focus request respects the existing close button's FOCUS_NONE setting. ContentScene's
editor visibility settings and all authored layout remain unchanged.

## Validation

Godot 4.5.1 GL Compatibility, 1200x675 development window:

- MainMapWorkerHubTest PASS: actual ContentScene, physical K and J, empty/hired worker
  rosters, visible in-bounds Hub, Tools while paused, K/Esc/Close release, J toggle/reopen,
  Work Progress visible whenever it pauses, other-modal exclusion and subsequent K access.
- WorkshopPlotAccessTest PASS: plot interaction, modal shortcut exclusion and pause release.
  Its first run failed only because an old assertion required Worksites to be absent.
  That assertion now checks the already-approved main_map_worksites.tscn reintegration and
  continued absence of the old HomeDoor. No production map change was needed.
- Native screenshots for empty Hub, hired Hub and visible Work Progress inspected.
- Native scene launches parse/load the affected scripts and scenes without script errors.
- Existing ObjectDB shutdown warnings and 15 retained resources remain. The prior focus
  warning is absent in the final regression run. Editor error-list capture is unsupported
  by this addon; game log and native process outputs were used instead.
- Task diff and whitespace checked. Map hash matches the pre-repair snapshot.

Modified: work_progress_ui.gd, workshop_plot_access_test.gd, ROADMAP.md.
Created: main_map_worker_hub_test.gd/.uid/.tscn, this report.
No files deleted or renamed. No commit, push or merge.

## Limits

No K handler or Worker Hub layout was changed because the reported failure could not be
reproduced there. The running game must be restarted to load the repaired script. This
work does not resolve the separate pending starting-cart decision or add equipment.
