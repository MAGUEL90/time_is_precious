# Staged content integration - 2026-10-27

Branch: `feature/content-scene/prepaid-integration-20261027`.
Verified base: `ce501a129e96fba95b80615410fb00dd665e00db` from `feature/economy/prepaid-worker-contracts`.
Content source remains `85dca9a8e509cfa712510c02649497b5a824e402` on the unchanged checkpoint branch.

## Stage 1: artwork and resource integrity

Selectively ported52 asset/metadata paths:48 additions and4 existing PNG replacements. All art bytes come from the reviewed content snapshot; variants and canonical UID/import settings are retained. No world scene, terrain, stockpile/date-palm removal, recipe, fee, save adapter, debug/guard, capture harness, project setting or payroll rule is included in this stage.

Validation used an isolated disposable copy of the prepaid source plus these exact assets. Only that QA copy disables MCP autoload/editor plugin to avoid sharing control ports; the production project settings are unchanged. APPDATA/LOCALAPPDATA and all test profiles are isolated under evidence, never personal saves.

- Cold headless Godot4.5.1 import: exit0, no timeout.
- `asset_organization_test`:176/176 pass, exit0; all25 image mappings, exact PNG hashes, imported dimensions/readability and canonical/retained UID resolution.
- Existing `test_scene_prepaid_contracts`:PASS,0failed, exit0. This run is a native prepaid baseline control, before batch/UI changes.
- Existing Windows root-certificate-store diagnostic remains; no parse/script failures in those runs.

No main merge, push, PR, or modification to the original preview/checkpoint branch was performed. Later UI/arrival work is separate and is not validated merely by these asset checks.
