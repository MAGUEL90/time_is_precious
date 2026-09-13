# Clay worksite compact cost display

Date: 2026-09-07
Status: PASSED — NEEDS HUMAN REVIEW
Branch: feature/process-workshop/clay-worksites
Risk: LEVEL 1 presentation change; existing local work preserved.

Following the latest playtest request:
- Added "How long will you work?" above the duration buttons.
- Replaced before/after condition bars in text with nominal cost only: Energy -3%,
  Satiety -6% for one hour; -9%/-18% for three hours at existing rates.
- Kept estimated clay output; removed normal time/stock/bag/ground details.
- Retained blocking reasons such as the worker requirement for twelve hours.
- Reduced the shared NinePatch to 240x140 normally, with room for blocking messages.
- Icons remain a later presentation step. Gameplay balance and execution are unchanged.

Cost preview now represents the duration's normal drain, independent of the current
bar value. Actual execution still checks conditions each minute and may stop early.
The user's -5% was an example, not a balancing change.

Modified inspector scene/script and their existing UI regression assertions.
Graphical ClayWorksiteInspectionTest passed at 1200x675; screenshot reviewed and
git diff --check clean. Existing certificate/shutdown warnings persist.
No commit, push, merge or unrelated file changes.
