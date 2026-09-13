# Worker Hub: Primary to City Storage

- Primary navigates directly to the City Storage tool view, hiding the Hub and skipping the embedded picker. Back/Escape returns to Tools; closing the Hub resets this navigation.
- The view uses the existing scene-local CityToolStorage unit provider. Equip/Unequip uses the existing management guards and real ownership allocation. It does not use player inventory or the food/clothing CityStockManager.
- Layout is authored in `scenes/storage_destination/city_storage.tscn`; dynamic rows and navigation are connected in `worker_control.gd`. Secondary retains its existing picker.
- Equipped Cart now uses the supplied `assets/ui/ui_icon/cart_icon.png`. Current supplied push/idle cart PNGs remain directly referenced by `worker_cart.tscn` (four push frames, two idle frames, 32 px cells). Updated art loads from those same paths; no generated replacement or new hair/clothes.
- Preview-only idle slowdown remains 1/3; world speed is unchanged.

Validation: WorkerControlTest passed, including direct navigation, refresh, Back, physical cart equip and return. WorkerCartAnimationTest passed with graphical frame synchronization checks; current cart poses and City Storage screenshot inspected. Main headless smoke exited 0. `git diff --check` passed. Existing certificate-store and shutdown ObjectDB/15-resource warnings remain. A test fixture initially retained its spare equipped cart and conflicted with a later allocation assertion; added the matching UI return step and reran successfully.

Local user changes preserved. No commit, push, or merge.

## Inventory presentation revision

City Storage now reuses Inventory's `item_grid.tscn`, `item_slot.tscn`, five-column layout, and outer panel atlas. Its heading remains City Storage. Clicking a physical tool slot equips or returns that unit through the existing management adapter; player-inventory dragging is disabled for these slots. The view remains bound to CityToolStorage, not the player's bag. Empty slots pad the initial 15-cell grid; additional stock scrolls vertically.

Accessory 1 and 2 have native-size `plus_icon_3` configured directly in `worker_control.tscn`; their existing disabled state is preserved. WorkerControlTest passed including real-unit equip/return, and both revised screens were visually inspected. An initial resource-order parse error was corrected before the passing run.

## Category and equipment navigation revision

- Removed worker/context text and Back. Existing close-icon states now return to Hub Tools.
- Reused InventoryCategorySelector with all six Inventory categories. The current provider contains equipment units only, so other categories show empty slots. City Storage still represents physical tool units rather than player inventory contents.
- Primary, Secondary and both Accessory buttons open the same storage view. Incompatible slot items remain visible but disabled. Accessory equipment definitions are not yet provided; no new item types or effects were invented.
- Equipped units display E in ItemSlot's existing SelectedQty position and pale-yellow theme color, including units held by another worker; ownership guards prevent sharing.
- WorkerControlTest passed for category switching, E, both Accessory entry points, close return and Secondary equip/unequip. Graphical inspection and diff whitespace check passed. Existing shutdown warnings remain.

## Human layout preservation and item details

Renamed the presentation scene to `city_storage.tscn`, retaining its UID and updating live references. Preserved the human's 270 x 210 panel, 16 px margins, and 8 px content separation. Close now shares TitleRow with the heading, separate from Categories. The CityToolStorage backend name remains unchanged because it represents tool allocation rather than presentation.

Tool hover reuses the player's ItemInfoPanel scene and registered ItemDatabase data. Cart, which has no registered item resource yet, shows its known unit name, equipment category and 3-item trip capacity; weight remains unknown (-). No invented weight or new balancing. Detail position is clamped to the viewport. Tests cover cart hover, registered hammer details, mouse exit, close, equip/unequip and category/slot navigation; all passed. No old scene-path references remain in scenes.

## Explicit equipment action

City Storage item clicks now open the existing Inventory OptionPanel with Equip/Unequip and Cancel. Allocation occurs only after the action button is pressed. Escape, right-click, outside click, refresh and storage close dismiss the popup. Existing slot and backend ownership/working guards remain active. Hover details do not overlap the active action panel.

WorkerControlTest passed for click-without-mutation, cancellation, confirmed equip/return, and the existing nearby checks. Graphical action popup inspected. Existing certificate and shutdown warnings remain. Layout remains the requested compact Inventory-sized scene; no economy or tool data changes in this step.

## Basic Glove and slot versus requirement

Director approved Basic Glove as Primary but optional at Clay Site. Registered the supplied icon as `resources/items/basic_glove.tres`, added one physical test unit to the interactive Hauler fixture, and mapped it to Primary. It cannot share a Primary slot with Cart. A glove does not satisfy a Hauler's required Cart. No output bonus, price or durability balance was added; glove weight remains pending and is shown as - in City Storage.

Details label Primary items as EQUIP (Primary), other equipment as EQUIP. Stone Hammer remains in the previous temporary Secondary mapping; Mining/Stone Site requirements are not implemented by this change. Worksite requirements and equipment slots are distinct concepts.

WorkerControlTest passed for item registration, Primary mapping, optional equip/return, existing clay work without gloves, and category detail labels. Diff whitespace check passed.

## Hands and Tool prototype

Replaced Primary/Secondary presentation with Hands/Feet, changed the first Accessory to Body, retained Accessory, and added a scene-authored Tool card. Glove maps to Hands; Cart and Stone Hammer map to Tool. Details identify the actual slot instead of Primary. All cards open the existing City Storage action flow; Feet, Body and Accessory currently have no compatible items.

Hands and Tool can be equipped simultaneously. Tool occupancy prevents using Cart and Hammer together, physical units remain exclusive, and the Hauler cart requirement is unchanged. No stat bonuses were introduced. Existing local equipment uses tool IDs, so slot mapping is resolved from those IDs without deleting allocations.

WorkerControlTest passed including simultaneous glove/hammer and ownership rejection; ClayWorksiteHaulerTest passed. Updated Tools screen visually inspected and diff whitespace check passed. Existing shutdown warnings remain.

## Taller Hub layout reference

Preserved the Director's 330 x 200 WorkerControl size. Left equipment column is Tool, Body, Accessory; right is Hands, Feet, Accessory. Added the second Accessory card as a separate empty slot, connected to storage without inventing compatible items. Centered the worker preview vertically between both columns. Worker cards retain four columns with empty disabled cards up to three rows and a narrow persistent scrollbar. WorkerControlTest passed and rendered layout inspected.

## Go to opens worksite

Go to now closes Worker Hub and opens the assigned site's existing inspector through the same helper used by nearby interaction. Removed camera-offset navigation and its movement-triggered restoration. Player position and camera offset stay unchanged. Existing active-worker eligibility remains. Worksite close restores player movement, and Hub pause is released before opening the inspector.

WorkerControlTest passed for the actual Go to button, assigned ClaySiteA panel, unchanged player/camera, and restored controls after closing. Screenshot inspected. An obsolete camera process reference caused an initial parse failure; removed it and reran successfully. Existing shutdown warnings remain.

## Stable Tools feedback layout

Tools feedback and the Cart requirement keep reserved vertical space even when empty. Feedback allows two lines within the reserved area; additional text is ellipsized. Labels are no longer removed from container layout when feedback clears. Existing user panel styling is preserved.

WorkerControlTest passed with explicit position comparisons for the name, Tool card and preview anchor before clearing and after restoring the working-lock message. Graphical layout inspected; diff whitespace check passed. Existing shutdown warnings remain.

Correction: that position-only check missed the ToolsPage extending above its allotted space. The two reserved rows caused overlap with the tabs. Superseded by `worker-tools-feedback-layout-correction.md`, which uses one shared feedback area and tests containment as well as stability.
