# Clay worksite interruption message

Date: 2026-09-07
Branch: feature/process-workshop/clay-worksites
Status: PASSED — NEEDS HUMAN REVIEW
Scope: approved interruption feedback in the isolated fixture; local changes preserved.

During the existing one-second blackout, interrupted work now displays one centered message:
"Too exhausted to continue." followed by "Worked 25 min." for a collapse after 25 minutes.
Other interruptions use "Work interrupted." with actual elapsed minutes.
Successful work has no message. The label clears with the fade; duplicate fixture-result
notes are hidden after interruption. Existing collapse retains control after the modal closes.

Output rules are unchanged: completed ten-minute cycles only, inventory first, exact overflow
stack to ground. No extra end-of-work cost, reward popup, or change to Player/Nightmare code.

Files: fixture script/scene, existing gathering regression test, and this report.
Graphical gathering regression passed at 1200x675, including actual collapse at minute 25,
one visible message, two clay in a single ground stack with a full bag, message cleanup,
no success message and pause restoration. Screenshot reviewed.
Inspection regression and main launch smoke passed; git diff --check clean.
Existing certificate-store and shutdown resource warnings remain.
Full Nightmare entry/return is not validated in this isolated test; the test stops after
handoff to collapse. No commit, push or merge.
