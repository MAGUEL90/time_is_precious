# Reusable storage destination

Date: 2026-09-10
Risk: LEVEL 1 — isolated reusable scene and test; no production integration.
Branch: feature/process-workshop/clay-worksites
Baseline: 0f971ab330b83e2c8502ef943ddd04e94019565a
Starting tree: dirty; all existing local changes preserved.

## Scope and use

Instance `res://scenes/storage_destination/storage_destination.tscn` at a warehouse, house or workshop unloading location. Configure `storage_path` to that location's storage node. The node must implement atomic `try_add_item(item_id: String, quantity: int) -> bool`: false must leave its inventory unchanged. The existing workshop storage exposes this signature; no global workshop storage binding is enabled by default.

Adjust CollisionShape2D and ArrivalPoint in the editor. The arrival point should remain inside the unloading shape. Match the area's collision mask to the future carrier PhysicsBody2D layer (default layer 1). Physics overlap detection updates on physics frames, not immediately after teleporting.

The destination contains no inventory of its own. The receiving storage owns capacity and accepted item rules. Call `try_deliver(carrier, cargo)` with a cargo Dictionary containing `item_id` and `quantity`. Success stores the whole load and clears cargo quantity. Failure leaves cargo unchanged. A successful transfer emits `delivery_received`. Reusing the emptied cargo cannot duplicate the delivery.

`accepting_deliveries` can temporarily close the destination. Missing storage, unknown items, full storage, invalid cargo and a carrier outside the area reject unloading. No automatic partial unloading, dropping, route choice or capacity reservation is added.

## Hauler follow-up

The user's “3 muatan” is provisionally interpreted as three items per journey; tests exercise this example. The destination itself intentionally imposes no hauler load limit, so it remains reusable for other transport capacities. No Hauler scheduler or cart requirement is activated in this task.

A minimal cart requirement can remain in the worksite feature branch. Cart ownership, allocation, return on withdrawal and exclusive use must be defined when integrating Hauler assignments. A broader worker equipment system merits a separate scoped change. Current visual actors are Node2D visuals, so future carrier integration must provide a physics body or an explicitly reviewed arrival contract.

## Files and validation

- Created `scenes/storage_destination/storage_destination.gd` and `.tscn`.
- Created `scenes/test_scenes/test_scene_storage_destination.gd` and `.tscn`.
- Created this report. No existing gameplay files, settings or assets changed.
- StorageDestinationTest: PASSED (outside area, arrival, three-item delivery, repeated trip, duplicate retry, full storage, unknown item, disabled destination, missing backend).
- No warehouse/home/workshop runtime integration, persistence or actual Hauler journey is claimed.
- Existing certificate-store and ObjectDB/15-resource exit diagnostics remain.
