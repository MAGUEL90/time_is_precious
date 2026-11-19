# Synthetic pre-removal checkpoints

The eight compressed JSON files were generated in an isolated Godot 4.5.1
profile by the original game code at commit `35969dc189632c5e83b85ec0c4737478f391fe59`.
They contain synthetic citizens, workers, stock and inventory, not a player's
save. The fixture setup debited each resource site's stock by the quantities
placed into stockpiles or on the ground. Workers, hauling routes and the save
file were produced using the original game APIs.

The cases cover stored materials only, an idle Hauler, an outbound shipment,
a pending resignation during shipment, a return after a completed delivery,
returns carrying rejected cargo with and without pending resignation, and an
outbound City Storage delivery. `test_scene_stockpile_migration.gd`
checks the SHA-256 of the decompressed original bytes before using a copy.
The originals are not rewritten by the test.
