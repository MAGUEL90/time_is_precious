# Worksite worker-card layout

2026-09-08 — PASSED — NEEDS HUMAN REVIEW.

The inherited worker grid had a fixed three-column setting. The worksite adapter now
calculates columns from available scroll width, scrollbar width, card size and separation,
refreshing after population and resize. Cards fill horizontally before wrapping.
The extra locked placeholder is omitted; only the two actual assignment slots remain.
Shared workshop assets/builders and production workshop behavior are unchanged.

Modified adapter and existing team regression. Graphical test passed at 1200x675:
two overview slots, at least four candidate columns, fourth candidate on the first row,
and selection/capacity checks. Both screenshots reviewed; git diff --check clean.
Existing certificate/shutdown warnings persist. Local edits preserved; no commit/merge.
