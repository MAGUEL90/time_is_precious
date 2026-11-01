# Five UI feedback items — local verification, 2026-10-31

Baseline: `fc71ceb573cf2d9bdccf52e3f9f2bc2d4eb6e587` on `fix/ui/fire-worker-feedback-20261031`. The starting working tree was clean. This report records the revisions and their verification against that baseline.

1. **Job Board selection and names.** Opening the board leaves all candidates unselected and Hire disabled until a manual selection. New initial applicants use Naram and Lugal from the existing citizen-name pool. When an old applicant has one of the two exact original ID and role-label pairs, the board corrects only its in-memory display name. Other IDs and custom names are unchanged. Fixed IDs, professions, save schema, and the name-generator counter are preserved. Opening the board does not write the checkpoint; a later ordinary save stores the corrected name. Already-hired workers who are not applicants are not renamed.
2. **Hire confirmation.** Text in the contract panel is white. The 3-, 6-, and 9-day buttons and the price row keep their size and position while changing duration, including when the total changes its number of digits. Existing font sizes are retained: the title is 12 pixels and candidate names and other panel text are 6 pixels.
3. **Hire success feedback.** The success message is removed; error feedback is retained.
4. **Fire confirmation.** The two dynamic paid-through and remaining-time rows are removed. The panel is 160 × 80 logical pixels and retains the assignment, tool-return, and no-refund information and No/Yes actions. The existing unpaid and expired notices remain. The blocked-Fire click warning is unchanged.
5. **Renewal dropdown.** The existing `brown_panel_24x24.png` atlas style is used for the option list, with white `3D`, `6D`, and `9D` labels. Durations and payment rules are unchanged.

## Changed files

- Runtime: `scenes/content_scene/startup/initial_worksites.gd`, `scenes/ui/job_board_ui/job_board_ui.gd`, `scenes/ui/job_board_ui/job_board_ui.tscn`, `scenes/test_scenes/clay_worksite_test/clay_worker_management.gd`, and `scenes/test_scenes/ui_sandbox/worker_control/worker_control.gd`.
- Tests: `scenes/test_scenes/clay_worksite_test/test_scene_worker_control.gd`, `scenes/test_scenes/initial_workshop_start_test.gd`, `scenes/test_scenes/population_employment_integration_test.gd`, `scenes/test_scenes/test_scene_content_prepaid_ui.gd`, `scenes/test_scenes/test_scene_contract_continue.gd`, `scenes/test_scenes/test_scene_dismissal_journey.gd`, and `scenes/test_scenes/test_scene_worker_renew_currency.gd`.

## References

The original five user screenshots were inspected by the parent, but their pixels were not available in this executor. The final changes use the parent's verified descriptions and the user's explicit text instructions; the existing brown asset and rendered game output were inspected locally. No restricted transfer was attempted.

## Verification

All game tests below used Godot 4.5.1 with isolated test data. Rendered checks used a 400 × 225 logical viewport and a 1200 × 675 window.

- **PASS:** Rendered `test_scene_content_prepaid_ui.tscn`. It covers no default selection, manual selection, Back without payment, insufficient funds, a single batch payment, repeated confirmation, white text, and stable selector and quote bounds for 3/6/9 days. A 19-digit quote also fits without clipping in the inspected render.
- **PASS:** Headless `initial_workshop_start_test.tscn` and `population_employment_integration_test.tscn`.
- **PASS:** Separate-process `test_scene_contract_continue.tscn` phases `write`, `read`, and `readrenew` with an isolated save. The test saves an old Hauler placeholder, verifies that opening the board does not change the checkpoint bytes, and verifies the corrected applicant name after the next normal save and Continue.
- **PASS:** Rendered `test_scene_worker_renew_currency.tscn`. It checks the brown dropdown, labels, existing durations, cancel/no charge, insufficient funds, and renewal payment.
- **PASS:** Rendered `test_scene_worker_control.tscn`. It checks compact Fire dialog geometry and text for active, unpaid, and expired contracts, cancel, no refund, and the valid confirmation path.
- **PASS:** Rendered `test_scene_worker_fire_hover.tscn`, whose current assertions cover no warning on hover, the blocked-Fire click warning and its cleanup, and valid Fire confirmation.
- **NOT RUN:** `test_scene_dismissal_journey.tscn` requires its prior earned checkpoint. Windows and Android were not tested. Linux software rendering reported that changing V-Sync mode is unsupported.

## Internal captures

Rendered fixture captures were generated locally for visual verification and are not included in the commit. They are test output, not the five user references.
