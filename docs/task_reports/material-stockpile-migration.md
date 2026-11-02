# Removed material stockpiles: checkpoint compatibility

The five per-resource stockpiles are removed from the playable city. Resource
sites, their Laborer output on the ground, City Storage, City Treasury and the
workshop remain. The city worksite does not accept new Hauler assignments.

City checkpoint version 13 and worksite snapshot version 3 record whether a
ground pile came from a removed stockpile. Its old material and quantity become
a ground pile at the former stockpile location; it can be collected in portions
without making it a Hauler target. Older versions are validated against the
fixed, complete five-stockpile registry before migration. Loading only stages
these changes in memory; it does not rewrite the original checkpoint. The next
successful explicit save writes version 13 and preserves the prior file through
the existing backup mechanism.

Previously assigned Haulers do not take another load. An idle route releases;
a trip already underway completes once and then its worksite assignment ends.
Goods headed to a removed stockpile are left at its old delivery point. An
existing City Storage trip still attempts its original destination; if that
receipt is refused, the cargo is left at the destination instead of becoming
stuck or disappearing, and the refused receipt earns no delivery XP. A pending
resignation still completes after its last cargo; ordinary released workers keep
their contract and allocated equipment. A final migrated trip is permitted to
finish even if its former contract expires before its cargo is released.

The isolated regression scene `test_scene_stockpile_migration.tscn` exercises
synthetic version 12 checkpoints from the pre-removal game, including stored
goods, idle/outbound/returning Haulers, pending resignation and City Storage.
It checks conservation and repeated saves/loads. An oversized legacy state
that cannot be encoded within the existing 8 MiB file limit is rejected before
application, leaving its original file intact. Use a fresh XDG data directory
on Linux and pass `-- --case=stocked`, `idle`, `outbound`, `resigning`,
`returning`, `returning_loaded`, `returning_loaded_resigning` or `city_outbound`.
The latter also supports `--reject-city` and
`--resign-in-flight`. Other targeted scenes cover partial pickup and the normal
New Game → ground output → player pickup flow.
