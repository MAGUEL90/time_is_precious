# City Hub and dialogue polish — 2026-10-10

Requested scope: smooth the emergency notification without pixel distortion, tidy Iddin-Sin dialogue, and combine City Supply/Management under one shortcut.

- City Hub opens/closes with C and contains Management and Supply tabs. Existing Inspect and last-raid navigation remain available from Management.
- Supply reads live food/clothing summaries from CitizenNeedsManager and CityToolStorage. The redundant storage-side summary is hidden; physical deposit access remains unchanged.
- Notification heartbeat changes opacity at a fixed scale of 1, preserving pixel geometry; pause, map exit and threat-end behavior remain intact.
- Iddin-Sin uses concise English lines with deliberate breaks. Quotes abbreviate Wood Log to Wood for display only. Costs, durations, conditions and response layout are unchanged.

Validation:
- RaidUITest PASS: tab switching/live refresh, alert scale/opacity, construction, inspection and report UI.
- CityStorageSupplyFlowTest PASSED: existing physical storage and supply flow.
- RaidPlaytestTest PASS: dialogue and wall/raid interaction.
- DefenseDialogueTest PASS with actual GL Compatibility renderer: construction, upgrade, watchtower, Inspect and captures of both City Hub tabs and greeting.
- Headless editor import passed; git diff --check passed. Old imported dialogue and one stale exact-copy assertion initially failed; reimport and corrected expectations passed on rerun.
- Native screenshots inspected at logical 400x225. Virtual display emits its existing unsupported V-Sync warning.

No balance, city progression, settings, plugins or save changes. User visual acceptance remains pending. Suggested next step: full raid/recovery playtest, then city progression in a separate feature branch.
