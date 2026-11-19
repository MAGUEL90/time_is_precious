# Genuine schema-17 authored-palm HOME research

**Scoped result: the byte-preserved research copy and old/current HOME Continue tests pass. Production migration is still incomplete and needs a separate decision and review.** The successful copy is created by isolated test-only byte-splicing tooling, not by a production migration path. No production code, validator, scene, resource, setting, laptop file or real save was changed. The earlier schema-18 HOME evidence and both source baselines were left frozen.

## Important finding: ordinary reserialization is not byte-exact

An initial attempt passed the parsed Godot comparison but failed an independent Python comparison of the old file and the result of writing the planned copy via the existing Godot JSON file boundary. Its original schema-17 HOME source encoded `player.hunger` as decimal `0.137000000000000094` (binary64 `3fc189374bc6a7f3`); the reserialized planner output encoded `0.137000000000000066` (`3fc189374bc6a7f2`), one ULP lower. The header token also changed from `17` to `17.0`. This is an observed on-disk difference in the synthetic fixture; it does not by itself establish a different live loaded value. The source file remained unchanged. The initial failed run is preserved at `qa/final_run/`; the independent result from the final run is `RESERIALIZATION_FINDING.json`.

The current copy helper preserves the decoded/parsed representation when it appends a source, but that alone does not prove byte- or decimal-exact preservation after full JSON reserialization. No production fix or real-save policy was invented. The reserialized planner output is retained only as evidence, never used as the successful converted checkpoint.

## Byte-preserving research path and tested behavior

1. An isolated copy of the genuine unchanged version-17 project used its production city startup, HomeDoor and CitySave writer to create a schema-17 HOME checkpoint with exactly six legacy ledgers. The writer advanced 137 real game minutes, varied source depletion/timers via normal collect calls, and verified three actual saved binary64 Satisfaction values immediately below, at and above 0.5. The writer schema is asserted from the unchanged runtime implementation, not created by editing a header.
2. The current version-18 research copy helper validated the genuine17 HOME input and planned one pristine authored source. It also rejected a deliberately mixed17-header/18-float64 control. The helper's reserialized planner file is not the accepted output.
3. `surgical_home_copy.py` is a **test-only** isolated adapter. It validates the planner's six old records and pristine new record, locates the unique encoded pickup-source array in the genuine original using a JSON-aware span scanner, and inserts only the compact seventh entry into the original UTF-8 bytes. It writes separate disposable output files and never rewrites the input. The final copy has exact header17, no float64 tags, all six records and every other encoded field unchanged. Removing the one 653-byte inserted segment reconstructs the entire original byte-for-byte. An independent Python Decimal comparison confirms equality after removing that entry. This is not a production implementation or approval to migrate a user save.
4. A separate genuine17 process used the unchanged Start Menu/store/home transition to Continue the byte-preserved copy. It used the real ExitDoor, then a separately prebound **test-only** palm view. The real gather handler granted three dates once, and the unchanged HomeDoor/store wrote a separate, genuinely version-17 harvested HOME checkpoint. It contains the depleted seventh source, its timer and RNG and no v18 tags.
5. Eight separate fresh processes read the same files: pristine and harvested twice each on the genuine17 runtime tree, and pristine and harvested twice each on the current18 runtime tree. Each tested real HOME→city→HOME travel, all saved state fields, all source IDs/config/slots/timers/RNG, and no duplicate ledgers or fruit. On genuine17 no fields are normalized. On current18 the source is first asserted to lack `needs.satisfaction_accumulators`, the live field is independently asserted to be an empty dictionary, and **only that empty field** is added to an in-memory expected comparison copy. Every other saved field, including timing, needs, profiles, numeric values and RNG, is compared exactly; only dictionary insertion order is ignored. The original file remains schema17 and byte-identical.
6. On both runtime trees, the normal validator/menu safely rejected (a) the original six-source HOME document against the seven-source test city, (b) a non-boolean authored slot, and (c) the seven-source document against the unmodified six-source city. Each was independently checked to fail specifically with `Invalid pickup source state.` rather than a mixed-format error. No session started; menu remained retryable; all live saved fields and ledgers were unchanged. The malformed file is made by changing only the newly appended source slot and has no float64 tags.
7. Five synthetic primaries (source, planner, converted, harvested, malformed) and their `.bak`, `.tmp`, `.pending` sentinels totaled 20 audited artifacts. An external audit compared every non-log file under the isolated XDG userdata tree before and after each of the 14 read/rejection processes; all paths, lengths and SHA-256 hashes were identical. Both old/current scripts refused deliberately duplicate XDG data/config paths before touching any non-log sentinel.

The unmodified returned city has **no authored palm view**, because there is no production startup hook. Its seventh ledger persists. All fruit-view checks after that observation use the explicit synthetic test-only view. The exact latest authored user map and visuals were not available.

## Commands and results

Executed from this directory:

`python3 run_genuine17_home.py final_byte_preserved`

It records every individual Godot command, XDG environment, exit, result and complete non-log before/after hash manifest in `qa/final_byte_preserved/manifest.json`. It creates a new isolated QA directory and refuses to reuse one. To repeat without altering evidence, choose a fresh run name, for example `python3 run_genuine17_home.py another_unique_name`.

- Engine: Godot `4.5.1.stable.official.f62fdbde1`, SHA-256 `db07cae7de644278a1884d4552bdf2bca3f5d30131b18faf3a0c4d730080b199`.
- Both runtime trees use that same engine binary; “v17” and “v18” identify the unchanged production project implementations, not different Godot binaries.
- **552 explicit assertions passed** over 17 normal fresh-process fixture stages. All normal stages exit 0 with no ERROR or SCRIPT ERROR. Six intentional source-rejection stages emit expected `unsupported` warnings.
- Two additional unsafe-profile stages exit 1 with the one expected guard ERROR each; all their non-log sentinel files remain unchanged.
- The test-only JSON insertion is additionally checked independently by the Python adapter and by the orchestrator's Decimal comparison. The failed first attempt is not included in the passing count.
- Both isolated project copies passed `git diff --check`; no graphical attempt was made.

## Fingerprints, lineage and replay

The genuine v17 baseline is `../combined_precision_cloud_20261109/v17_baseline_project`, whose `CitySaveState.VERSION` is 17. Its entire 3,176-file non-cache tree matches the prior recorded `combined_precision_cloud_20261109/baseline_hashes.json` (manifest SHA-256 `f28e6f7656619591752a7f5ab96ff81c009fea985354a35ac96a138e2ae99899`). Its state/values/needs-manager hashes are respectively:

- `e290a178b89f6a6f74bbd0116f9815b3d0ad892fd7309475bfbee5d76368e8c4`
- `2edb2c236e3f0237f140b7ce73950be533d46d77c7d5a0a8ae570c6a9b01ef81`
- `fd5c0cfafd1fa06e4a4bb12b7725ed20c3cdf558c808908c0ab903b9940d5910`

The v18 starting tree is the previously reviewed `../palm_home_continue_cloud_20261109/project`. `SOURCE_AUDIT.json` confirms both frozen trees unchanged after all tests. Each new candidate adds exactly the same two scripts and modifies/deletes no baseline files:

- `scenes/test_scenes/run_authored_palm_genuine17_home.gd`: `848040bccac7cac998de62127fa0fa5e2b212fb5a6489dc30cb602c435d70ab7`
- `scenes/test_scenes/test_scene_authored_palm_genuine17_home.gd`: `6ccfdefa525a816ab7a247067767d7300f651285514264102e51d753e17670bf`

`TEST_ONLY_INCREMENT.patch` SHA-256 `561d663bfc7bac1db2e7ce4983fc8108c58630f275b0d1df5e08db842ffcaac2` was applied to separate copies of both exact baselines; all four resulting files matched tested hashes (`PATCH_REPLAY.json`). It adds test scripts only. External research tools:

- `run_genuine17_home.py`: `fbab49a97a7b33812eb8cc26817da9a57747dbe2a11a405938eec6aefc0c8582`
- `surgical_home_copy.py`: `e8dc5f583d4b810ac38096b8dddfc635bcfc9f060f2f88db5afac6bc36e3038d`
- `verify_reserialization_drift.py`: `a5704abb3404e06d74adc29238a9c59a0e8f3040876f8d34092e6feecd35ec99`

Final synthetic checkpoints:

- Genuine six-source HOME17: `6f43b94454088b002b476b2edddd0bb7c29ccd8d94b69ae76b391e07eae543d0`
- Byte-preserved seven-source HOME17: `913f9bb511184d2ba47c93d78f1edc269ed34ccb35a78267c5948fa0051fc5cd`
- Genuine harvested seven-source HOME17: `f3620964c01d58739f475e388fdb9b94367fe1cef4f64289d94838167424aaf2`

## Remaining blockers

- Production still lacks an authored-palm startup/reload hook and a reviewed real-save migration policy. The unmodified city rejects the seven-source HOME checkpoint and does not recreate the authored view on return.
- The ordinary parsed/reencoded JSON output shown above does not meet the requested exact on-disk preservation. The byte-splicing adapter is isolated research only and must not be presented as a production-ready migration or used on real saves.
- Exact latest user-authored scene, graphical/manual gameplay, Android, whole-project validation and merge/deployment remain outside this test.
