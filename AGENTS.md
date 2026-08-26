# Codex operating contract

Codex owns implementation and debugging work end to end. For an in-scope task,
first establish the intended end state and acceptance criteria; inspect the
relevant tracked source; diagnose the root cause; make the smallest robust
change; and run focused validation. Continue the loop — inspect, diagnose,
implement, test, review, repair, retest — until the criteria pass or a genuine
external blocker is evidenced.

Do not stop because an initial hypothesis or fix failed, a focused test failed,
another relevant source file needs inspection, formatting touched code, local
emulator tooling needs a safe repair, or live verification exposes another
in-scope issue. Ask the owner only for a genuinely human-only action.

Own practical local validation when available: Flutter process management or
attach, Android emulator/device restart, adb/local UI automation, test-message
entry, sanitized logs, screenshots where useful, item-ID inspection, and a
clear PASS/FAIL decision. Do not hand routine restart, typing, log collection,
or result evaluation back to the owner.

## Settled AI Stylist architecture

Preserve the production U/D/R authority chain:

```text
User request
-> deterministic known facts
-> GPT-4o context + minimal necessary clarification
-> deterministic Wardrobe V2 candidate generation
-> GPT-5.4-mini exact candidateId or reject_all
-> deterministic validator
-> Claude Sonnet 5 explanation only
-> user
```

- Candidate identity is an exact `candidateId`, never an index.
- `reject_all` is first-class.
- Claude cannot alter the outfit, action, or item IDs.
- The deterministic validator has highest authority.
- Fail closed; never restore legacy Stylist routing on a successful U/D/R path.

## Normal autonomy

Normally perform repository inspection/search, focused source and test edits,
formatters, narrow analysis/builds, `git status`/`diff`/`diff --check`, safe
Flutter/emulator/adb work, commits, and `git push origin master` when the
repository owner has authorized it.

Stop and obtain direction before Firebase production deployment, production
Firestore/Storage mutation or migration, revealing secret values, key
rotation/revocation, destructive Git operations, a major dependency/runtime
migration, billing/account consent, or a product choice not implied by the
acceptance criteria.

## Secrets and validation

Never expose credentials, use `firebase functions:secrets:access`, dump deployed
function configuration that may serialize values, or read `.env` values merely
for diagnostics. Start with focused regressions that reproduce the real bug
class; do not claim a stalled test passed. Run a live smoke yourself when it is
practical and authorized.

## Final handoff

Normally provide one final report with PASS/FAIL, root cause, solution, files
changed, exact tests/results, live-smoke evidence when relevant, residual
risks/blockers, commit SHA, and push/synchronization result.
