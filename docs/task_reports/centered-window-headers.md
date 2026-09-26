# Centered window headers — 2026-09-23

## Scope

User authorized applying the City Storage header treatment to similar windows: centered title and independent top-right Close. Continued on `feature/workers/city-storage-supply`, starting at `4de7d0521648712b277851b9b6ec90ea07772fab` with 65 existing dirty paths. Existing authored changes were preserved. No gameplay, balance, save, project settings, commit or merge changes.

## Implementation

- Centered headers and separated Close in Item Transfer, Production Info, Worker Control/Details, Worksite inspector/Worker Progress, Hauler Delivery, legacy City Tool Storage and legacy Worker Hub.
- Applied the same layout to Workshop Build, Job, Production, Worker Assignment and Worker Info. A bounded implementation agent edited these eight workshop files; root reviewed the actual diff and validated them.
- Headers reserve symmetric space for close icons. Dynamic titles clip or wrap within their available space. Script references and affected existing test references follow the new Close paths.
- Workshop Job confirmation stays above its Close button in draw order.
- Already-centered menus and progress windows were retained. Footer actions and body/HUD labels are outside this header-only change.

## Validation

Godot 4.5.1, isolated temporary user-data directories:

- Editor parse/import: exit 0.
- Temporary geometry/render smoke: 13 headers passed centered alignment, centered bounds (1.1 logical pixel tolerance), non-overlap and Close containment. Long dynamic titles were also checked.
- WorkerControlTest, WorkshopUIRegressionTest, HaulerDeliverySetupTest, ContentWorksitesIntegrationTest and CityStorageSupplyFlowTest: PASSED.
- Main scene GL compatibility launch: exit 0.
- Representative rendered screenshots inspected, including transfer, worker details, hauler, workshop build and worker info.
- Initial geometry check caught the legacy City Storage label's full-width bounds; fixed with centered shrink sizing. Initial hauler regression retained an old HBox type/path; updated it for the new header and reran successfully.
- `git diff --check` passed. No old Header/Close or TitleRow/Close script references remain.

Evidence and pre-edit copies: `%TEMP%/tip-centered-headers-20260923/` (`qa`, `root-before`, `workshop-before`).

Known pre-existing engine diagnostics remain: certificate-store error and shutdown ObjectDB/resource warnings. The legacy Worker Hub prototype still exceeds the game viewport because of its pre-existing body sizing; its header geometry was checked, but the prototype body was not redesigned. Human in-game visual approval and other display sizes remain untested. No unsaved editor scene state was discarded.
