extends "res://scenes/test_scenes/test_scene_city_save.gd"

## Isolated multi-process checkpoint test. The same writer can run on the
## preceding commit; the reader checks this branch's reconstructed presentation.
const TOWER_SAVE: String = "user://watchtower_layout_continue/checkpoint.json"
const REFUND_SAVE: String = "user://watchtower_layout_continue/refund.json"

func _run() -> void:
	_snapshot_globals()
	TimeComponentManager.set_process(false)
	TimeComponentManager.is_paused = false
	get_tree().paused = false
	await load_content()
	await get_tree().process_frame
	store = WorkStateRuntime.get_node("CitySave")
	store.disk.path = TOWER_SAVE
	var phase: String = "write"
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--tower-phase="):
			phase = argument.trim_prefix("--tower-phase=")
	_expect(phase in ["write", "read", "completed"], "Use a known watchtower checkpoint phase.")
	_expect(FileAccess.file_exists(TOWER_SAVE) == (phase != "write"), "Use a fresh isolated writer and its checkpoint for readers.")
	if failures > 0:
		_finish_tower(phase)
		return
	if phase == "write":
		await _seed()
		_set_clock_minute(_clock_minute() + 120)
		content.get_node("YSortWorld/WorkerRuntime").daily.tick()
		_expect(state.wall_hp == 50, "The paid wall finishes before tower construction.")
		Inventory.add_bulk_item({"stone": 10, "wood_log": 10})
		var before: Dictionary = Inventory.items.duplicate(true)
		_expect(state.request_wall_work(state.get_work_quote("watchtower")), "The real paid watchtower project starts.")
		_expect(int(Inventory.items.get("stone", 0)) == int(before.get("stone", 0)) - 10
			and int(Inventory.items.get("wood_log", 0)) == int(before.get("wood_log", 0)) - 10,
			"The project charges the player exactly once.")
		_set_clock_minute(_clock_minute() + 90)
		content.get_node("YSortWorld/WorkerRuntime").daily.tick()
		_expect(state._work_kind == "watchtower" and state._work_remaining == 90 and not state.watchtower_built,
			"The saved project is halfway through construction.")
		_expect(store.save_checkpoint(), "The pending watchtower checkpoint is saved: " + store.last_error)
	else:
		var original: String = FileAccess.get_file_as_string(TOWER_SAVE)
		var original_document: Dictionary = JSON.parse_string(original)
		_expect(store.load_checkpoint(), "The prior checkpoint loads: " + store.last_error)
		await get_tree().process_frame
		await get_tree().process_frame
		_expect(FileAccess.get_file_as_string(TOWER_SAVE) == original, "Loading does not rewrite the checkpoint.")
		var restored: Dictionary = store.snapshot.capture(content)
		_expect(JSON.parse_string(JSON.stringify(restored, "", true, true)) == original_document,
			"Every saved owner, payment and RNG state restores exactly.")
		var tower: Node2D = content.get_node("RaidBootstrap/WatchtowerVisual")
		var anchor: Node2D = content.get_node("YSortWorld/WatchtowerDisplayAnchor")
		var indicator: WallWorldIndicator = content.get_node("RaidBootstrap/WallWorldIndicator")
		_expect(tower.global_position.is_equal_approx(anchor.global_position), "Continue uses the temporary clear tower display position.")
		if phase == "read":
			_expect(state._work_kind == "watchtower" and state._work_remaining == 90
				and not state.watchtower_built and tower.visible and tower.constructing,
				"A pending old checkpoint reconstructs the scaffold without granting a tower.")
			_expect(indicator.visible and indicator.work_progress.work_kind == "watchtower"
				and indicator.global_position.is_equal_approx(wall_spot.global_position + Vector2(0, -18)),
				"The restored work indicator is attached to the caretaker.")
			# Probe the presentation of a paused project without changing its ledger;
			# the raid state machine itself has separate combat regression coverage.
			var prior_phase: String = state.phase
			state.phase = "attacking"
			state.changed.emit()
			_expect(tower.visible and tower.constructing and indicator.health_label.visible
				and indicator.progress_bar.value == state.wall_hp and state._work_remaining == 90,
				"During an attack the scaffold remains unfinished and the caretaker shows wall HP.")
			state.phase = prior_phase
			state.changed.emit()
			_expect(indicator.work_progress.visible and not indicator.health_label.visible,
				"After the attack the same construction progress returns.")
			var retained_payment: Dictionary = state._work_paid.duplicate(true)
			var inventory_before_refund: Dictionary = Inventory.items.duplicate(true)
			Inventory.max_load = Inventory.get_total_inventory_weight()
			state._refund_interrupted_repair()
			state.changed.emit()
			_expect(state._refund_pending and state._work_paid == retained_payment
				and Inventory.items == inventory_before_refund,
				"A full inventory retains the entire interrupted tower payment for refund.")
			_expect(not tower.visible and not indicator.visible and ui.construction_row.visible
				and not ui.construction_progress.visible and ui.construction_label.text == "Refund pending",
				"A stopped tower awaiting refund is not shown as active construction.")
			store.disk.path = REFUND_SAVE
			_expect(store.save_checkpoint(), "The pending tower refund saves without losing its payment: " + store.last_error)
			state._refund_pending = false
			state._work_kind = ""
			state._work_paid.clear()
			state._work_paid_source = ""
			_expect(store.load_checkpoint(), "The pending tower refund restores: " + store.last_error)
			_expect(state._refund_pending and state._work_paid == retained_payment
				and Inventory.items == inventory_before_refund and not tower.visible
				and not indicator.visible and ui.construction_label.text == "Refund pending",
				"Load reconstructs the held payment and its stopped-work presentation.")
			Inventory.max_load = maxf(100000.0, Inventory.get_total_inventory_weight())
			state._refund_interrupted_repair()
			state.changed.emit()
			var refunded_inventory: Dictionary = inventory_before_refund.duplicate(true)
			for item_id: String in retained_payment:
				refunded_inventory[item_id] = int(refunded_inventory.get(item_id, 0)) + int(retained_payment[item_id])
			_expect(not state._refund_pending and state._work_kind.is_empty() and Inventory.items == refunded_inventory
				and not tower.visible and not indicator.visible, "A later retry returns the payment exactly once.")
			state._refund_interrupted_repair()
			_expect(Inventory.items == refunded_inventory, "A repeated refund cannot duplicate materials.")
			store.disk.path = TOWER_SAVE
			_expect(store.load_checkpoint(), "The original in-progress project restores after the refund probe: " + store.last_error)
			_expect(tower.visible and tower.constructing and indicator.work_progress.visible,
				"The original in-progress tower presentation is restored.")
			var paid_inventory: Dictionary = Inventory.items.duplicate(true)
			_set_clock_minute(_clock_minute() + 90)
			content.get_node("YSortWorld/WorkerRuntime").daily.tick()
			_expect(state.watchtower_built and state._work_kind.is_empty() and tower.visible and not tower.constructing
				and Inventory.items == paid_inventory, "The tower completes once without another payment.")
			_expect(store.save_checkpoint(), "The completed tower checkpoint saves: " + store.last_error)
		else:
			_expect(state.watchtower_built and state._work_kind.is_empty() and tower.visible and not tower.constructing,
				"A fresh process restores the completed tower, not its scaffold.")
	_finish_tower(phase)

func _finish_tower(phase: String) -> void:
	get_tree().paused = false
	print("WatchtowerLayoutContinueTest ", phase, ": ", "PASS" if failures == 0 else "FAIL (%d)" % failures)
	get_tree().quit(0 if failures == 0 else 1)
