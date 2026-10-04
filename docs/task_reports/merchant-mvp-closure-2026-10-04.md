# Merchant MVP scope closure — 2026-10-04

The Game Director explicitly skipped the proposed “What are you looking for?” dialogue and requested closure of this merchant work. Implementation scope is complete; status PASSED — NEEDS HUMAN REVIEW, with merge still reserved for the Game Director. PR #110 remains open; no merge or branch deletion performed.

Included: common visitor schedule, finite inventory/funds, randomized eligible purchase requests per visit, stable same-visit ledger, authoritative buy/sell and buyback quotas, weightless currency, compact natural greeting every interaction, themed transaction UI with Max/concise validation and matching Back/Buy/Sell buttons.

The two-item pool (wood 3–6, sun-dried mudbrick 10–20) is explicitly accepted for MVP. Additional goods, Rare tiers and city statistics remain deferred. No quest or extra needs dialogue added.

Latest gameplay commit: d95813b. Import and five final suites passed; random-request suite covered 20 visits/15 sampled profiles. Prior whole merchant playtest covered earned-resource sale, purchase, buyback and balances; exact-total legacy tests explicitly use a fixed profile. See merchant-full-playtest-2026-10-04.md and merchant-random-requests-2026-10-04.md. No gameplay changes in this closure commit, so tests were not rerun.

Limits remain as documented: session continuity is not disk saving, prices/quotas are provisional, and automated Linux/graphical checks do not establish Windows/Android manual acceptance. Broader game progression is outside this merchant closure.
