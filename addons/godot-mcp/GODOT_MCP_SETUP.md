# Time Is Precious: Godot MCP

Installed 2026-09-26: @yanhuifair/godot-mcp 1.12.2, with a local Godot 4.5 compatibility patch to plugin.gd.
Upstream: https://github.com/yanhuifair/Godot-MCP
License: AGPL-3.0-or-later; full license is included alongside this file.

## Local setup

- Codex server: godot_time_is_precious (STDIO).
- Server package is pinned in C:/Users/Hendro/Documents/Codex/tools/godot-mcp-1.12.2 with package-lock.json.
- Godot: C:/Users/Hendro/Downloads/Programs/Godot_v4.5.1-stable_win64.exe/Godot_v4.5.1-stable_win64_console.exe.
- Codex uses the absolute project path, so it does not depend on the chat's working directory.
- project.godot enables the editor plugin and the godot_mcp_runtime autoload.
- Existing dialogue_manager remains enabled. Gameplay scenes, scripts and display settings are unchanged.
- Editor bridge binds localhost:9876; runtime bridge binds localhost:9877. Keep only one MCP-enabled Godot project open at a time. Before writes, check the connected project/scene, especially when using worktrees.
- Restart/reload Codex's MCP server connection to load the new tools in a chat. Keep the project open in Godot for reliable editor access; play it for runtime access.

## Compatibility changes (local, 2026-09-26)

The original 1.12.2 plugin failed parsing on Godot 4.5.1 despite the broad Godot 4.x compatibility claim.

- Calls to optional unsaved-scene and 3D snapping APIs use dynamic call plus capability guards.
- Editor language comes from EditorSettings.
- Unsupported APIs return an explicit error rather than invented state.
- The editor error-list command returns an explicit unsupported diagnostic: upstream's legacy buffer is not populated and an empty list is not proof of no errors. Use read_game_log and captured editor stdout/stderr instead.

Do not reinstall the upstream addon over this folder without preserving/reapplying and testing these compatibility changes. The Node server package itself is unmodified.

## Verified workflow

1. editor_health_check / get_status: editor connection.
2. editor_play, then allow game startup to complete.
3. runtime_ping: require a successful live reply.
4. runtime_get_tree / runtime_get_node: inspect actual live nodes.
5. runtime_screenshot: save image, then open the saved image with an image-viewing tool. This MCP tool returns a path, not inline image pixels.
6. read_game_log: verify timestamp and startup content before judging errors. Do not mistake a previous run's log for the current run.
7. editor_stop: stop only the test session you started.

A cold editor may take time to become ready. Tool acknowledgement of play is not proof that the runtime has started. The installation probe was rerun in one persistent MCP connection after editor initialization.

## Validation

- MCP initialize and tools/list: 386 tools advertised (not all tested).
- Godot 4.5.1 addon check-only parser: passed after local compatibility patch.
- Live editor reported Godot 4.5.1.
- Main scene ran as ContentScene; runtime tree contained 586 nodes.
- Runtime screenshot saved and visually inspected at the native 400 x 225 viewport.
- Current-run log read through MCP; runtime bridge listening confirmed, no blocking runtime error in the smoke-test log.
- Game stopped through MCP.
- No gameplay scenes/scripts modified. Full gameplay regression suite and all 386 tools were not tested.
- Headless editor shutdown emitted ObjectDB/resource-in-use diagnostics; these are not counted as a clean full engine shutdown.

## Recovery

Remove only the godot_mcp_runtime autoload and godot-mcp editor plugin entry from project.godot to disable the addon, preserving all other entries. Remove the Codex connection with `codex mcp remove godot_time_is_precious` if desired. No merge or push was performed during installation.
